# AIOMetadata — Complete Implementation Guide

> Everything you need to build your own Stremio metadata addon from scratch.
> Covers all 15+ providers, 85+ routes, caching, ID mapping, and the full data pipeline.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Stremio Addon Protocol](#2-stremio-addon-protocol)
3. [All API Routes](#3-all-api-routes)
4. [Metadata Assembly Pipeline](#4-metadata-assembly-pipeline)
5. [Search System](#5-search-system)
6. [Episode Assembly](#6-episode-assembly)
7. [Provider: TMDB](#7-provider-tmdb)
8. [Provider: TVDB](#8-provider-tvdb)
9. [Provider: Jikan/MAL](#9-provider-jikanmal)
10. [Provider: AniList](#10-provider-anilist)
11. [Provider: Kitsu](#11-provider-kitsu)
12. [Provider: TVmaze](#12-provider-tvmaze)
13. [Provider: IMDb / Cinemeta](#13-provider-imdb--cinemeta)
14. [Provider: Fanart.tv](#14-provider-fanarttv)
15. [Provider: RPDB / TopPoster](#15-provider-rpdb--topposter)
16. [Catalog: Trakt](#16-catalog-trakt)
17. [Catalog: SimKL](#17-catalog-simkl)
18. [Catalog: MDBList](#18-catalog-mdblist)
19. [Catalog: Letterboxd](#19-catalog-letterboxd)
20. [ID Mapping System](#20-id-mapping-system)
21. [ID Resolution Algorithm](#21-id-resolution-algorithm)
22. [Anime Detection](#22-anime-detection)
23. [Caching System](#23-caching-system)
24. [Database Schema](#24-database-schema)
25. [Image Selection Logic](#25-image-selection-logic)
26. [Search Result Ranking](#26-search-result-ranking)
27. [Per-User Configuration](#27-per-user-configuration)
28. [Manifest Generation](#28-manifest-generation)
29. [Catalog Routing](#29-catalog-routing)
30. [Data Transformation (parseProps)](#30-data-transformation-parseprops)
31. [Pseudocode: Full Request Flow](#31-pseudocode-full-request-flow)

---

## 1. Architecture Overview

```
                    Stremio App
                        |
                   HTTP JSON API
                        |
              +-------------------+
              |   Express Server  |
              |   (index.js)      |
              +-------------------+
              |   Routes:         |
              |   /manifest.json  |
              |   /catalog/...    |
              |   /meta/...       |
              |   /stream/...     |
              +--------+----------+
                       |
          +------------+-------------+
          |            |             |
     getCatalog    getMeta      getSearch
          |            |             |
          +-----+------+------+-----+
                |             |
         +------+------+ +---+---+
         | ID Resolver | | Cache |
         +------+------+ +---+---+
                |             |
    +-----------+-----------+ |
    |     |     |     |     | |
   TMDB  TVDB  MAL  AniList Redis
   IMDb  Kitsu TVmaze Fanart
   RPDB  Trakt SimKL  MDBList
```

**Stack**: Node.js 20 + Express + React/Vite + Redis + SQLite/PostgreSQL

**Key files**:
- `addon/index.js` — Express server, all 85+ routes (5873 lines)
- `addon/lib/getMeta.js` — Metadata orchestrator
- `addon/lib/getSearch.js` — Search orchestrator
- `addon/lib/getEpisodes.js` — TMDB episode assembly
- `addon/lib/getCache.js` — Multi-layer caching system (2600 lines)
- `addon/lib/getCatalog.ts` — Catalog routing
- `addon/lib/getManifest.js` — Per-user manifest generation
- `addon/lib/id-mapper.js` — Anime ID mapping database
- `addon/lib/id-resolver.js` — Cross-provider ID resolution
- `addon/utils/parseProps.js` — Data transformation utilities (3400 lines)

---

## 2. Stremio Addon Protocol

Stremio addons are simple HTTP JSON APIs. The addon declares capabilities via a manifest, then serves catalog listings, metadata, and optionally streams.

### Manifest Structure

```json
{
  "id": "com.aio.metadata",
  "version": "1.31.0",
  "name": "AIO Metadata",
  "description": "All-in-one metadata provider",
  "types": ["movie", "series"],
  "catalogs": [
    {
      "type": "movie",
      "id": "tmdb.trending",
      "name": "Trending Movies",
      "extra": [
        { "name": "genre", "isRequired": false, "options": ["Action", "Comedy", ...] },
        { "name": "skip", "isRequired": false }
      ]
    }
  ],
  "resources": ["catalog", "meta"],
  "idPrefixes": ["tt", "tmdb:", "tvdb:", "mal:", "kitsu:", "anilist:", "anidb:"],
  "behaviorHints": {
    "configurable": true,
    "configurationRequired": false
  }
}
```

### Stremio Meta Object (Final Output)

This is what every `/meta/:type/:id.json` endpoint must return:

```json
{
  "meta": {
    "id": "tt1234567",
    "type": "movie",
    "name": "Movie Title",
    "poster": "https://image.tmdb.org/t/p/w500/abc.jpg",
    "background": "https://image.tmdb.org/t/p/original/xyz.jpg",
    "logo": "https://assets.fanart.tv/fanart/movies/123/hdmovielogo/logo.png",
    "description": "Plot summary here...",
    "releaseInfo": "2024",
    "runtime": "2h 15min",
    "genres": ["Action", "Sci-Fi"],
    "director": ["Director Name"],
    "cast": ["Actor 1", "Actor 2"],
    "writer": ["Writer Name"],
    "imdbRating": "8.5",
    "country": "United States",
    "language": "English",
    "trailers": [{ "source": "youtubeVideoId", "type": "Trailer" }],
    "trailerStreams": [{ "title": "Trailer Name", "ytId": "youtubeVideoId" }],
    "links": [
      { "name": "8.5", "category": "imdb", "url": "https://imdb.com/title/tt1234567" },
      { "name": "PG-13", "category": "Genres", "url": "stremio:///..." },
      { "name": "Action", "category": "Genres", "url": "stremio:///discover/..." },
      { "name": "Actor Name", "category": "Cast", "url": "stremio:///search?search=..." }
    ],
    "behaviorHints": { "defaultVideoId": "tt1234567", "hasScheduledVideos": false },
    "videos": [
      {
        "id": "tt1234567:1:1",
        "season": 1,
        "number": 1,
        "episode": 1,
        "title": "Pilot",
        "overview": "Episode description",
        "released": "2024-01-15T00:00:00.000Z",
        "thumbnail": "https://image.tmdb.org/t/p/w500/still.jpg"
      }
    ]
  }
}
```

### Supported Stremio ID Formats

| Prefix | Example | Content Type |
|--------|---------|--------------|
| `tt` (IMDb) | `tt1234567` | movie/series/anime |
| `tmdb:` | `tmdb:12345` | movie/series/anime |
| `tvdb:` | `tvdb:12345` | series/movie |
| `tvdbc:` | `tvdbc:12345` | TVDB collection |
| `tvmaze:` | `tvmaze:12345` | series |
| `mal:` | `mal:12345` | anime |
| `kitsu:` | `kitsu:12345` | anime |
| `anidb:` | `anidb:12345` | anime |
| `anilist:` | `anilist:12345` | anime |

---

## 3. All API Routes

### Stremio Core Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/stremio/manifest.json` | Static default manifest (no catalogs) |
| GET | `/stremio/:uuid/manifest.json` | Per-user manifest with configured catalogs |
| GET | `/stremio/:uuid/catalog/:type/:id/:extra?.json` | Catalog listings (paginated) |
| GET | `/stremio/:uuid/meta/:type/:id.json` | Full metadata for one item |
| GET | `/stremio/:uuid/stream/:type/:id.json` | Rating button stream (optional) |
| GET | `/stremio/:uuid/subtitles/:type/:id/:extra?.json` | Watch tracking hook |

**Cache headers**:
- Manifest: `no-cache, no-store, must-revalidate, max-age=0, s-maxage=0`
- Catalog/Meta: `no-cache, must-revalidate, max-age=0`
- All responses include ETag: `MD5(ADDON_VERSION + JSON.stringify(data) + userUUID + configHash)`

### Configuration Routes

| Method | Path | Body/Params | Purpose |
|--------|------|-------------|---------|
| GET | `/api/config` | — | Get public env config (which API keys are set) |
| POST | `/api/config/save` | `{ config }` | Save new user config, returns UUID |
| POST | `/api/config/load/:uuid` | — | Load user config from DB |
| PUT | `/api/config/update/:uuid` | `{ config }` | Update user config |
| POST | `/api/config/migrate` | `{ config }` | Migrate localStorage config to DB |
| GET | `/api/config/is-trusted/:uuid` | — | Check if user is trusted |
| POST | `/api/test-keys` | `{ apiKeys }` | Validate API keys (rate limited: 60/min) |

### OAuth Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/auth/trakt/authorize` | Initiate Trakt OAuth (CSRF state, 10 min TTL) |
| GET | `/api/auth/trakt/callback` | Exchange code for token, save to DB |
| POST | `/api/auth/trakt/disconnect` | Delete Trakt token |
| POST | `/api/trakt/proxy` | Proxy GET calls to Trakt API |
| GET | `/api/auth/simkl/authorize` | Initiate SimKL OAuth |
| GET | `/api/auth/simkl/callback` | Exchange code, save token (never expires) |
| POST | `/api/auth/simkl/disconnect` | Delete SimKL token |
| POST | `/api/simkl/users/stats` | Proxy SimKL user stats |
| GET | `/anilist/auth` | Initiate AniList OAuth |
| GET | `/anilist/callback` | Exchange AniList code |
| GET | `/anilist/status/:uuid` | Check AniList auth status |
| POST | `/api/oauth/token/info` | Get token metadata (provider, username, expiry) |

### Provider Proxy Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tmdb/list/:listId` | Fetch TMDB list details |
| GET | `/api/tmdb/discover/reference` | TMDB genres, languages, certifications |
| GET | `/api/tmdb/discover/providers` | Streaming providers by region |
| GET | `/api/tmdb/discover/search/:entity` | Search person/company/keyword |
| GET | `/api/tmdb/discover/preview` | Live discover preview |
| POST | `/api/tmdb/auth/request_token` | TMDB auth token |
| POST | `/api/tmdb/auth/session` | Create TMDB session |
| GET | `/api/tvdb/discover/reference` | TVDB genres, languages, etc. |
| GET | `/api/tvdb/discover/search/:entity` | Search TVDB companies |
| GET | `/api/tvdb/discover/preview` | TVDB discover preview |
| GET | `/api/anilist/discover/reference` | AniList tags |
| GET | `/api/anilist/discover/search/studio` | Search AniList studios |
| POST | `/api/anilist/discover/preview` | AniList discover preview |
| GET | `/api/mal/discover/reference` | MAL genres + studios |
| GET | `/api/mal/discover/search/producer` | Search MAL producers |
| GET | `/api/mal/discover/preview` | MAL discover preview |
| GET | `/api/simkl/discover/preview` | SimKL discover preview |
| GET | `/api/mdblist/lists/user` | Proxy MDBList user lists |
| GET | `/api/mdblist/lists/top` | Proxy MDBList top lists |
| GET | `/api/mdblist/lists/:username/:listname` | Proxy specific list |
| GET | `/api/mdblist/lists/:listId` | Proxy list by ID |
| GET | `/api/mdblist/external/lists/user` | Proxy external lists |
| POST | `/api/letterboxd/extract-identifier` | Extract Letterboxd identifier from URL |
| POST | `/api/letterboxd/list` | Fetch Letterboxd list data |
| GET | `/api/trakt/users/:username/stats` | Trakt user stats |
| GET | `/api/trakt/users/:username/lists` | Trakt user lists |
| GET | `/api/trakt/lists/trending/:type` | Trakt trending lists |
| GET | `/api/trakt/lists/popular/:type` | Trakt popular lists |

### Utility Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Health check (`{ status, timestamp, version, checks }`) |
| GET | `/api/image/blur` | Proxy + Gaussian blur image via Sharp |
| GET | `/api/version` | Version info |
| GET | `/api/providers/status` | Which API keys are configured |
| GET | `/api/admin/stats` | Cache stats, uptime, memory |
| GET | `/api/admin/cache/stats` | Redis metrics |
| POST | `/api/admin/cache/clear` | Clear all caches |
| POST | `/api/admin/cache/clear/:pattern` | Clear by key pattern |

---

## 4. Metadata Assembly Pipeline

### Entry Point: `getMeta(type, language, stremioId, config, userUUID, includeVideos)`

**Step 1 — Parse the Stremio ID**:
```
"tt1234567"    → { imdbId: "tt1234567" }
"tmdb:12345"   → { tmdbId: "12345" }
"tvdb:789"     → { tvdbId: "789" }
"mal:456"      → { malId: "456" }
"kitsu:123"    → { kitsuId: "123" }
"anilist:789"  → { anilistId: "789" }
"tun_tt123"    → { imdbId: "tt123" }  (strip prefix, re-add to output)
```

**Step 2 — Detect anime**:
- Check if ID prefix is `mal:`, `kitsu:`, `anidb:`, `anilist:` → always anime
- Check `idMapper` (anime-list-full.json) for IMDb/TMDB/TVDB IDs
- Check Trakt anime movies mapping
- If anime detected: `finalType = 'anime'`

**Step 3 — Determine providers needed**:
```
preferredProvider:
  movie  → config.providers.movie  || 'tmdb'
  series → config.providers.series || 'tvdb'
  anime  → config.providers.anime  || 'mal'

targetProviders = Set([preferredProvider, 'imdb'])
  + providers needed by art providers (poster/bg/logo config):
    fanart → movie: ['tmdb','imdb'], series: ['tvdb']
    tmdb   → ['tmdb']
    tvdb   → ['tvdb']
```

**Step 4 — Resolve all IDs**:
```
resolveAllIds(stremioId, type, config, {}, Array.from(targetProviders))
→ { imdbId, tmdbId, tvdbId, tvmazeId, malId, kitsuId, anilistId, anidbId }
```

**Step 5 — Dispatch to type-specific handler**:

### Movie Meta — Provider Cascade

```
1. preferredProvider === 'tvdb' && tvdbId
   → tvdb.getMovieExtended(tvdbId)
   → buildTvdbMovieResponse()

2. preferredProvider === 'imdb' && imdbId
   → cinemeta.getMetaFromImdb(imdbId, 'movie')
   → buildImdbMovieResponse()

3. tmdbId available (TMDB fallback — most common path)
   → moviedb.movieInfo({
       id: tmdbId,
       language: language,
       append_to_response: "videos,credits,external_ids,images,translations,watch/providers,release_dates",
       include_image_language: "${langCode},en,null",
       include_video_language: "${langCode},en,null"
     })
   → buildTmdbMovieResponse()

4. All providers failed → return { meta: null }
```

### Series Meta — Provider Cascade

```
1. preferredProvider === 'tmdb' && tmdbId
   → moviedb.tvInfo({
       id: tmdbId,
       language: language,
       append_to_response: "videos,credits,external_ids,images,translations,watch/providers,content_ratings"
     })
   → Fetch seasons in batches of 20: tvInfo({ append_to_response: "season/1,...,season/20" })
   → buildTmdbSeriesResponse()

2. preferredProvider === 'imdb' && imdbId
   → cinemeta.getMetaFromImdb(imdbId, 'series')
   → Augment with TMDB certification + trailers if tmdbId available
   → buildImdbSeriesResponse()

3. preferredProvider === 'tvmaze' && tvmazeId
   → [tvmaze.getShowDetails(id), tvmaze.getShowEpisodes(id)] in parallel
   → buildSeriesResponseFromTvmaze()

4. tvdbId available (TVDB fallback)
   → [tvdb.getSeriesExtended(id), tvdb.getSeriesEpisodes(id, lang, seasonType)] in parallel
   → buildTvdbSeriesResponse()

5. All providers failed → return { meta: null }
```

### Anime Meta — Provider Cascade

```
1. Non-anime-specific provider set → try TMDB/TVDB/TVmaze/IMDB cascades above

2. kitsuId available (and preferred or MAL not preferred)
   → kitsu.getMultipleAnimeDetails([kitsuId], 'genres,episodes,mediaRelationships.destination')
   → getAnimeArtwork(allIds, config) in parallel
   → buildKitsuAnimeResponse()

3. malId available (ultimate fallback)
   → Promise.all([
       jikan.getAnimeDetails(malId),
       jikan.getAnimeCharacters(malId),      // if includeVideos
       jikan.getAnimeEpisodes(malId)          // if includeVideos, 24h cache
     ])
   → getAnimeArtwork(allIds, config) in parallel
   → buildAnimeResponse()
```

### Anime Artwork Resolution (parallel)

```javascript
Promise.all([
  getAnimeBg({ tvdbId, tmdbId, malId, imdbId }, config),         // background
  getAnimePoster({ malId, imdbId, tvdbId, tmdbId }, config),     // poster
  getAnimeLogo({ malId, imdbId, tvdbId, tmdbId }, config),       // logo
  getImdbRating(imdbId, type),                                    // rating
  getAnimeBg({ ... }, config, true)                               // landscapePoster
])
```

---

## 5. Search System

### Entry Point: `getSearch(id, type, language, extra, config)`

Routes by search `id`:

| Search ID | Handler |
|-----------|---------|
| `search` | Routes to configured search engine per type |
| `mal.genre_search` | `jikan.getAnimeByGenre()` |
| `mal.va_search` | `jikan.getAnimeByVoiceActor()` |
| `tvdb_collections_search` | `performTvdbCollectionsSearch()` |
| `gemini.search` | `performAiSearch()` (Google Gemini) |
| `people_search` | `performTmdbPeopleSearch()` / `performTvdbPeopleSearch()` / `performTraktPeopleSearch()` |

### TMDB Search Pipeline (4 steps)

**Step 1 — Gather IDs in parallel**:
```javascript
Promise.all([
  // Title search
  type === 'movie'
    ? moviedb.searchMovie({ query, language, include_adult, page })
    : moviedb.searchTv({ query, language, include_adult, page }),

  // Person search (skip if query has special chars)
  shouldSearchPersons
    ? moviedb.searchPerson({ query, language })
        .then(res => {
          // Validate top person: popularity >= 1.5, quality work votes >= 4000
          // If valid: fetch personMovieCredits/personTvCredits
        })
    : Promise.resolve([])
])
```

Special case: if query matches `/^tt\d{7,8}$/i`, uses `moviedb.find({ id, external_source: 'imdb_id' })`.

**Step 2 — Sort + Hydrate top 25**:
```javascript
sorted = sortSearchResults(rawResults, query).slice(0, 25)

// Per item (parallel):
details = moviedb.movieInfo/tvInfo({
  id, language,
  append_to_response: "external_ids,release_dates,images,translations,keywords"
})
allIds = resolveAllIds(`tmdb:${id}`, type, config, {}, ['imdb'])
imdbRating = getImdbRating(allIds.imdbId, type)
```

**Step 3 — Filter adult content by keywords**:
Removes items with keywords: `['porn', 'porno', 'soft porn', 'softcore', 'pinku-eiga']`

**Step 4 — Age rating + digital release filters**:
- Movie hierarchy: `G < PG < PG-13 < R < NC-17`
- TV hierarchy: `TV-Y < TV-Y7 < TV-G < TV-PG < TV-14 < TV-MA`
- `hideUnreleasedDigitalSearch`: filters movies without digital release dates

### Post-Search Filters (applied to all engines)

```javascript
// Content exclusion (user-configured)
filterMetasByRegex(metas, exclusionKeywords, regexExclusionFilter)

// Remove invalid entries
metas.filter(m => m.id && m.name && m.type)
```

---

## 6. Episode Assembly

### TMDB Episodes: `getEpisodes(language, tmdbId, imdb_id, seasons, config)`

**Standard flow**:
```javascript
// Batch seasons in groups of 20
batches = genSeasonsString(seasons)
// e.g., ["season/1,season/2,...,season/20", "season/21,..."]

// Per batch (parallel):
moviedb.tvInfo({
  id: tmdbId,
  language: language,
  append_to_response: "season/1,season/2,..."
})
// Extract res["season/N"].episodes
```

**Episode ID format**:
- With IMDb ID: `"${imdb_id}:${season}:${index + 1}"`
- Without IMDb ID: `"tmdb:${tmdbId}:${season}:${index + 1}"`

**Episode object**:
```json
{
  "id": "tt1234567:1:5",
  "name": "Episode Name",
  "season": 1,
  "number": 5,
  "episode": 5,
  "thumbnail": "https://image.tmdb.org/t/p/w500/still.jpg",
  "overview": "Episode description",
  "description": "Episode description",
  "rating": "8.5",
  "firstAired": "2024-01-15T00:00:00.001Z",
  "released": "2024-01-15T00:00:00.001Z"
}
```

**Thumbnail handling**:
- `hideEpisodeThumbnails === true`: routes through `/api/image/blur?url=${encoded}`
- Normal: `https://image.tmdb.org/t/p/w500${still_path}`
- Missing: `${host}/missing_thumbnail.png`

**Special overrides** (JSON config files):
- `diferentOrder.json` — maps tmdbId to custom episode group ordering
- `diferentImdbId.json` — substitutes different IMDb IDs for episode ID building

---

## 7. Provider: TMDB

**Base URL**: `https://api.themoviedb.org/3`

**Auth**: API key as query param `?api_key=XXX`
- Key from: `config.apiKeys?.tmdb` || `process.env.TMDB_API` || `process.env.BUILT_IN_TMDB_API_KEY`

**HTTP Client**: `undici` fetch. Supports SOCKS5 proxy (`TMDB_SOCKS_PROXY_URL`).
- Connection timeout: 10s
- Request timeout: 15s via `AbortSignal.timeout(15000)`

### Rate Limiting / Retry

- Max 3 retries
- **429**: reads `retry-after` header (seconds), waits `(retryAfter * 1000) + 50ms`
- **Non-retryable** (immediate fail): `400, 401, 403, 404, 422`
- **404**: returns `null` (not an error)
- **Retryable**: 429, 5xx, undici network errors
- **Backoff**: `1000 * 2^(attempt-1)` ms

### All Endpoints

| Function | Endpoint | Notes |
|----------|----------|-------|
| `movieInfo` | `GET /movie/{id}` | Pass-through query params |
| `tvInfo` | `GET /tv/{id}` | Pass-through query params |
| `movieExternalIds` | `GET /movie/{id}/external_ids` | Cached 24h |
| `tvExternalIds` | `GET /tv/{id}/external_ids` | Cached 24h |
| `movieCredits` | `GET /movie/{id}/credits` | |
| `tvCredits` | `GET /tv/{id}/credits` | |
| `searchMovie` | `GET /search/movie?query=...` | |
| `searchTv` | `GET /search/tv?query=...` | |
| `searchPerson` | `GET /search/person?query=...` | |
| `personInfo` | `GET /person/{id}` | |
| `personMovieCredits` | `GET /person/{id}/movie_credits` | |
| `personTvCredits` | `GET /person/{id}/tv_credits` | |
| `find` | `GET /find/{id}?external_source=...` | IMDb→TMDB resolution |
| `discoverMovie` | `GET /discover/movie` | Genre/year/rating filters |
| `discoverTv` | `GET /discover/tv` | |
| `genreMovieList` | `GET /genre/movie/list` | Cached 30 days |
| `genreTvList` | `GET /genre/tv/list` | Cached 30 days |
| `trending` | `GET /trending/{type}/{window}` | day/week |
| `seasonInfo` | `GET /tv/{id}/season/{n}` | Cached 24h |
| `movieImages` / `tvImages` | `GET /{type}/{id}/images` | Cached 24h |
| `getMovieCertifications` | `GET /movie/{id}/release_dates` | Cached 24h |
| `getTvCertifications` | `GET /tv/{id}/content_ratings` | Cached 24h |
| `getMovieWatchProviders` | `GET /movie/{id}/watch/providers` | Cached 24h |
| `getTvWatchProviders` | `GET /tv/{id}/watch/providers` | Cached 24h |
| `requestToken` | `GET /authentication/token/new` | |
| `sessionId` | `POST /authentication/session/new` | |

### Common `append_to_response` Combos

For full movie meta:
```
videos,credits,external_ids,images,translations,watch/providers,release_dates
```

For full series meta:
```
videos,credits,external_ids,images,translations,watch/providers,content_ratings
```

For search result hydration:
```
external_ids,release_dates,images,translations,keywords
```

For season batching:
```
season/1,season/2,...,season/20
```

### Image URL Patterns

```
Poster:     https://image.tmdb.org/t/p/w500{file_path}
Poster HD:  https://image.tmdb.org/t/p/w600_and_h900_bestv2{file_path}
Background: https://image.tmdb.org/t/p/original{file_path}
Logo:       https://image.tmdb.org/t/p/original{file_path}
Cast photo: https://image.tmdb.org/t/p/w276_and_h350_face{profile_path}
```

### IMDb ID Enrichment (when missing from TMDB)

If TMDB response lacks `imdb_id`:
1. Try `name-to-imdb` npm package: `nameToImdb({ name, type, year, strict: true })`
2. If that fails and `config.tmdb.scrapeImdb` is set: scrape IMDb search page

---

## 8. Provider: TVDB

**Base URL**: `https://api4.thetvdb.com/v4`

**Image Base**: `https://artworks.thetvdb.com/banners/images/`

### Auth Flow

```
POST /login
  Body: { "apikey": "<key>" }
  Response: { "data": { "token": "jwt..." } }

All subsequent requests:
  Header: Authorization: Bearer <token>
```

- Token cached in memory with 28-day expiry
- Two tiers: global `tokenCache` (self-hosted) and per-user `userTokenCaches` (public instances)
- Key from: `config.apiKeys?.tvdb` || `process.env.TVDB_API_KEY`

### Rate Limiting / Retry

- Retry on 429 with exponential backoff: `min(1000 * 2^attempt, 30000)` ms, max 3 retries
- 404 returns `{ data: { data: null } }` (not an error)

### All Endpoints

| Function | Endpoint | Cache |
|----------|----------|-------|
| `searchSeries` | `GET /search?query={q}&type=series` | — |
| `searchMovies` | `GET /search?query={q}&type=movie` | — |
| `searchPeople` | `GET /search?query={q}&type=people` | — |
| `searchCompanies` | `GET /search?query={q}&type=company&limit=25` | — |
| `searchCollections` | `GET /search?query={q}&type=list` | — |
| `getSeriesExtended` | `GET /series/{id}/extended?meta=translations` | `cacheWrapTvdbApi` |
| `getMovieExtended` | `GET /movies/{id}/extended?meta=translations` | `cacheWrapTvdbApi` |
| `getPersonExtended` | `GET /people/{id}/extended` | — |
| `getSeriesEpisodes` | `GET /series/{id}/episodes/{seasonType}/{lang}?page={n}` | `cacheWrapTvdbApi` |
| `findByImdbId` | `GET /search/remoteid/{imdbId}` | — |
| `findByTmdbId` | `GET /search/remoteid/{tmdbId}` | — |
| `getAllGenres` | `GET /genres` | — |
| `getAllLanguages` | `GET /languages` | `cacheWrapTvdbApi` |
| `getAllCountries` | `GET /countries` | `cacheWrapTvdbApi` |
| `getAllContentRatings` | `GET /content/ratings` | `cacheWrapTvdbApi` |
| `filter` | `GET /{type}/filter?{params}` | `cacheWrapTvdbApi` |
| `getSeasonExtended` | `GET /seasons/{id}/extended` | `cacheWrapTvdbApi` |
| `getCollectionDetails` | `GET /lists/{id}/extended` | `cacheWrapTvdbApi` |
| `getCollectionTranslations` | `GET /lists/{id}/translations/{lang}` | `cacheWrapTvdbApi` |

### Artwork Type IDs

| Type ID | Artwork Type |
|---------|-------------|
| 2 | Series poster |
| 3 | Series/movie background |
| 14 | Movie poster |
| 15 | Movie background (fallback to 3) |
| 23 | Series logo |
| 25 | Movie logo |

### Artwork Selection: `findArtwork(artworks, type, lang, config)`

```
If englishArtOnly → prefer lang='eng'
Otherwise: target lang → 'eng' → any
Within language: sort by score descending → pick first
```

### Episode Pagination

Fetches pages sequentially (`page=0,1,2...`), continues while `data.links.next` is truthy. Fallback chain: requested `seasonType` → `'official'` → language `'en-US'`.

---

## 9. Provider: Jikan/MAL

**Base URL**: `process.env.JIKAN_API_BASE || 'https://api.jikan.moe/v4'`

**Auth**: None (public API)

**HTTP Client**: `undici` with optional SOCKS5 proxy (`MAL_SOCKS_PROXY_URL`). Connection timeout: 30s. Request timeout: 15s.

### Rate Limiting (Critical)

```
MAX_CONCURRENT = env.JIKAN_MAX_CONCURRENT || 2
MIN_REQUEST_INTERVAL = env.JIKAN_MIN_INTERVAL || 350ms
MAX_REQUESTS_PER_MINUTE = env.JIKAN_MAX_PER_MINUTE || 55  (Jikan limit is 60/min)
MAX_RETRIES = 3
RATE_LIMIT_DELAY = 2000ms (base for 429 backoff)
```

**Queue system**: All requests go through a priority queue. Enforces:
1. Per-minute sliding window (150ms safety buffer)
2. Per-dispatch minimum interval

**Adaptive concurrency**:
- On 429: drops to 1 concurrent request
- Restores after 30s without 429: increments by 1 up to `MAX_CONCURRENT`

**429 backoff**:
- Base: `2^(retries-1) * 2000ms`
- Scaled by recent hits: `>10 → *2.5`, `>5 → *1.8`
- Plus jitter: `random() * 300ms`

**ETag caching**: Stores ETags + response bodies in Redis (25h TTL). On 304: returns cached body.

### All Endpoints

| Function | Endpoint |
|----------|----------|
| `searchAnime` | `GET /anime?q={query}&limit={n}&page={n}&type={movie\|tv}&sfw={bool}` |
| `getAnimeDetails` | `GET /anime/{malId}/full` |
| `getAnimeEpisodes` | `GET /anime/{malId}/episodes?page={n}` (all pages) |
| `getAnimeEpisodeVideos` | `GET /anime/{malId}/videos/episodes?page={n}` (all pages) |
| `getAnimeCharacters` | `GET /anime/{malId}/characters` |
| `getAnimeByVoiceActor` | `GET /people/{personId}/full` → extracts `data.voices` |
| `getAiringSchedule` | `GET /schedules?filter={day}&page={n}&sfw={bool}` |
| `getAiringNow` | `GET /seasons/now?page={n}&sfw={bool}` |
| `getUpcoming` | `GET /seasons/upcoming?page={n}&sfw={bool}` |
| `getAnimeByGenre` | `GET /anime?genres={id}&order_by=members&sort=desc&page={n}&type={tv\|movie}&sfw={bool}` |
| `getAnimeGenres` | `GET /genres/anime` |
| `getTopAnimeByType` | `GET /top/anime?type={movie\|tv\|ova\|ona}&page={n}&sfw={bool}` |
| `getTopAnimeByFilter` | `GET /top/anime?filter={filter}&page={n}&sfw={bool}` |
| `getTopAnimeByDateRange` | `GET /anime?start_date={}&end_date={}&order_by=members&sort=desc&page={n}` |
| `getStudios` | `GET /producers?order_by=favorites&sort=desc` |
| `getAnimeByStudio` | `GET /anime?producers={id}&order_by=members&sort=desc&page={n}&limit={n}` |
| `getAnimeBySeason` | `GET /seasons/{year}/{season}?page={n}&sfw={bool}` |
| `getAvailableSeasons` | `GET /seasons` |
| `fetchDiscover` | `GET /anime?{dynamic params}` |

### Key Fields from Jikan Response

```json
{
  "data": {
    "mal_id": 1,
    "title": "...",
    "title_english": "...",
    "title_japanese": "...",
    "type": "TV",
    "episodes": 26,
    "status": "Finished Airing",
    "score": 8.75,
    "scored_by": 123456,
    "rank": 28,
    "popularity": 3,
    "members": 2000000,
    "synopsis": "...",
    "year": 1998,
    "season": "spring",
    "genres": [{ "mal_id": 1, "name": "Action" }],
    "studios": [{ "mal_id": 14, "name": "Sunrise" }],
    "images": {
      "jpg": { "image_url": "...", "large_image_url": "..." },
      "webp": { "image_url": "...", "large_image_url": "..." }
    },
    "trailer": { "youtube_id": "...", "url": "..." },
    "relations": [{ "relation": "Sequel", "entry": [{ "mal_id": 5, "type": "anime", "name": "..." }] }]
  }
}
```

---

## 10. Provider: AniList

**Base URL**: `https://graphql.anilist.co`

**Auth**: Unauthenticated for reads. `Authorization: Bearer <token>` for mutations.

**HTTP**: All requests are `POST` with body `{ query, variables }`.

### Rate Limiting

```
limit: 30 requests (degraded; normally 90)
minInterval: 2000ms between requests
Sequential queue (single processor, FIFO)
```

On 429: reads `retry-after` or `x-ratelimit-reset` header, waits accordingly. Max 3 retries.

### Key GraphQL Queries

**Get anime details by MAL ID** (used for artwork):
```graphql
query ($malId: Int) {
  Media(idMal: $malId, type: ANIME) {
    id idMal
    title { romaji english native }
    coverImage { large medium color }
    bannerImage description type format status episodes
    duration genres averageScore meanScore popularity
    season seasonYear
    trailer { id site thumbnail }
    externalLinks { id url site type language }
  }
}
```

**Search anime**:
```graphql
query ($search: String, $type: MediaType) {
  Page(page: 1, perPage: 20) {
    media(search: $search, type: $type) {
      id idMal
      title { english romaji native }
      coverImage { large medium color }
    }
  }
}
```

**Batch artwork by AniList IDs** (batches of 50):
```graphql
query {
  anime0: Media(id: 123, type: ANIME) {
    id idMal coverImage { large medium color } bannerImage
  }
  anime1: Media(id: 456, type: ANIME) { ... }
}
```

**User lists**:
```graphql
query($userName: String, $status: MediaListStatus, $page: Int, $perPage: Int, $sort: [MediaListSort]) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage total }
    mediaList(userName: $userName, type: ANIME, status: $status, sort: $sort) {
      score(format: POINT_100)
      media {
        id idMal
        title { english romaji native }
        coverImage { large medium color }
        duration format description seasonYear
      }
    }
  }
}
```

**Trending**:
```graphql
query($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage total }
    media(type: ANIME, sort: TRENDING_DESC, format_not_in: [MUSIC, NOVEL]) {
      id idMal title { english romaji native }
      coverImage { large medium color }
      bannerImage genres averageScore popularity status season seasonYear
    }
  }
}
```

**Discover** (dynamic query built from params):
- Supports: `sort`, `format_in`, `status`, `season`, `seasonYear`, `countryOfOrigin`, `genre_in/not_in`, `tag_in/not_in`, `averageScore_greater/lesser`, `popularity_greater`, `episodes_greater/lesser`, `duration_greater/lesser`, `isAdult`, `startDate_greater/lesser`

**Submit rating** (mutation):
```graphql
mutation($mediaId: Int, $scoreRaw: Int) {
  SaveMediaListEntry(mediaId: $mediaId, scoreRaw: $scoreRaw) { mediaId }
}
```

### Cache

- Artwork: `cacheWrapGlobal('anilist-artwork:{malId}', ..., 30 days)`
- Batch artwork: `cacheWrapGlobal('anilist-batch:{batchKey}', ..., 30 days)`
- Catalogs: `cacheWrapAniListCatalog(username, listName, page, ..., 1 hour)`

### Image URLs

- Poster: `coverImage.large`
- Background: `bannerImage` (preferred) or `coverImage.large`
- Background processing: passed through local `/api/image/banner-to-background` for resize (1920x1080)

---

## 11. Provider: Kitsu

**Base URL**: `https://kitsu.io/api/edge` (via `kitsu` npm library)

**Auth**: None (public API)

**HTTP**: `kitsu` npm library for most calls, `axios` for batch ID lookups.
- Headers: `Accept: application/vnd.api+json`, `Content-Type: application/vnd.api+json`
- Timeout: 10s

### All Endpoints

| Function | Endpoint |
|----------|----------|
| `searchByName` | `GET /anime?filter[text]={q}&filter[subtype]={type}&page[limit]=20&include=genres` |
| `getMultipleAnimeDetails` | `GET /anime?filter[id]={ids}&include={appends}&page[size]=20` |
| `getAnimeEpisodes` | `GET /anime/{id}/episodes?page[limit]=20` (paginated recursively) |
| `getAnimeDetails` | `GET /anime/{id}?include=episodes,genres,characters,mediaRelationships.destination` |

### Cache

- Episodes: `cacheWrapGlobal('kitsu-episodes:v2:{kitsuId}', ..., 1 hour)`

### Key Response Fields

```
canonicalTitle, titles{en_us,en_jp,en,ja_jp}
synopsis, subtype, status, episodeCount, episodeLength
ageRating, ageRatingGuide, nsfw, slug
youtubeVideoId
posterImage{tiny,small,medium,large,original}
coverImage{tiny,small,large,original}
```

---

## 12. Provider: TVmaze

**Base URL**: `https://api.tvmaze.com`

**Auth**: None

**HTTP**: `undici` Agent (2 max connections, 10s keepAlive). Timeout: 15s. User-Agent: `AIOMetadata/{version}`.

### Rate Limiting

```
MAX_RETRIES = 3
RETRY_DELAY = 1000ms base (exponential for 5xx)
RATE_LIMIT_FALLBACK_DELAY = 10000ms (when no Retry-After header)
```

### All Endpoints

| Function | Endpoint | Cache Key |
|----------|----------|-----------|
| `getShowByImdbId` | `GET /lookup/shows?imdb={id}` | `lookup-shows-imdb:{id}` |
| `getShowByTvdbId` | `GET /lookup/shows?thetvdb={id}` | `lookup-shows-tvdb:{id}` |
| `getShowDetails` | `GET /shows/{id}?embed[]=cast&embed[]=crew` | `shows-details:{id}` |
| `getShowEpisodes` | `GET /shows/{id}/episodes?specials=1` | `shows-episodes:{id}` |
| `getShowById` | `GET /shows/{id}` | `shows-basic:{id}` |
| `searchShows` | `GET /search/shows?q={query}` | `search-shows:{encoded}` |
| `searchPeople` | `GET /search/people?q={query}` | `search-people:{encoded}` |
| `getPersonCastCredits` | `GET /people/{id}/castcredits?embed=show` | `people-castcredits:{id}` |
| `getFullSchedule` | `GET /schedule?date={date}&country={code}` | `schedule-full:{country}:{date}` |

All cached via `cacheWrapTvmazeApi` (12h TTL). 301 redirects handled by extracting show ID from Location header.

---

## 13. Provider: IMDb / Cinemeta

AIOMetadata does NOT use an official IMDb API. Three strategies:

### Strategy A: Cinemeta (primary)

```
GET https://v3-cinemeta.strem.io/meta/{type}/{imdbId}.json
→ Returns Stremio meta object
→ Cached 24h: cacheWrapGlobal('cinemeta-meta:{type}:{imdbId}')

GET https://cinemeta-live.strem.io/meta/{type}/{imdbId}.json
→ Live/real-time variant
→ Cached 24h: cacheWrapGlobal('cinemeta-live-meta:{type}:{imdbId}')
```

### Strategy B: Metahub (static image URLs, no HTTP call)

```
Logo:       https://images.metahub.space/logo/medium/{imdbId}/img
Background: https://images.metahub.space/background/medium/{imdbId}/img
Poster:     https://images.metahub.space/poster/medium/{imdbId}/img
```

### Strategy C: IMDb HTML Scraping (fallback for ID resolution)

```
GET https://www.imdb.com/find?q={encoded_title}&s=all&title_type={feature|tv_series}
→ Parse with cheerio
→ Extract IMDb ID from href using /\/title\/(tt\d+)\//
→ Score matches: exact=1000, normalized=950, prefix=800, contains=700
→ Validate against Cinemeta to prevent false positives
```

Uses random User-Agent rotation (5 agents). Timeout: 10s.

---

## 14. Provider: Fanart.tv

**Base URL**: `https://webservice.fanart.tv/v3/` (via `fanart.tv-api` npm package)

**Auth**: API key from `config.apiKeys?.fanart` || `process.env.FANART_API_KEY`

### All Endpoints

| Function | API Method | ID Type | Property |
|----------|-----------|---------|----------|
| `getBestSeriesBackground` | `getShowImages(tvdbId)` | TVDB ID | `showbackground` |
| `getBestMovieBackground` | `getMovieImages(tmdbId)` | TMDB ID | `moviebackground` |
| `getBestMoviePoster` | `getMovieImages(tmdbId)` | TMDB ID | `movieposter` |
| `getBestSeriesPoster` | `getShowImages(tvdbId)` | TVDB ID | `tvposter` |
| `getBestMovieLogo` | `getMovieImages(tmdbId)` | TMDB ID | `hdmovielogo` |
| `getBestTVLogo` | `getShowImages(tvdbId)` | TVDB ID | `hdtvlogo` |

### Cache

All cached via `cacheWrapGlobal()` with **7-day TTL**:
- `fanart-api:series-background:{tvdbId}`
- `fanart-api:movie-background:{tmdbId}`
- `fanart-api:movie-poster:{tmdbId}`
- `fanart-api:series-poster:{tvdbId}`
- `fanart-api:movie-logo:{tmdbId}`
- `fanart-api:series-logo:{tvdbId}`

### Image Selection: `selectFanartImageByLang(images, config)`

```
1. If englishArtOnly → force targetLang = 'en'
   Else: targetLang = config.language.split('-')[0].toLowerCase() || 'en'
2. Filter by targetLang
3. If empty: filter by 'en'
4. If empty: filter by '00' (language-neutral)
5. If empty: use all images
6. Sort by likes descending
7. Return first
```

---

## 15. Provider: RPDB / TopPoster

### RPDB (Rating Poster DB)

Generates poster images with rating badges overlaid.

```
URL: https://api.ratingposterdb.com/{apiKey}/{idType}/poster-default/{mediaId}.jpg?fallback=true&lang={2letter}
```

ID priority: `tvdbId` → `tmdbId` (with `movie-`/`series-` prefix) → `imdbId`

### TopPoster (Alternative)

```
Poster: https://api.top-streaming.stream/{apiKey}/{idType}/poster-default/{mediaId}.jpg?lang={iso}&fallback_url={encoded}
Thumbnail: https://api.top-streaming.stream/{apiKey}/{idType}/thumbnail/{mediaId}/S{n}E{n}.jpg?blur={bool}
```

Supports IMDB and TMDB only (no TVDB).

---

## 16. Catalog: Trakt

**Base URL**: `https://api.trakt.tv`

**Auth**: OAuth 2.0 Bearer token. Auto-refresh when token expires within 1 hour.

### Rate Limiting

Per-user queues via `QueueManager`:
```
concurrency: env.TRAKT_CONCURRENCY || 5
minTime: env.TRAKT_MIN_TIME_MS || 300ms
maxRequestsPerWindow: env.TRAKT_GET_WINDOW_LIMIT || 1000
rateLimitWindowMs: env.TRAKT_GET_WINDOW_MS || 5 min
```

On 429: reads `Retry-After` header, pauses specific user's queue.

### All Endpoints

| Function | Endpoint |
|----------|----------|
| `fetchTraktWatchlistItems` | `GET /sync/watchlist/{type}/{sort}/{dir}?page={p}&limit={n}&genres={g}` |
| `fetchTraktFavoritesItems` | `GET /sync/favorites/{type}/{sort}/{dir}?page={p}&limit={n}&genres={g}` |
| `fetchTraktRecommendationsItems` | `GET /recommendations/{type}?limit=50` |
| `fetchTraktListItems` | `GET /users/{user}/lists/{slug}/items/{type}?page={p}&limit={n}` |
| `fetchTraktCalendarShows` | `GET /calendars/my/shows/{startDate}/{days}` |
| `fetchTraktTrendingItems` | `GET /{type}/trending?page={p}&limit={n}&genres={g}` |
| `fetchTraktPopularItems` | `GET /{type}/popular?page={p}&limit={n}&genres={g}` |
| `fetchTraktMostFavoritedItems` | `GET /{type}/favorited/{period}?page={p}&limit={n}&genres={g}` |
| `fetchTraktSearchItems` | `GET /search/{type}?query={q}&fields=title,translations,overview&extended=images&limit=30` |
| `fetchTraktPersonCredits` | `GET /people/{id}/{movies\|shows}?extended=full,images` |
| `fetchTraktHistory` | `GET /sync/history/episodes?start_at={date}&limit=100` |
| `fetchTraktWatchedShows` | `GET /sync/watched/shows?extended=noseasons` |
| `fetchTraktShowWatchedProgress` | `GET /shows/{id}/progress/watched` |
| `fetchTraktGenres` | `GET /genres/{type}` (3s timeout, hardcoded fallback) |

### Cache Keys (Redis)

```
trakt-api:watchlist:{tokenHash}:{type}:{page}:{limit}:{sort}:{dir}:{genre}
trakt-api:favorites:{tokenHash}:{type}:{page}:{limit}:{sort}:{dir}:{genre}
trakt-api:trending:{type}:{page}:{limit}:{genre}
trakt-api:popular:{type}:{page}:{limit}:{genre}
trakt_upnext_state:{tokenHash}  (7 day TTL)
```

Default TTL: `CATALOG_TTL` (1 day)

---

## 17. Catalog: SimKL

**Base URL**: `https://api.simkl.com`

**Auth**: OAuth 2.0 Bearer token. Tokens never expire.

### Rate Limiting

```
Global shared (not per-user):
maxRetries: 5
minInterval: 300ms between ALL requests
rateLimitDelay: 5000ms base on 429
backoffMultiplier: 2
maxDelay: 30000ms
```

### All Endpoints

| Function | Endpoint |
|----------|----------|
| `fetchSimklWatchlistItems` | `GET /sync/all-items/{status}?extended=full` |
| `fetchSimklWatchlistItems` (incremental) | `GET /sync/all-items/{status}?extended=full&date_from={date}` |
| `fetchSimklLastActivities` | `POST /sync/activities` |
| `fetchSimklTrendingItems` | `GET https://data.simkl.in/discover/trending/{type}/{interval}_500.json` |
| `fetchSimklGenreItems` | `GET /{movies\|tv\|anime}/genres/{genre}/{type}/{country}/{network}/{year}/{sort}` |
| `fetchSimklCalendar` | `GET https://data.simkl.in/calendar/{type}.json` |

### Watchlist Sync Strategy (3-tier)

```
1. No cache OR items removed → Full sync: /sync/all-items/{status}?extended=full
2. Cache exists + activity changed → Incremental: /sync/all-items/{status}?extended=full&date_from={lastSync}
3. No changes → Return cached data, extend Redis TTL
```

Redis keys:
- `simkl-watchlist-full:{tokenHash}:{status}` (24h TTL)
- `simkl-activities:{tokenHash}` (24h TTL)
- `simkl-api-last-activities:{tokenHash}` (6h TTL)

---

## 18. Catalog: MDBList

**Base URL**: `https://api.mdblist.com`

**Auth**: API key as `?apikey={key}` query param

### Rate Limiting

```
Global IP throttle: 210ms minimum between ALL requests (Cloudflare)
Per-API-key penalty box on 429
maxRetries: 5
backoffMultiplier: 2
```

### All Endpoints

| Function | Endpoint |
|----------|----------|
| `fetchMDBListItems` | `GET /lists/{listId}/items?limit={n}&offset={o}&apikey={k}&append_to_response=genre,poster&unified={bool}&sort={s}&order={o}` |
| `fetchMDBListItems` (watchlist) | `GET /watchlist/items?limit={n}&offset={o}&apikey={k}` |
| `fetchMdbListSearchItems` | `GET /search/{type}?query={q}&limit=30&apikey={k}` |
| `fetchMDBListGenres` | `GET /genres/?apikey={k}&anime={0\|1}` |
| `getMediaRatingFromMDBList` | `GET /{provider}/{type}/{id}?apikey={k}` |
| `fetchMDBListBatchMediaInfo` | `POST /{provider}/{type}?apikey={k}` body: `{ ids: [...] }` (max 200/batch) |
| `fetchMDBListUpNext` | `GET /upnext?apikey={k}&limit={n}&offset={o}` |
| `testMdblistKey` | `GET /user?apikey={k}` |

### Pagination

Reads `x-total-items` and `x-has-more` response headers. Page size: `CATALOG_LIST_ITEMS_SIZE` (default 20).

---

## 19. Catalog: Letterboxd

**No direct Letterboxd API** — uses StremThru as proxy.

### Flow

**Step 1**: Extract identifier from Letterboxd URL
```
HEAD https://letterboxd.com/{username}/
HEAD https://letterboxd.com/{username}/list/{slug}/
→ Extract x-letterboxd-identifier header
```

**Step 2**: Fetch list via StremThru proxy
```
Regular list: GET https://stremthru.13377001.xyz/v0/meta/letterboxd/lists/{identifier}
Watchlist:    GET https://stremthru.13377001.xyz/v0/meta/letterboxd/users/{identifier}/lists/watchlist
→ Response: { data: { title, items: [...] } }
```

**Step 3**: Parse items
- stremioId priority: `imdb` > `tmdb:{id}` > `mal:{id}`
- `item.type === 'show'` → Stremio type `'series'`

### Genre Map (hardcoded)

```
"8G"→Action, "9k"→Adventure, "8m"→Animation, "7I"→Comedy,
"9Y"→Crime, "ai"→Documentary, "7S"→Drama, "8w"→Family,
"82"→Fantasy, "90"→History, "aC"→Horror, "b6"→Music,
"aW"→Mystery, "8c"→Romance, "9a"→Science Fiction, "a8"→Thriller,
"1hO"→TV Movie, "9u"→War, "8Q"→Western
```

---

## 20. ID Mapping System

### Data Sources (loaded at startup, refreshed every 24h)

| Source | URL | Purpose |
|--------|-----|---------|
| Fribb's anime-lists | `https://raw.githubusercontent.com/Fribb/anime-lists/.../anime-list-full.json` | AniDB↔AniList↔MAL↔Kitsu↔TVDB↔TMDB↔IMDb |
| Kitsu→IMDb mapping | `https://raw.githubusercontent.com/TheBeastLT/stremio-kitsu-anime/.../imdb_mapping.json` | Kitsu episode→IMDb episode mapping |
| Trakt anime movies | `https://github.com/rensetsu/db.trakt.extended-anitrakt/releases/latest/movies_ex.json` | MAL↔TMDB↔IMDb for anime movies |
| Wikidata CSV (series) | `https://raw.githubusercontent.com/0xConstant1/Wikidata-Fetcher/.../tv_mappings.csv` | IMDb↔TMDB↔TVDB↔TVmaze for series |
| Wikidata CSV (movies) | `https://raw.githubusercontent.com/0xConstant1/Wikidata-Fetcher/.../movie_mappings.csv` | IMDb↔TMDB↔TVDB for movies |

### ETag-Based Update Protocol

```
1. Check Redis for saved ETag
2. HEAD request to GitHub → compare ETags
3. If match → read from local cache file
4. If mismatch → download → save local file → update Redis ETag
5. On failure → fallback to local cache
```

### In-Memory Index Maps

From `anime-list-full.json` (~15K entries):

| Map | Key | Value |
|-----|-----|-------|
| `animeIdMap` | `mal_id` (int) | Full mapping entry |
| `kitsuIdMap` | `kitsu_id` (int) | Full mapping entry |
| `anidbIdMap` | `anidb_id` (int) | Full mapping entry |
| `anilistIdMap` | `anilist_id` (int) | Full mapping entry |
| `imdbIdMap` | `imdb_id` (string) | Full mapping entry |
| `simklIdMap` | `simkl_id` (int) | Full mapping entry |
| `tvdbIdToAnimeListMap` | `tvdb_id` (int) | **Array** (franchise) |
| `imdbIdToAnimeListMap` | `imdb_id` (string) | **Array** (multi-season) |

From Wikidata CSVs:

| Map | Key | Value |
|-----|-----|-------|
| `seriesImdbToAll` | IMDb ID | `{ imdbId, tmdbId, tvdbId, tvmazeId }` |
| `seriesTvdbToAll` | TVDB ID | Same |
| `seriesTmdbToAll` | TMDB ID | Same |
| `seriesTvmazeToAll` | TVmaze ID | Same |
| `moviesImdbToAll` | IMDb ID | `{ imdbId, tmdbId, tvdbId }` |
| `moviesTvdbToAll` | TVDB ID | Same |
| `moviesTmdbToAll` | TMDB ID | Same |

### Franchise Mapping (Anime)

One TVDB series often maps to multiple MAL/Kitsu entries (e.g., Attack on Titan S1/S2/S3):

```javascript
buildFranchiseMapFromTvdbId(tvdbId):
  1. Get all siblings from tvdbIdToAnimeListMap[tvdbId]
  2. Fetch Kitsu details for all sibling kitsu_ids
  3. TV series sorted by startDate → season 1, 2, 3...
  4. OVAs/ONAs → all mapped to season 0
  5. Returns Map<seasonNumber, kitsuId>
```

### Episode-Level Mapping

`enrichMalEpisodes(videos, kitsuId, preserveIds)`:
```
1. Look up Kitsu→IMDb mapping: { fromSeason, fromEpisode, nonImdbEpisodes }
2. Fetch Cinemeta episodes from: https://cinemeta-live.strem.io/meta/series/{imdbId}.json
3. Re-map MAL episode numbers to IMDb season:episode coordinates
4. Return videos with updated { id, imdb_id, imdbSeason, imdbEpisode }
```

---

## 21. ID Resolution Algorithm

### `resolveAllIds(stremioId, type, config, prefetchedIds, targetProviders)`

**Step 1 — Parse Stremio ID**:
```
"tt1234567" → { imdbId: "tt1234567" }
"tmdb:123"  → { tmdbId: "123" }
"mal:456"   → { malId: "456" }
etc.
```

**Step 2 — Anime fast path**:
If any of `malId`, `kitsuId`, `anidbId`, `anilistId` is set:
```
→ idMapper.getMappingByMalId/ByKitsuId/etc.
→ Merge all IDs from mapping entry
→ Return immediately (no API calls)
```

**Step 3 — Wiki mapping early return**:
```
Check wiki-mapper.js for TMDB/TVDB/IMDb lookups
If found and all targetProviders satisfied → return
```

**Step 4 — Redis/DB cache**:
```
Check id_mappings database table
If all targetProviders satisfied → return
```

**Step 5 — Phase 1 API lookups (parallel)**:
```
If tmdbId → TMDB external_ids → { imdbId, tvdbId }
If tvmazeId → TVmaze externals → { imdbId, tmdbId, tvdbId }
If tvdbId → TVDB remoteIds → { imdbId, tmdbId }
If only imdbId → Cinemeta → { tmdbId, tvdbId }
```

**Step 6 — Phase 2 API lookups (parallel, only if gaps remain)**:
```
No tmdbId + have imdbId → moviedb.find({ imdb_id })
No tvdbId + have imdbId → tvdb.findByImdbId()
No tvdbId + have tmdbId → tvdb.findByTmdbId()
```

**Step 7 — Save to cache**:
```
database.saveIdMapping(type, tmdbId, tvdbId, imdbId, tvmazeId)
```

---

## 22. Anime Detection

### `isAnime(mediaObject, genreList)`

```
1. Build genre name set from mediaObject.genres or mediaObject.genre_ids
2. Check for 'animation' or 'anime' genre
3. If neither → return false

4. If (original_language === 'ja' OR originalCountry in ['jp','jpn'])
   AND (has 'animation' OR 'anime' genre)
   → return true

5. If has explicit 'anime' genre tag → return true (any country)

6. Otherwise → return false (animation but not Japanese = not anime)
```

| Scenario | Result |
|----------|--------|
| No animation/anime genre | `false` |
| Japanese + animation genre | `true` |
| Japanese + anime genre | `true` |
| Non-Japanese + anime genre | `true` |
| Non-Japanese + animation genre only | `false` |

---

## 23. Caching System

### Architecture

```
Request → In-Memory LRU (hot) → Redis (warm) → Provider API (cold)
                                                      ↓
                                              Store in Redis with TTL
```

### Redis Setup

```javascript
import Redis from 'ioredis';
const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: 3,
  enableReadyCheck: true,
  lazyConnect: true
});
```

`NO_CACHE=true` env disables Redis entirely.

### TTL Constants

| Type | TTL | Env Override |
|------|-----|-------------|
| Meta | 7 days | `META_TTL` |
| Catalog | 1 day | `CATALOG_TTL` |
| TMDB Trending | 3 hours | `TMDB_TRENDING_TTL` |
| Search | 12 hours | — |
| Jikan API | 1 day | — |
| TVDB API | 12 hours | — |
| TVmaze API | 12 hours | — |
| AniList Catalog | 1 hour | `ANILIST_CATALOG_TTL` |
| Static/Decade | 30 days | — |
| Genre lists | 30 days | — |

### Error Caching TTLs

| Error Type | TTL |
|------------|-----|
| `EMPTY_RESULT` | 60s (skip) |
| `RATE_LIMITED` | 15 min |
| `TEMPORARY_ERROR` | 2 min |
| `PERMANENT_ERROR` | 30 min |
| `NOT_FOUND` | 1 hour |
| `CACHE_CORRUPTED` | 1 min (self-healing) |

### Cache Key Patterns

```
User-scoped:  v{version}:{key}
Global:       global:{version}:{key}
Version-free: global:{key}  (skipVersion: true — survives upgrades)
```

### Named Cache Wrappers

| Function | Key Pattern | TTL |
|----------|-------------|-----|
| `cacheWrapCatalog` | `catalog:{scope}:{configHash}:{ttl}:{catalogKey}` | Varies |
| `cacheWrapSearch` | `search:{configHash}:{searchKey}` | 12 hours |
| `cacheWrapMeta` | `meta:{configHash}:{metaId}` | 7 days |
| `cacheWrapMetaComponents` | 13 separate sub-keys per meta | 7 days |
| `cacheWrapMetaSmart` | Components first, fallback to full | 7 days |
| `cacheWrapJikanApi` | `global:jikan-api:{key}` | 1 day |
| `cacheWrapTvdbApi` | `global:tvdb-api:{key}` | 12 hours |
| `cacheWrapTvmazeApi` | `global:tvmaze-api:{key}` | 12 hours |
| `cacheWrapAniListCatalog` | `anilist-catalog:{user}:{list}:page{n}` | 1 hour |

### In-Flight Deduplication

```javascript
const inFlightRequests = new Map(); // key → Promise

// Before fetching:
if (inFlightRequests.has(key)) return inFlightRequests.get(key);

// During fetch:
const promise = fetchFn();
inFlightRequests.set(key, promise);

// After fetch:
inFlightRequests.delete(key);
```

### Self-Healing

When Redis GET returns unparseable JSON:
```
1. Delete corrupted entry
2. Write short-TTL error placeholder (1 min)
3. Next request regenerates from provider
```

### Component-Based Meta Cache

Meta objects split into 13 Redis keys for granular invalidation:
```
meta-basic:{hash}:{id}       — Core fields + integrity flags
meta-poster:{hash}:{id}      — Poster URL
meta-raw-poster:{hash}:{id}  — Pre-proxy poster URL
meta-background:{hash}:{id}
meta-landscape-poster:{hash}:{id}
meta-logo:{hash}:{id}
meta-videos:{hash}:{id}      — Episodes array
meta-cast:{hash}:{id}
meta-director:{hash}:{id}
meta-writer:{hash}:{id}
meta-links:{hash}:{id}
meta-trailers:{hash}:{id}
meta-extras:{hash}:{id}      — app_extras object
```

Reconstruction uses `MGET` (single Redis round-trip). Integrity validated via `_hasPoster`, `_hasBackground`, etc. flags in `basic` component.

---

## 24. Database Schema

### Dual Backend: SQLite + PostgreSQL

```
DATABASE_URI=sqlite:///path/to/file.db
DATABASE_URI=postgres://user:pass@host/db
```

SQLite: WAL mode, 256MB mmap, 10000-page cache, 5s busy timeout.

### Tables

**`user_configs`**
```sql
CREATE TABLE user_configs (
  id              SERIAL PRIMARY KEY,
  user_uuid       VARCHAR(255) UNIQUE NOT NULL,
  password_hash   VARCHAR(255) NOT NULL,       -- bcrypt (12 rounds) or legacy SHA-256
  config_data     JSONB/TEXT NOT NULL,          -- Full config JSON
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW()
);
```

**`id_mappings`**
```sql
CREATE TABLE id_mappings (
  id              SERIAL PRIMARY KEY,
  content_type    VARCHAR(50) NOT NULL,        -- 'movie', 'series', 'anime'
  tmdb_id         VARCHAR(255),
  tvdb_id         VARCHAR(255),
  imdb_id         VARCHAR(255),
  tvmaze_id       VARCHAR(255),
  created_at      TIMESTAMP,
  updated_at      TIMESTAMP,
  UNIQUE(content_type, tmdb_id, tvdb_id, imdb_id, tvmaze_id)
);
CREATE INDEX idx_id_mappings_tmdb ON id_mappings(tmdb_id);
CREATE INDEX idx_id_mappings_tvdb ON id_mappings(tvdb_id);
CREATE INDEX idx_id_mappings_imdb ON id_mappings(imdb_id);
CREATE INDEX idx_id_mappings_tvmaze ON id_mappings(tvmaze_id);
```

**`trusted_uuids`**
```sql
CREATE TABLE trusted_uuids (
  user_uuid       VARCHAR(255) UNIQUE NOT NULL,
  trusted_at      TIMESTAMP DEFAULT NOW()
);
```

**`oauth_tokens`**
```sql
CREATE TABLE oauth_tokens (
  id              VARCHAR(255) PRIMARY KEY,
  provider        VARCHAR(50) NOT NULL,        -- 'trakt', 'simkl', 'anilist'
  user_id         VARCHAR(255) NOT NULL,
  access_token    TEXT NOT NULL,
  refresh_token   TEXT NOT NULL,
  expires_at      BIGINT NOT NULL,             -- Unix ms
  scope           TEXT,
  created_at      TIMESTAMP,
  updated_at      TIMESTAMP
);
CREATE INDEX idx_oauth_tokens_provider ON oauth_tokens(provider);
CREATE INDEX idx_oauth_tokens_user_id ON oauth_tokens(user_id);
```

### Password Handling

- New passwords: bcrypt (12 rounds)
- Legacy SHA-256: auto-migrated to bcrypt on next successful login
- `verifyPasswordHash()`: tries bcrypt first, falls back to SHA-256

---

## 25. Image Selection Logic

### Image Priority Chain

**Posters** (by `resolveArtProvider('movie'/'series'/'anime', 'poster', config)`):

For movies:
```
1. RPDB/TopPoster (if API key configured — rating overlay)
2. Fanart.tv movieposter
3. TMDB poster (w500)
4. Metahub poster
```

For series:
```
1. RPDB/TopPoster
2. Fanart.tv tvposter
3. TVDB poster (artwork type 2)
4. TMDB poster
5. Metahub poster
```

For anime:
```
1. AniList coverImage.large
2. Kitsu posterImage.large
3. TVDB poster
4. TMDB poster
5. Fanart.tv
6. MAL images.jpg.large_image_url
```

**Backgrounds**:

For movies:
```
1. Fanart.tv moviebackground
2. TMDB backdrop (original)
3. Metahub background
```

For series:
```
1. Fanart.tv showbackground
2. TVDB background (artwork type 3)
3. TMDB backdrop
4. Metahub background
```

For anime:
```
1. AniList bannerImage (resized to 1920x1080)
2. Kitsu coverImage.large
3. TVDB background
4. TMDB backdrop
5. Fanart.tv
```

**Logos**:
```
1. Fanart.tv hdmovielogo/hdtvlogo (language-aware)
2. TMDB logo from images API
3. Metahub logo
```

### TMDB Image Language Selection

```javascript
selectTmdbImageByLang(images, config):
  1. Filter by user language code
  2. If empty: filter by 'en'
  3. If empty: filter by null (language-neutral)
  4. If empty: use all
  5. Sort by vote_average descending
  6. Return first
```

---

## 26. Search Result Ranking

### TMDB Ranking: `sortSearchResults(results, query)`

**Step 1 — Normalize + classify**:
```javascript
normalize(str):
  NFD decompose → strip diacritics → lowercase
  → & → and → dashes/underscores/slashes → spaces
  → remove non-alphanumeric → strip leading "the "
  → collapse spaces

matchReason = one of: ExactHQ, Exact, Person, StartsWith, Contains, Other

jaroWinklerSimilarity(s1, s2):
  Full Jaro-Winkler algorithm (0-1 score)
  Winkler boost when jaro > 0.7, up to 4-char prefix
```

**Step 2 — Filter**:
- Priority pass: exact+HQ, high votes/popularity
- Hard fail: missing year/poster, obscure+old
- Per-matchReason thresholds
- Safety net: if all filtered, keep top 5 by popularity

**Step 3 — Sort**:
```
Person matches first
→ ExactHQ (by similarity)
→ Composite score: popularity + log10(votes)*5 + recency bonus + similarity*10
→ Year tiebreaker
```

### TVDB Ranking: `sortTvdbSearchResults(results, query)`

- Checks primary title + aliases + translations
- `Contains` match requires similarity >= 0.20
- Sort: has poster → non-upcoming → original API order

---

## 27. Per-User Configuration

Each user gets a UUID. Their config controls everything:

```javascript
{
  // Provider preferences
  providers: {
    movie: 'tmdb',          // or 'tvdb', 'imdb'
    series: 'tvdb',         // or 'tmdb', 'imdb', 'tvmaze'
    anime: 'mal'            // or 'kitsu', 'anilist'
  },

  // Art provider preferences
  artProviders: {
    anime: { poster: 'anilist', background: 'anilist', logo: 'tvdb' },
    movie: { poster: 'tmdb', background: 'fanart', logo: 'fanart' },
    series: { poster: 'tvdb', background: 'fanart', logo: 'fanart' }
  },

  // API keys
  apiKeys: {
    tmdb: '...',
    tvdb: '...',
    fanart: '...',
    rpdb: '...',
    mdblist: '...',
    gemini: '...',
    traktTokenId: '...',
    simklTokenId: '...',
    anilistTokenId: '...'
  },

  // Language & region
  language: 'en-US',

  // Catalog selections
  catalogs: [
    { id: 'tmdb.trending', type: 'movie', enabled: true },
    { id: 'mal.top', type: 'series', enabled: true },
    { id: 'trakt.watchlist', type: 'movie', enabled: true, metadata: { ... } }
  ],

  // Search configuration
  search: {
    enabled: true,
    searchOrder: ['movie', 'series', 'anime_series'],
    engineEnabled: { movie: true, series: true, anime_series: true },
    providers: {
      movie: 'tmdb.search',
      series: 'tmdb.search',
      anime_series: 'mal.search.series',
      anime_movie: 'mal.search.movie'
    }
  },

  // Content filters
  includeAdult: false,
  ageRating: 'none',
  exclusionKeywords: [],
  regexExclusionFilter: '',

  // Display preferences
  posterRatingProvider: 'rpdb',    // or 'top', 'none'
  showMetaProviderAttribution: true,
  displayAgeRating: true,
  hideEpisodeThumbnails: false,
  showRateMeButton: false,
  castCount: 20,

  // Anime preferences
  mal: { useImdbIdForCatalogAndSearch: true, sfw: true }
}
```

---

## 28. Manifest Generation

### `getManifest(config)` — Generated fresh each call

**Steps**:

1. Extract enabled catalogs from config
2. Detect which providers are needed → fetch genre lists in parallel:
   - TMDB genres (movie + TV)
   - MAL genres (anime)
   - Trakt genres
   - MDBList genres
3. For each enabled catalog → dispatch to creator function:
   - `createCatalog()` — Standard TMDB/TVDB/MAL
   - `createTraktCatalog()` — Trakt lists
   - `createSimklCatalog()` — SimKL lists
   - `createMDBListCatalog()` — MDBList lists
   - `createLetterboxdCatalog()` — Letterboxd lists
   - `createStremThruCatalog()` — StremThru catalogs
   - `createAniListCatalog()` — AniList catalogs
   - `createTMDBDiscoverCatalog()` — TMDB discover presets
   - `createTVDBDiscoverCatalog()` — TVDB discover presets
4. Deduplicate by `id:type` key
5. Append search catalogs (ordered by `config.search.searchOrder`)

Each catalog definition includes:
- `id`, `type`, `name`
- `extra`: `[{ name: "genre", options: [...] }, { name: "skip" }]`
- Page size: 25 for MAL, otherwise `CATALOG_LIST_ITEMS_SIZE || 20`

---

## 29. Catalog Routing

### `getCatalog(type, language, page, id, genre, config, userUUID, includeVideos, skip)`

Routes by catalog ID prefix:

| ID Prefix | Handler |
|-----------|---------|
| `tvdb.collections` | `getTvdbCollectionsCatalog()` |
| `tvdb.discover.*` | `getTvdbDiscoverCatalog()` |
| `tvdb.*` | `getTvdbCatalog()` |
| `tmdb.*`, `mdblist.*`, `streaming.*` | `getTmdbAndMdbListCatalog()` |
| `stremthru.*`, `custom.*` | `getStremThruCatalog()` |
| `trakt.*` | `getTraktCatalog()` |
| `mal.discover.*` | `getMalDiscoverCatalog()` |
| `anilist.discover.*` | `getAniListDiscoverCatalog()` |
| `anilist.*` | `getAniListCatalog()` |
| `letterboxd.*` | `getLetterboxdCatalog()` |
| `simkl.*` | `getSimklCatalog()` |

### Cache Key Augmentation (per catalog type)

- `trakt.*`: adds `sort`, `sortDirection`
- `mdblist.*`: adds `sort`, `order`, `filter_score_min/max`
- `tmdb.discover.*`: adds `discoverSig` (MD5 of discover params)
- `trakt.calendar`: adds `date` (today in user's timezone), `days`
- `simkl.*`: adds `pageSize`
- Auth catalogs (`tmdb.watchlist`): TTL=0 (no caching)

### Post-Catalog Filters

```javascript
// Content exclusion
filterMetasByRegex(metas, exclusionKeywords, regexExclusionFilter)

// Age rating filter
applyAgeRatingFilter(metas, type, config)
// Movie: G < PG < PG-13 < R < NC-17
// TV: TV-Y < TV-Y7 < TV-G < TV-PG < TV-14 < TV-MA

// Optional shuffle
if (catalogConfig.randomizePerPage) shuffle(metas)
```

---

## 30. Data Transformation (parseProps)

### Key Utility Functions

**`parseMedia(el, type, genreList, config)`** — TMDB result → Stremio meta

**`parseCast(credits, count, metaProvider)`** — `credits.cast` → `[{ name, character, photo }]`

**`parseDirector(credits)`** — Filter `crew` by `job === "Director"`

**`parseWriter(credits)`** — Writing department + Creator job, deduplicated

**`buildLinks(imdbRating, imdbId, title, type, genres, credits, ...)`** — Array of `{ name, category, url }`:
- IMDb rating link
- Genre links → `stremio:///discover/...`
- Cast/director/writer search links → `stremio:///search?search=...`

**`parseRunTime(runtime)`** — Minutes or string → `"2h 15min"` format

**`parseYear(status, firstAirDate, lastAirDate)`** — `"2020"`, `"2018-2023"`, `"2020-"`

**`parseSlug(type, title, imdbId)`** — `"{type}/{title}-{imdbNumeric}"` for share URLs

**`buildPosterProxyUrl(host, type, proxyId, fallback, language, config)`** — Resolves RPDB/TopPoster URLs

**`resolveArtProvider(contentType, artType, config)`** — Maps config to provider name

**`getAnimeBg/getAnimePoster/getAnimeLogo`** — Provider cascade for anime artwork

**`sortSearchResults(results, query)`** — Full ranking algorithm (see section 26)

**`addMetaProviderAttribution(overview, provider, config)`** — Appends `[Meta provided by {provider}]`

---

## 31. Pseudocode: Full Request Flow

### Meta Request: `GET /stremio/:uuid/meta/series/tt1234567.json`

```
1. Load user config from database by UUID
2. Parse stremioId "tt1234567" → { imdbId: "tt1234567" }

3. Check anime:
   a. Check idMapper.getMappingByImdbId("tt1234567")
   b. Check trakt anime movies mapping
   c. If found → finalType = 'anime'
   d. Otherwise → finalType = 'series'

4. Determine providers needed:
   preferredProvider = config.providers.series || 'tvdb'
   targetProviders = ['tvdb', 'imdb']  // + art provider needs

5. Resolve all IDs:
   a. Check wiki-mapper (in-memory CSV maps)
   b. Check id_mappings DB table
   c. If gaps: TMDB external_ids → { tmdbId, tvdbId }
   d. If gaps: TVDB findByImdbId → { tvdbId, tmdbId }
   e. Save to DB cache

6. Try cacheWrapMetaSmart → check Redis component cache first:
   a. MGET 13 component keys
   b. If all present + integrity valid → reconstruct + return

7. Cache miss → call getMeta:
   a. Try preferred provider (TVDB):
      - tvdb.getSeriesExtended(tvdbId)
      - tvdb.getSeriesEpisodes(tvdbId, language, seasonType)
      - Build series meta + episodes
   b. On failure → try TMDB fallback:
      - moviedb.tvInfo({ tmdbId, append_to_response: "..." })
      - Batch season fetches
      - Build series meta + episodes

8. Enrich with art:
   a. Poster: Fanart.tv tvposter || TVDB type 2 || TMDB poster
   b. Background: Fanart.tv showbackground || TVDB type 3 || TMDB backdrop
   c. Logo: Fanart.tv hdtvlogo || TMDB logo
   d. If RPDB configured: wrap poster URL with rating overlay

9. Get IMDb rating: check in-memory ratings dataset (500K entries)

10. Build final Stremio meta object with:
    - id, type, name, poster, background, logo
    - description, genres, director, cast, writer
    - releaseInfo, runtime, imdbRating
    - trailers, links, behaviorHints
    - videos (episodes array)

11. Store in Redis (13 component keys, 7-day TTL)

12. Return { meta: { ... } }
```

### Catalog Request: `GET /stremio/:uuid/catalog/movie/tmdb.trending.json`

```
1. Load user config
2. Route catalog ID "tmdb.trending" → getTmdbAndMdbListCatalog()

3. Check cache: cacheWrapCatalog with key including configHash + catalogKey

4. Cache miss → fetch:
   a. moviedb.trending('movie', 'day', { page, language })
   b. For each result (paginated):
      - resolveAllIds → get imdbId
      - cacheWrapMetaSmart → get or build full meta
      - Extract { id, type, name, poster, description, imdbRating, releaseInfo }

5. Apply post-filters:
   a. exclusionKeywords / regexExclusionFilter
   b. Age rating filter

6. Store in Redis (TMDB_TRENDING_TTL = 3h)

7. Return { metas: [...] }
```

---

## Appendix A: Environment Variables (Key Ones)

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | 3232 | Server port |
| `HOST_NAME` | — | Public URL |
| `NODE_ENV` | development | Environment |
| `DATABASE_URI` | sqlite://addon/data/db.sqlite | Database |
| `REDIS_URL` | redis://localhost:6379 | Redis |
| `TMDB_API` | — | TMDB API key (required) |
| `TVDB_API_KEY` | — | TVDB API key |
| `FANART_API_KEY` | — | Fanart.tv API key |
| `RPDB_API_KEY` | — | RPDB API key |
| `MDBLIST_API_KEY` | — | MDBList API key |
| `GEMINI_API_KEY` | — | Google Gemini key |
| `TRAKT_CLIENT_ID` | — | Trakt OAuth |
| `TRAKT_CLIENT_SECRET` | — | Trakt OAuth |
| `SIMKL_CLIENT_ID` | — | SimKL OAuth |
| `SIMKL_CLIENT_SECRET` | — | SimKL OAuth |
| `ANILIST_CLIENT_ID` | — | AniList OAuth |
| `ANILIST_CLIENT_SECRET` | — | AniList OAuth |
| `CATALOG_TTL` | 86400 (1 day) | Catalog cache TTL |
| `META_TTL` | 604800 (7 days) | Meta cache TTL |
| `CATALOG_LIST_ITEMS_SIZE` | 20 | Items per catalog page |
| `NO_CACHE` | false | Disable all caching |
| `JIKAN_MAX_CONCURRENT` | 2 | Jikan concurrent requests |
| `JIKAN_MIN_INTERVAL` | 350 | Jikan min ms between requests |
| `TRAKT_CONCURRENCY` | 5 | Trakt concurrent requests |
| `TRAKT_MIN_TIME` | 200 | Trakt min ms between requests |

## Appendix B: External Data Files

| File | Source | Update Interval | Purpose |
|------|--------|----------------|---------|
| `anime-list-full.json` | Fribb/anime-lists (GitHub) | 24h | Cross-provider anime ID mapping (~15K entries) |
| `imdb_mapping.json` | TheBeastLT/stremio-kitsu-anime (GitHub) | 24h | Kitsu episode → IMDb episode mapping |
| `movies_ex.json` | rensetsu/db.trakt.extended-anitrakt (GitHub) | 24h | Trakt anime movie ID mapping |
| `tv_mappings.csv` | 0xConstant1/Wikidata-Fetcher (GitHub) | 24h | Wikidata series ID cross-references |
| `movie_mappings.csv` | 0xConstant1/Wikidata-Fetcher (GitHub) | 24h | Wikidata movie ID cross-references |
| `diferentOrder.json` | Bundled | — | TMDB episode group overrides |
| `diferentImdbId.json` | Bundled | — | IMDb ID substitutions |

## Appendix C: npm Dependencies (Key)

| Package | Purpose |
|---------|---------|
| `express` | HTTP server |
| `ioredis` | Redis client |
| `sqlite3` / `pg` | Database |
| `undici` | HTTP client (TMDB, TVDB, Jikan, TVmaze) |
| `axios` | HTTP client (Kitsu, some fallbacks) |
| `cheerio` | IMDb HTML scraping |
| `sharp` | Image processing (blur, resize) |
| `bcrypt` | Password hashing |
| `lru-cache` | In-memory cache |
| `bottleneck` | Rate limiting (AniList) |
| `lz-string` | Config compression |
| `name-to-imdb` | Title → IMDb ID resolution |
| `fanart.tv-api` | Fanart.tv client |
| `kitsu` | Kitsu API client |
| `csv-parse` | Wikidata CSV parsing |
