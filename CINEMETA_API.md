# Cinemeta API Documentation

Stremio's official metadata API. Free, no auth required. Covers movies and TV shows by IMDB ID.

**Base URL:** `https://v3-cinemeta.strem.io`
**Catalog Base:** `https://cinemeta-catalogs.strem.io/top` (redirected from main base)

---

## Table of Contents

1. [Manifest](#manifest)
2. [Catalogs](#catalogs)
3. [Meta (Single Item)](#meta)
4. [Images](#images)
5. [Response Schemas](#response-schemas)

---

## Manifest

Returns all available catalogs, genres, and supported filters.

```bash
curl "https://v3-cinemeta.strem.io/manifest.json"
```

---

## Catalogs

### URL Pattern

```
GET /catalog/{type}/{catalogId}.json
GET /catalog/{type}/{catalogId}/{extra}.json
```

**Note:** The main base URL redirects catalogs to `https://cinemeta-catalogs.strem.io/top/catalog/...`
You can use either — curl with `-L` to follow redirects, or use the catalogs URL directly.

### Parameters

| Parameter | Values | Description |
|-----------|--------|-------------|
| `type` | `movie`, `series` | Content type |
| `catalogId` | `top`, `year`, `imdbRating` | Catalog to query (see below) |
| `extra` | `genre=X`, `search=X`, `skip=N` | Filters (dot-separated for multiple) |

### Available Catalogs

| ID | Name | Description | Requires |
|----|------|-------------|----------|
| `top` | Popular | Trending/popular content | Nothing |
| `year` | New | Content by release year | `genre` (a year like `2025`) |
| `imdbRating` | Featured | Highest rated content | Nothing |

### Extra Filters

Append as path segment. Combine multiple with `&` inside the path segment.

| Filter | Format | Example |
|--------|--------|---------|
| Genre | `genre={Genre}` | `genre=Action` |
| Year (for `year` catalog) | `genre={Year}` | `genre=2025` |
| Search | `search={query}` | `search=breaking%20bad` |
| Pagination | `skip={N}` | `skip=100` (pages of ~50) |

### Catalog Endpoints

```bash
# Popular movies (trending)
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top.json"

# Popular TV shows
curl -L "https://v3-cinemeta.strem.io/catalog/series/top.json"

# Search movies
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/search=shawshank.json"

# Search TV shows
curl -L "https://v3-cinemeta.strem.io/catalog/series/top/search=breaking%20bad.json"

# Genre filter
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/genre=Action.json"
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/genre=Horror.json"
curl -L "https://v3-cinemeta.strem.io/catalog/series/top/genre=Comedy.json"

# Movies by year
curl -L "https://v3-cinemeta.strem.io/catalog/movie/year/genre=2025.json"
curl -L "https://v3-cinemeta.strem.io/catalog/series/year/genre=2024.json"

# Featured (highest rated)
curl -L "https://v3-cinemeta.strem.io/catalog/movie/imdbRating.json"
curl -L "https://v3-cinemeta.strem.io/catalog/series/imdbRating.json"

# Featured + genre
curl -L "https://v3-cinemeta.strem.io/catalog/movie/imdbRating/genre=Sci-Fi.json"

# Pagination (skip first 100, get next ~50)
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/skip=100.json"
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/skip=50.json"

# Combined: genre + pagination
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/genre=Action&skip=50.json"
```

### Available Genres

**Movies:**
`Action`, `Adventure`, `Animation`, `Biography`, `Comedy`, `Crime`, `Documentary`, `Drama`, `Family`, `Fantasy`, `History`, `Horror`, `Mystery`, `Romance`, `Sci-Fi`, `Sport`, `Thriller`, `War`, `Western`

**Series (additional):**
`Reality-TV`, `Talk-Show`, `Game-Show`

### Catalog Response

Returns ~40-50 items per page.

```json
{
  "metas": [
    {
      "id": "tt27543632",
      "imdb_id": "tt27543632",
      "type": "movie",
      "name": "The Housemaid",
      "poster": "https://images.metahub.space/poster/small/tt27543632/img",
      "background": "https://images.metahub.space/background/medium/tt27543632/img",
      "logo": "https://images.metahub.space/logo/medium/tt27543632/img",
      "description": "A struggling young woman is relieved by...",
      "year": "2025",
      "imdbRating": "7.0",
      "genre": ["Drama", "Thriller"],
      "genres": ["Drama", "Thriller"],
      "releaseInfo": "2025",
      "runtime": "131 min",
      "cast": ["Sydney Sweeney", "Amanda Seyfried", "Brandon Sklenar"],
      "director": ["Paul Feig"],
      "writer": ["Rebecca Sonnenshine", "Freida McFadden"],
      "country": "United States",
      "released": "2025-12-19T00:00:00.000Z",
      "awards": "1 win & 8 nominations total",
      "popularity": 5.51382,
      "popularities": {
        "moviedb": 165.4146,
        "stremio": 5.51382,
        "stremio_lib": 0,
        "trakt": 1119
      },
      "moviedb_id": 1368166,
      "slug": "movie/the-housemaid-27543632",
      "trailers": [
        {"source": "BqWH0KDqm3U", "type": "Trailer"}
      ],
      "trailerStreams": [
        {"title": "The Housemaid", "ytId": "BqWH0KDqm3U"}
      ],
      "links": [
        {"name": "7.0", "category": "imdb", "url": "https://imdb.com/title/tt27543632"},
        {"name": "Drama", "category": "Genres", "url": "stremio:///discover/..."},
        {"name": "Sydney Sweeney", "category": "Cast", "url": "stremio:///search?search=..."}
      ],
      "behaviorHints": {
        "defaultVideoId": "tt27543632",
        "hasScheduledVideos": false
      }
    }
  ]
}
```

---

## Meta

Get full details for a single movie or TV show.

### URL Pattern

```
GET /meta/{type}/{imdbId}.json
```

### Endpoints

```bash
# Movie
curl "https://v3-cinemeta.strem.io/meta/movie/tt0111161.json"

# TV Show (includes all episodes)
curl "https://v3-cinemeta.strem.io/meta/series/tt0944947.json"
```

### Movie Meta Response

```json
{
  "meta": {
    "id": "tt0111161",
    "imdb_id": "tt0111161",
    "type": "movie",
    "name": "The Shawshank Redemption",
    "description": "A banker convicted of uxoricide forms a friendship...",
    "year": "1994",
    "releaseInfo": "1994",
    "released": "1994-10-14T00:00:00.000Z",
    "runtime": "142 min",
    "genre": ["Drama"],
    "genres": ["Drama"],
    "cast": ["Tim Robbins", "Morgan Freeman", "Bob Gunton"],
    "director": ["Frank Darabont"],
    "writer": ["Stephen King", "Frank Darabont"],
    "country": "United States",
    "awards": "Nominated for 7 Oscars. 21 wins & 42 nominations total",
    "imdbRating": "9.3",
    "poster": "https://images.metahub.space/poster/small/tt0111161/img",
    "background": "https://images.metahub.space/background/medium/tt0111161/img",
    "logo": "https://images.metahub.space/logo/medium/tt0111161/img",
    "popularity": 1.18,
    "popularities": {
      "moviedb": 35.39,
      "stremio": 1.18,
      "trakt": 57,
      "stremio_lib": 0
    },
    "moviedb_id": 278,
    "slug": "movie/the-shawshank-redemption-0111161",
    "dvdRelease": "2008-08-15T00:00:00.000Z",
    "trailers": [
      {"source": "PLl99DlL6b4", "type": "Trailer"}
    ],
    "trailerStreams": [
      {"title": "The Shawshank Redemption", "ytId": "PLl99DlL6b4"}
    ],
    "links": [
      {"name": "9.3", "category": "imdb", "url": "https://imdb.com/title/tt0111161"},
      {"name": "The Shawshank Redemption", "category": "share", "url": "https://www.strem.io/s/movie/..."},
      {"name": "Drama", "category": "Genres", "url": "stremio:///discover/..."},
      {"name": "Tim Robbins", "category": "Cast", "url": "stremio:///search?search=Tim%20Robbins"},
      {"name": "Frank Darabont", "category": "Directors", "url": "stremio:///search?search=..."}
    ],
    "videos": [],
    "behaviorHints": {
      "defaultVideoId": "tt0111161",
      "hasScheduledVideos": false
    }
  }
}
```

### Series Meta Response

Same as movie, plus `videos` array with all episodes and `status` field:

```json
{
  "meta": {
    "id": "tt0944947",
    "type": "series",
    "name": "Game of Thrones",
    "year": "2011–2019",
    "status": "Ended",
    "tvdb_id": 121361,
    "...same fields as movie...",
    "videos": [
      {
        "id": "tt0944947:1:1",
        "name": "Winter Is Coming",
        "season": 1,
        "number": 1,
        "episode": 1,
        "firstAired": "2011-04-18T05:00:00.000Z",
        "released": "2011-04-18T05:00:00.000Z",
        "overview": "Eddard Stark is torn between his family and...",
        "description": "Eddard Stark is torn between his family and...",
        "thumbnail": "https://episodes.metahub.space/tt0944947/1/1/w780.jpg",
        "tvdb_id": 3254641,
        "rating": "0"
      },
      {
        "id": "tt0944947:8:6",
        "name": "The Iron Throne",
        "season": 8,
        "number": 6,
        "episode": 6,
        "firstAired": "2019-05-20T05:00:00.000Z",
        "released": "2019-05-20T05:00:00.000Z",
        "overview": "The fate of the Seven Kingdoms is at stake...",
        "description": "The fate of the Seven Kingdoms is at stake...",
        "thumbnail": "https://episodes.metahub.space/tt0944947/8/6/w780.jpg",
        "tvdb_id": 7121405,
        "rating": "0"
      }
    ],
    "behaviorHints": {
      "defaultVideoId": null,
      "hasScheduledVideos": true
    }
  }
}
```

### Meta Field Reference

| Field | Type | Movies | Series | Description |
|-------|------|--------|--------|-------------|
| `id` | string | Yes | Yes | IMDB ID (e.g., `tt0111161`) |
| `imdb_id` | string | Yes | Yes | Same as id |
| `type` | string | Yes | Yes | `movie` or `series` |
| `name` | string | Yes | Yes | Title |
| `description` | string | Yes | Yes | Plot summary |
| `year` | string | Yes | Yes | Release year (`"2025"` or `"2011–2019"`) |
| `releaseInfo` | string | Yes | Yes | Same as year |
| `released` | string | Yes | Yes | ISO 8601 date |
| `runtime` | string | Yes | Yes | e.g., `"142 min"` |
| `genre` | string[] | Yes | Yes | Genre list |
| `genres` | string[] | Yes | Yes | Duplicate of genre |
| `cast` | string[] | Yes | Yes | Actor names |
| `director` | string[] | Yes | Yes | Director names |
| `writer` | string[] | Yes | Yes | Writer names |
| `country` | string | Yes | Yes | Production country |
| `awards` | string | Yes | Yes | Award text |
| `imdbRating` | string | Yes | Yes | Rating as string (e.g., `"9.3"`) |
| `poster` | string | Yes | Yes | Poster image URL |
| `background` | string | Yes | Yes | Background/wallpaper URL |
| `logo` | string | Yes | Yes | Logo (transparent PNG) URL |
| `popularity` | float | Yes | Yes | Stremio popularity score |
| `popularities` | object | Yes | Yes | Scores from multiple platforms |
| `moviedb_id` | int | Yes | Yes | TMDB ID |
| `slug` | string | Yes | Yes | URL slug |
| `dvdRelease` | string | Yes | No | DVD release date |
| `status` | string | No | Yes | `"Ended"`, `"Returning Series"`, etc. |
| `tvdb_id` | int | No | Yes | TVDB ID |
| `videos` | array | Empty | Yes | All episodes (see below) |
| `trailers` | array | Yes | Yes | YouTube trailer IDs |
| `trailerStreams` | array | Yes | Yes | YouTube trailer with title |
| `links` | array | Yes | Yes | IMDB, genres, cast search links |
| `behaviorHints` | object | Yes | Yes | UI hints |

### Video (Episode) Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stremio ID (`tt0944947:1:1`) |
| `name` | string | Episode title |
| `season` | int | Season number (0 = specials) |
| `number` | int | Episode number within season |
| `episode` | int | Same as number |
| `firstAired` | string | Air date (ISO 8601) |
| `released` | string | Same as firstAired |
| `overview` | string | Episode description |
| `description` | string | Same as overview |
| `thumbnail` | string | Episode still image URL |
| `tvdb_id` | int | TVDB episode ID |
| `rating` | string | Rating |

---

## Images

No authentication required. Direct image URLs by IMDB ID.

### Poster

```
https://images.metahub.space/poster/{size}/{imdbId}/img
```

| Size | Dimensions | File Size (example) |
|------|-----------|-------------------|
| `small` | ~185px wide | ~30 KB |
| `medium` | ~370px wide | ~69 KB |
| `large` | ~740px wide | ~783 KB |

```bash
curl -L "https://images.metahub.space/poster/small/tt0111161/img" -o poster_sm.jpg
curl -L "https://images.metahub.space/poster/medium/tt0111161/img" -o poster_md.jpg
curl -L "https://images.metahub.space/poster/large/tt0111161/img" -o poster_lg.jpg
```

### Background / Wallpaper

```
https://images.metahub.space/background/{size}/{imdbId}/img
```

| Size | Dimensions | File Size (example) |
|------|-----------|-------------------|
| `small` | ~300px wide | ~26 KB |
| `medium` | ~600px wide | ~139 KB |
| `large` | ~1280px wide | ~783 KB |

```bash
curl -L "https://images.metahub.space/background/small/tt0111161/img" -o bg_sm.jpg
curl -L "https://images.metahub.space/background/medium/tt0111161/img" -o bg_md.jpg
curl -L "https://images.metahub.space/background/large/tt0111161/img" -o bg_lg.jpg
```

### Logo (Transparent PNG)

```
https://images.metahub.space/logo/{size}/{imdbId}/img
```

All sizes return the same image (~66 KB PNG).

```bash
curl -L "https://images.metahub.space/logo/medium/tt0111161/img" -o logo.png
```

### Episode Thumbnails

```
https://episodes.metahub.space/{imdbId}/{season}/{episode}/w780.jpg
https://episodes.metahub.space/{imdbId}/{season}/{episode}/w300.jpg
```

| Size | Dimensions |
|------|-----------|
| `w300` | 300px wide (~11 KB) |
| `w780` | 780px wide (~60 KB) |

```bash
# Game of Thrones S01E01 thumbnail
curl -L "https://episodes.metahub.space/tt0944947/1/1/w780.jpg" -o ep_thumb.jpg

# Smaller version
curl -L "https://episodes.metahub.space/tt0944947/1/1/w300.jpg" -o ep_thumb_sm.jpg
```

### YouTube Trailers

Trailer IDs from the `trailers` or `trailerStreams` fields:

```
https://www.youtube.com/watch?v={ytId}
https://img.youtube.com/vi/{ytId}/maxresdefault.jpg   (thumbnail)
https://img.youtube.com/vi/{ytId}/hqdefault.jpg       (thumbnail)
```

---

## Response Schemas

### Catalog Item (in `metas[]`)

Same fields as Meta response, all fields included.

### Links Object

```json
{
  "name": "9.3",
  "category": "imdb",
  "url": "https://imdb.com/title/tt0111161"
}
```

Categories: `imdb`, `share`, `Genres`, `Cast`, `Writers`, `Directors`

### Popularity Object

```json
{
  "moviedb": 35.39,    // TMDB popularity
  "stremio": 1.18,     // Stremio internal
  "stremio_lib": 0,    // Stremio library
  "trakt": 57          // Trakt.tv
}
```

### Behavior Hints

```json
{
  "defaultVideoId": "tt0111161",     // For movies: IMDB ID. For series: null
  "hasScheduledVideos": false         // true if series has upcoming episodes
}
```

---

## Quick Reference

```bash
# Trending movies
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top.json"

# Trending series
curl -L "https://v3-cinemeta.strem.io/catalog/series/top.json"

# Search
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/search=inception.json"
curl -L "https://v3-cinemeta.strem.io/catalog/series/top/search=breaking%20bad.json"

# By genre
curl -L "https://v3-cinemeta.strem.io/catalog/movie/top/genre=Horror.json"

# By year
curl -L "https://v3-cinemeta.strem.io/catalog/movie/year/genre=2025.json"

# Featured (top rated)
curl -L "https://v3-cinemeta.strem.io/catalog/movie/imdbRating.json"

# Movie details
curl "https://v3-cinemeta.strem.io/meta/movie/tt0111161.json"

# TV show details + all episodes
curl "https://v3-cinemeta.strem.io/meta/series/tt0944947.json"

# Images (no auth)
curl -L "https://images.metahub.space/poster/large/{IMDB_ID}/img"
curl -L "https://images.metahub.space/background/large/{IMDB_ID}/img"
curl -L "https://images.metahub.space/logo/medium/{IMDB_ID}/img"
curl -L "https://episodes.metahub.space/{IMDB_ID}/{season}/{ep}/w780.jpg"
```

## Notes

- All endpoints are **free and require no authentication**
- Catalog endpoints redirect from main base to `cinemeta-catalogs.strem.io` — use `-L` with curl
- Meta endpoints respond directly from main base
- Pagination is ~40-50 items per page, use `skip=N` to paginate
- Image URLs are deterministic — construct them directly from IMDB ID without calling the API
- Trailer `source`/`ytId` values are YouTube video IDs
- `genre` and `genres` are duplicate fields (both present)
- `description` and `overview` are duplicate fields on episodes
- `number` and `episode` are duplicate fields on episodes
- Years range from 1920 to 2026 for movies, 1960 to 2026 for series
