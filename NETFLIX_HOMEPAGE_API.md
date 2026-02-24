# Netflix-Style Homepage — API Implementation Guide

> Every endpoint you need to build a Netflix-like homepage with hero banners, category rows, anime sections, and personalized lists. Copy-paste ready.

---

## Table of Contents

1. [Overview](#1-overview)
2. [API Keys Required](#2-api-keys-required)
3. [Hero Banner Section](#3-hero-banner-section)
4. [Top 10 Rows](#4-top-10-rows)
5. [Standard Category Rows](#5-standard-category-rows)
6. [Genre Rows](#6-genre-rows)
7. [Curated / Smart Rows](#7-curated--smart-rows)
8. [Anime Rows](#8-anime-rows)
9. [Personalized Rows (Trakt)](#9-personalized-rows-trakt)
10. [Image URL Reference](#10-image-url-reference)
11. [Genre ID Reference](#11-genre-id-reference)
12. [Rate Limits](#12-rate-limits)
13. [Caching Strategy](#13-caching-strategy)
14. [Response Parsing](#14-response-parsing)
15. [Full Homepage Blueprint](#15-full-homepage-blueprint)
16. [Pseudocode: Build the Homepage](#16-pseudocode-build-the-homepage)

---

## 1. Overview

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│   HERO BANNER  (auto-rotating, 3-5 featured titles)     │
│   [full-width backdrop + logo overlay + description]     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│   Top 10 Movies     ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →            │
│   Top 10 TV Shows   ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →            │
│   Popular Movies    ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →     │
│   New Releases      ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →     │
│   Comedy Movies     ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →     │
│   Bingeworthy       ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →     │
│   Trending Anime    ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →     │
│   Action Movies     ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■  →     │
│   ...more rows...                                        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**Data sources**: 3 APIs cover everything:
- **TMDB** — Movies, TV shows, genres, images (primary source for 80% of content)
- **Jikan (MAL)** — Anime rankings, seasonal, schedules
- **AniList** — Anime trending, user lists

Optional:
- **Trakt** — Personalized watchlists, watch history, community favorites
- **Fanart.tv** — Higher quality logos and artwork

---

## 2. API Keys Required

| Provider | Cost | Get It At | Required? |
|----------|------|-----------|-----------|
| TMDB | Free | https://www.themoviedb.org/settings/api | Yes |
| Jikan/MAL | Free | No key needed (public API) | For anime |
| AniList | Free | No key needed for reads | For anime |
| Trakt | Free | https://trakt.tv/oauth/applications | For personalized |
| Fanart.tv | Free | https://fanart.tv/get-an-api-key/ | For better art |

**TMDB is the only required key.** You can build a complete homepage with just TMDB + Jikan (no keys needed for Jikan).

---

## 3. Hero Banner Section

The hero is the big cinematic banner at the top. You need: a backdrop image, a title logo, a description, and the content ID.

### Step 1: Get featured titles

```
GET https://api.themoviedb.org/3/trending/all/day?api_key={KEY}&language=en-US
```

**Response** (take top 5):
```json
{
  "results": [
    {
      "id": 123456,
      "media_type": "movie",
      "title": "Movie Name",
      "name": "TV Show Name",
      "overview": "A brief description...",
      "backdrop_path": "/abc123.jpg",
      "poster_path": "/def456.jpg",
      "genre_ids": [28, 878],
      "vote_average": 8.2,
      "release_date": "2026-01-15",
      "first_air_date": "2026-01-15"
    }
  ]
}
```

**Which field is the title?**
- `media_type === "movie"` → use `title`
- `media_type === "tv"` → use `name`

### Step 2: Get the title logo for each hero item

```
GET https://api.themoviedb.org/3/{media_type}/{id}/images?api_key={KEY}&include_image_language=en,null
```

**Response** (grab first logo):
```json
{
  "logos": [
    {
      "file_path": "/logo123.png",
      "iso_639_1": "en",
      "vote_average": 5.2,
      "width": 500,
      "height": 187
    }
  ]
}
```

### Step 3: Build the hero

```
Backdrop:  https://image.tmdb.org/t/p/original{backdrop_path}
Logo:      https://image.tmdb.org/t/p/w500{logos[0].file_path}
```

**Logo selection priority**: Pick the logo where `iso_639_1` matches user language → `"en"` → `null` → first available. Within same language, pick highest `vote_average`.

### Optional: Get content rating for the hero badge

For movies:
```
GET https://api.themoviedb.org/3/movie/{id}/release_dates?api_key={KEY}
```
Parse: `results.find(r => r.iso_3166_1 === "US").release_dates.find(d => d.certification).certification`

For TV:
```
GET https://api.themoviedb.org/3/tv/{id}/content_ratings?api_key={KEY}
```
Parse: `results.find(r => r.iso_3166_1 === "US").rating`

### Optional: Get runtime for the hero info line

For movies — already in the trending response as part of full details:
```
GET https://api.themoviedb.org/3/movie/{id}?api_key={KEY}&language=en-US
```
→ `runtime` field (minutes)

For TV:
```
GET https://api.themoviedb.org/3/tv/{id}?api_key={KEY}&language=en-US
```
→ `episode_run_time[0]` or `last_episode_to_air.runtime`

### Hero Data Shape (what you render)

```json
{
  "id": 123456,
  "mediaType": "movie",
  "title": "Movie Name",
  "description": "A brief description...",
  "backdropUrl": "https://image.tmdb.org/t/p/original/abc123.jpg",
  "logoUrl": "https://image.tmdb.org/t/p/w500/logo123.png",
  "rating": "PG-13",
  "year": "2026",
  "runtime": "2h 15m",
  "genres": ["Action", "Sci-Fi"],
  "voteAverage": 8.2
}
```

---

## 4. Top 10 Rows

Netflix-style numbered rows. Use weekly trending (more stable than daily).

### Top 10 Movies

```
GET https://api.themoviedb.org/3/trending/movie/week?api_key={KEY}&language=en-US
```
Take `results.slice(0, 10)`. The rank IS the array index + 1.

### Top 10 TV Shows

```
GET https://api.themoviedb.org/3/trending/tv/week?api_key={KEY}&language=en-US
```
Take `results.slice(0, 10)`.

### Top 10 Anime

```
GET https://api.jikan.moe/v4/top/anime?type=tv&limit=10&sfw=true
```

**Response**:
```json
{
  "data": [
    {
      "mal_id": 5114,
      "title": "Fullmetal Alchemist: Brotherhood",
      "title_english": "Fullmetal Alchemist: Brotherhood",
      "score": 9.09,
      "scored_by": 2100000,
      "rank": 1,
      "images": {
        "jpg": {
          "image_url": "https://cdn.myanimelist.net/images/anime/...",
          "large_image_url": "https://cdn.myanimelist.net/images/anime/..."
        }
      },
      "synopsis": "...",
      "episodes": 64,
      "status": "Finished Airing",
      "genres": [{ "mal_id": 1, "name": "Action" }]
    }
  ]
}
```

Use `large_image_url` for poster, `title_english || title` for display name.

---

## 5. Standard Category Rows

Each of these is **one API call** that returns 20 items.

### Popular Movies
```
GET https://api.themoviedb.org/3/movie/popular?api_key={KEY}&language=en-US&page=1
```

### Popular TV Shows
```
GET https://api.themoviedb.org/3/tv/popular?api_key={KEY}&language=en-US&page=1
```

### Now Playing (In Theaters)
```
GET https://api.themoviedb.org/3/movie/now_playing?api_key={KEY}&language=en-US&page=1
```

### Upcoming Movies
```
GET https://api.themoviedb.org/3/movie/upcoming?api_key={KEY}&language=en-US&page=1
```

### Airing Today (TV)
```
GET https://api.themoviedb.org/3/tv/airing_today?api_key={KEY}&language=en-US&page=1
```

### On The Air (TV airing this week)
```
GET https://api.themoviedb.org/3/tv/on_the_air?api_key={KEY}&language=en-US&page=1
```

### Top Rated Movies (All Time)
```
GET https://api.themoviedb.org/3/movie/top_rated?api_key={KEY}&language=en-US&page=1
```

### Top Rated TV Shows (All Time)
```
GET https://api.themoviedb.org/3/tv/top_rated?api_key={KEY}&language=en-US&page=1
```

### New Releases This Year
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&language=en-US&sort_by=popularity.desc&primary_release_year=2026&page=1
```

### New TV Shows This Year
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&language=en-US&sort_by=popularity.desc&first_air_date_year=2026&page=1
```

**All TMDB list responses share the same shape**:
```json
{
  "page": 1,
  "total_pages": 500,
  "total_results": 10000,
  "results": [
    {
      "id": 12345,
      "title": "Movie Title",
      "name": "TV Show Name",
      "poster_path": "/abc.jpg",
      "backdrop_path": "/xyz.jpg",
      "overview": "Description...",
      "vote_average": 7.8,
      "vote_count": 1234,
      "genre_ids": [28, 12],
      "release_date": "2026-01-15",
      "first_air_date": "2026-01-15",
      "original_language": "en",
      "popularity": 456.789
    }
  ]
}
```

For the row card, you need: `id`, `title`/`name`, `poster_path`, `vote_average`.

---

## 6. Genre Rows

Use **TMDB Discover** — the most powerful endpoint. One call per genre row.

### Template

```
GET https://api.themoviedb.org/3/discover/{movie|tv}?api_key={KEY}&language=en-US&sort_by=popularity.desc&with_genres={GENRE_ID}&page=1
```

### Ready-to-use genre rows

**Comedy Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=35&page=1
```

**Action Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=28&page=1
```

**Horror Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=27&page=1
```

**Sci-Fi Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=878&page=1
```

**Romance Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=10749&page=1
```

**Thriller Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=53&page=1
```

**Documentary Movies**:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=99&page=1
```

**Crime TV Shows**:
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=popularity.desc&with_genres=80&page=1
```

**Drama TV Shows**:
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=popularity.desc&with_genres=18&page=1
```

**Sci-Fi & Fantasy TV**:
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=popularity.desc&with_genres=10765&page=1
```

### Multi-Genre Combos

**Action Comedy** (comma = AND):
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=28,35&page=1
```

**Sci-Fi OR Fantasy** (pipe = OR):
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=878|14&page=1
```

### Exclude Genres

**Animation but NOT family** (exclude kids stuff):
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=16&without_genres=10751&page=1
```

---

## 7. Curated / Smart Rows

These use discover with specific filters to create Netflix-style "mood" categories.

### Bingeworthy TV Shows (highly rated, lots of votes)
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=vote_average.desc&vote_count.gte=500&vote_average.gte=8&page=1
```

### Hidden Gems (high rated, low popularity)
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=vote_average.desc&vote_count.gte=100&vote_count.lte=1000&vote_average.gte=7.5&page=1
```

### Award-Winning Dramas (dramas with high votes)
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=vote_average.desc&with_genres=18&vote_count.gte=2000&vote_average.gte=8&page=1
```

### 90s Classics
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&primary_release_date.gte=1990-01-01&primary_release_date.lte=1999-12-31&vote_count.gte=500&page=1
```

### 2000s Classics
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&primary_release_date.gte=2000-01-01&primary_release_date.lte=2009-12-31&vote_count.gte=500&page=1
```

### Family Movie Night
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=10751&certification_country=US&certification.lte=PG&page=1
```

### Date Night Movies (romance + comedy, R or less)
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_genres=10749,35&certification_country=US&certification.lte=R&page=1
```

### Critically Acclaimed This Year
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=vote_average.desc&primary_release_year=2026&vote_count.gte=200&vote_average.gte=7&page=1
```

### Long-Running TV Shows (5+ seasons)
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=popularity.desc&vote_count.gte=200&with_status=0&page=1
```
Note: `with_status=0` = Returning Series. Filter client-side by `number_of_seasons >= 5` after fetching details.

### Miniseries
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=popularity.desc&with_type=2&vote_count.gte=100&page=1
```
`with_type=2` = Miniseries.

### Based on True Stories
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_keywords=818|9672&page=1
```
Keywords: `818` = "based on true story", `9672` = "based on true events".

### Superhero Movies
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_keywords=9715|180547&page=1
```
Keywords: `9715` = "superhero", `180547` = "superhero movie".

### Korean Dramas
```
GET https://api.themoviedb.org/3/discover/tv?api_key={KEY}&sort_by=popularity.desc&with_original_language=ko&with_genres=18&page=1
```

### Bollywood
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_original_language=hi&page=1
```

### Spanish Language Films
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&with_original_language=es&vote_count.gte=200&page=1
```

### Streaming Provider Specific (e.g., "Available on Netflix")

First get provider ID:
```
GET https://api.themoviedb.org/3/watch/providers/movie?api_key={KEY}&language=en-US&watch_region=US
```
Netflix = provider ID `8`.

Then filter:
```
GET https://api.themoviedb.org/3/discover/movie?api_key={KEY}&sort_by=popularity.desc&watch_region=US&with_watch_providers=8&page=1
```

Common provider IDs (US):
| ID | Provider |
|----|----------|
| 8 | Netflix |
| 337 | Disney+ |
| 9 | Amazon Prime |
| 350 | Apple TV+ |
| 15 | Hulu |
| 531 | Paramount+ |
| 1899 | Max |
| 283 | Crunchyroll |

---

## 8. Anime Rows

### Top Anime (All Time)
```
GET https://api.jikan.moe/v4/top/anime?type=tv&limit=25&sfw=true
```

### Top Anime Movies
```
GET https://api.jikan.moe/v4/top/anime?type=movie&limit=25&sfw=true
```

### Anime Airing Right Now
```
GET https://api.jikan.moe/v4/seasons/now?limit=25&sfw=true
```

### Upcoming Anime (Next Season)
```
GET https://api.jikan.moe/v4/seasons/upcoming?limit=25&sfw=true
```

### This Season (e.g., Winter 2026)
```
GET https://api.jikan.moe/v4/seasons/2026/winter?limit=25&sfw=true
```

Seasons: `winter` (Jan-Mar), `spring` (Apr-Jun), `summer` (Jul-Sep), `fall` (Oct-Dec)

### Most Popular Anime (by member count)
```
GET https://api.jikan.moe/v4/top/anime?filter=bypopularity&limit=25&sfw=true
```

### Most Favorited Anime
```
GET https://api.jikan.moe/v4/top/anime?filter=favorite&limit=25&sfw=true
```

### Anime by Genre

**Action Anime**:
```
GET https://api.jikan.moe/v4/anime?genres=1&order_by=members&sort=desc&type=tv&limit=25&sfw=true
```

**Romance Anime**:
```
GET https://api.jikan.moe/v4/anime?genres=22&order_by=members&sort=desc&type=tv&limit=25&sfw=true
```

**Fantasy Anime**:
```
GET https://api.jikan.moe/v4/anime?genres=10&order_by=members&sort=desc&type=tv&limit=25&sfw=true
```

**Slice of Life**:
```
GET https://api.jikan.moe/v4/anime?genres=36&order_by=members&sort=desc&type=tv&limit=25&sfw=true
```

**Sports Anime**:
```
GET https://api.jikan.moe/v4/anime?genres=30&order_by=members&sort=desc&type=tv&limit=25&sfw=true
```

### Trending Anime Right Now (AniList — better than MAL for "trending")

```
POST https://graphql.anilist.co
Content-Type: application/json

{
  "query": "query($page:Int,$perPage:Int){Page(page:$page,perPage:$perPage){media(type:ANIME,sort:TRENDING_DESC,format_not_in:[MUSIC,NOVEL],isAdult:false){id idMal title{english romaji native}coverImage{large extraLarge color}bannerImage genres averageScore popularity episodes status season seasonYear description}}}",
  "variables": { "page": 1, "perPage": 20 }
}
```

**Response**:
```json
{
  "data": {
    "Page": {
      "media": [
        {
          "id": 154587,
          "idMal": 52991,
          "title": {
            "english": "Anime Name",
            "romaji": "Anime Name Japanese",
            "native": "アニメ名"
          },
          "coverImage": {
            "large": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/...",
            "extraLarge": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/...",
            "color": "#e4a15d"
          },
          "bannerImage": "https://s4.anilist.co/file/anilistcdn/media/anime/banner/...",
          "genres": ["Action", "Adventure"],
          "averageScore": 84,
          "popularity": 150000,
          "episodes": 24,
          "status": "RELEASING",
          "season": "WINTER",
          "seasonYear": 2026,
          "description": "HTML description..."
        }
      ]
    }
  }
}
```

Use `title.english || title.romaji` for display. Use `coverImage.large` for poster. Use `bannerImage` for backdrop.

### Anime Airing Today (by day of week)

```
GET https://api.jikan.moe/v4/schedules?filter=monday&limit=25&sfw=true
```
Replace `monday` with current day. Days: `monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`, `sunday`.

### Best of a Decade (e.g., 2010s Anime)
```
GET https://api.jikan.moe/v4/anime?start_date=2010-01-01&end_date=2019-12-31&order_by=score&sort=desc&type=tv&limit=25&sfw=true
```

### Anime by Studio (e.g., MAPPA)

First find studio ID:
```
GET https://api.jikan.moe/v4/producers?q=MAPPA&order_by=favorites&sort=desc
```
→ MAPPA = producer ID `569`

Then:
```
GET https://api.jikan.moe/v4/anime?producers=569&order_by=members&sort=desc&limit=25&sfw=true
```

Common studio IDs: `569`=MAPPA, `858`=Wit Studio, `21`=Madhouse, `11`=ufotable, `4`=Bones, `2`=Kyoto Animation, `44`=Shaft, `1`=Pierrot, `10`=Production I.G, `287`=David Production

---

## 9. Personalized Rows (Trakt)

Requires Trakt OAuth. All requests need these headers:
```
trakt-api-version: 2
trakt-api-key: {TRAKT_CLIENT_ID}
Authorization: Bearer {user_access_token}
```

### My Watchlist (Movies)
```
GET https://api.trakt.tv/sync/watchlist/movies?limit=20
```

### My Watchlist (Shows)
```
GET https://api.trakt.tv/sync/watchlist/shows?limit=20
```

### Continue Watching
```
GET https://api.trakt.tv/sync/history/episodes?limit=20
```
Then for each show: `GET https://api.trakt.tv/shows/{trakt_id}/progress/watched` → find next unwatched episode.

### My Favorites
```
GET https://api.trakt.tv/sync/favorites/movies?limit=20
GET https://api.trakt.tv/sync/favorites/shows?limit=20
```

### Recommended For You
```
GET https://api.trakt.tv/recommendations/movies?limit=20
GET https://api.trakt.tv/recommendations/shows?limit=20
```

### Community Trending (no auth needed, just client ID)
```
GET https://api.trakt.tv/movies/trending?limit=20
GET https://api.trakt.tv/shows/trending?limit=20
```

### Community Most Favorited This Week
```
GET https://api.trakt.tv/movies/favorited/weekly?limit=20
GET https://api.trakt.tv/shows/favorited/weekly?limit=20
```

**Trakt response shape** (trending example):
```json
[
  {
    "watchers": 150,
    "movie": {
      "title": "Movie Name",
      "year": 2026,
      "ids": {
        "trakt": 123,
        "slug": "movie-name-2026",
        "imdb": "tt1234567",
        "tmdb": 98765
      }
    }
  }
]
```

Trakt gives you `tmdb` ID — use it to fetch poster from TMDB:
```
https://image.tmdb.org/t/p/w342{poster_path}
```
You'll need a quick `GET https://api.themoviedb.org/3/movie/{tmdb_id}?api_key={KEY}` to get the poster_path if you don't already have it cached.

---

## 10. Image URL Reference

### TMDB Image URLs

All TMDB images are constructed from a base URL + size + file_path:

| Use Case | URL Pattern | Example Size |
|----------|-------------|-------------|
| Poster (card) | `https://image.tmdb.org/t/p/{size}{poster_path}` | `w342` |
| Poster (detail) | same | `w500` |
| Poster (HD) | same | `w780` |
| Backdrop (hero) | `https://image.tmdb.org/t/p/original{backdrop_path}` | `original` |
| Backdrop (row hover) | `https://image.tmdb.org/t/p/w780{backdrop_path}` | `w780` |
| Logo (hero overlay) | `https://image.tmdb.org/t/p/w500{logo_path}` | `w500` |
| Cast photo | `https://image.tmdb.org/t/p/w276_and_h350_face{profile_path}` | — |

**Available poster sizes**: `w92`, `w154`, `w185`, `w342`, `w500`, `w780`, `original`
**Available backdrop sizes**: `w300`, `w780`, `w1280`, `original`

### MAL/Jikan Image URLs

Already full URLs in the response:
```
data.images.jpg.image_url         → small poster
data.images.jpg.large_image_url   → large poster (use this)
data.images.webp.large_image_url  → webp variant
```

### AniList Image URLs

Already full URLs:
```
coverImage.medium    → small poster
coverImage.large     → large poster (use this)
coverImage.extraLarge → HD poster
bannerImage          → backdrop/banner
```

---

## 11. Genre ID Reference

### TMDB Movie Genres

| ID | Genre |
|----|-------|
| 28 | Action |
| 12 | Adventure |
| 16 | Animation |
| 35 | Comedy |
| 80 | Crime |
| 99 | Documentary |
| 18 | Drama |
| 10751 | Family |
| 14 | Fantasy |
| 36 | History |
| 27 | Horror |
| 10402 | Music |
| 9648 | Mystery |
| 10749 | Romance |
| 878 | Science Fiction |
| 10770 | TV Movie |
| 53 | Thriller |
| 10752 | War |
| 37 | Western |

### TMDB TV Genres

| ID | Genre |
|----|-------|
| 10759 | Action & Adventure |
| 16 | Animation |
| 35 | Comedy |
| 80 | Crime |
| 99 | Documentary |
| 18 | Drama |
| 10751 | Family |
| 10762 | Kids |
| 9648 | Mystery |
| 10763 | News |
| 10764 | Reality |
| 10765 | Sci-Fi & Fantasy |
| 10766 | Soap |
| 10767 | Talk |
| 10768 | War & Politics |
| 37 | Western |

### MAL Anime Genres

| ID | Genre |
|----|-------|
| 1 | Action |
| 2 | Adventure |
| 4 | Comedy |
| 8 | Drama |
| 10 | Fantasy |
| 14 | Horror |
| 7 | Mystery |
| 22 | Romance |
| 24 | Sci-Fi |
| 36 | Slice of Life |
| 30 | Sports |
| 37 | Supernatural |
| 41 | Suspense |

Or fetch dynamically:
```
GET https://api.jikan.moe/v4/genres/anime
```

---

## 12. Rate Limits

| Provider | Limit | Strategy |
|----------|-------|----------|
| TMDB | ~40 req/sec (generous) | Parallel calls are fine, add retry on 429 |
| Jikan/MAL | 60 req/min, 3 req/sec | **Queue everything**, 350ms minimum between calls |
| AniList | 90 req/min (30 degraded) | 2s minimum between calls, sequential queue |
| Trakt | 1000 GET/5min per user | Fine for homepage, add 429 retry |
| Fanart.tv | No documented limit | Be reasonable, cache aggressively |

### Retry Pattern (for all providers)

```
On 429 response:
  1. Read Retry-After header (seconds)
  2. Wait that long (or 2s if no header)
  3. Retry up to 3 times
  4. Exponential backoff: 1s, 2s, 4s

On 5xx response:
  1. Wait 1s * 2^(attempt-1)
  2. Retry up to 3 times

On 404:
  Return null (item doesn't exist, don't retry)
```

---

## 13. Caching Strategy

### Recommended TTLs

| Row Type | Cache TTL | Why |
|----------|-----------|-----|
| Hero banner | 3 hours | Trending changes frequently |
| Top 10 | 3 hours | Weekly trending, but refresh often enough |
| Trending/popular | 3 hours | Changes throughout the day |
| Now playing / airing today | 6 hours | Changes daily |
| Genre rows | 24 hours | Stable enough, refresh daily |
| Curated/smart rows | 24 hours | Based on stable vote data |
| Decade rows (90s, 2000s) | 7 days | Almost never changes |
| Top rated (all time) | 24 hours | Very stable |
| Anime seasonal | 6 hours | New episodes air daily |
| Anime top/all time | 24 hours | Very stable |
| User watchlist | 0 (no cache) | Must be real-time |
| Continue watching | 5 minutes | Near real-time but don't spam |
| Genre ID lists | 30 days | Almost never changes |
| Image URLs | 30 days | Static assets |
| Logo images | 30 days | Almost never changes |

### Cache Key Pattern

```
homepage:{row_id}:{language}:{page}
```

Examples:
```
homepage:trending_movie_week:en-US:1
homepage:discover_movie_comedy:en-US:1
homepage:jikan_top_tv:1
homepage:anilist_trending:1
homepage:hero:en-US
```

### Implementation Pattern

```
async function getRow(rowId, fetchFn, ttlSeconds) {
  const cacheKey = `homepage:${rowId}`;

  // 1. Check Redis
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);

  // 2. Fetch from API
  const data = await fetchFn();

  // 3. Store in Redis with TTL
  await redis.setex(cacheKey, ttlSeconds, JSON.stringify(data));

  return data;
}
```

---

## 14. Response Parsing

### Unified Card Shape

Normalize all provider responses into one shape for your frontend:

```json
{
  "id": "tmdb:12345",
  "title": "Movie Name",
  "posterUrl": "https://image.tmdb.org/t/p/w342/abc.jpg",
  "backdropUrl": "https://image.tmdb.org/t/p/w780/xyz.jpg",
  "year": "2026",
  "rating": 8.2,
  "mediaType": "movie",
  "genres": ["Action", "Sci-Fi"],
  "overview": "Brief description..."
}
```

### TMDB → Card

```javascript
function parseTmdbItem(item, mediaType) {
  const type = mediaType || item.media_type; // trending/all has media_type
  return {
    id: `tmdb:${item.id}`,
    title: type === 'movie' ? item.title : item.name,
    posterUrl: item.poster_path
      ? `https://image.tmdb.org/t/p/w342${item.poster_path}`
      : null,
    backdropUrl: item.backdrop_path
      ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}`
      : null,
    year: (item.release_date || item.first_air_date || '').split('-')[0],
    rating: Math.round(item.vote_average * 10) / 10,
    mediaType: type === 'tv' ? 'series' : 'movie',
    genres: item.genre_ids, // resolve to names using genre list
    overview: item.overview
  };
}
```

### Jikan/MAL → Card

```javascript
function parseJikanItem(item) {
  return {
    id: `mal:${item.mal_id}`,
    title: item.title_english || item.title,
    posterUrl: item.images?.jpg?.large_image_url || null,
    backdropUrl: null, // MAL doesn't have backdrops
    year: item.year || (item.aired?.from || '').split('-')[0],
    rating: item.score,
    mediaType: item.type === 'Movie' ? 'movie' : 'series',
    genres: (item.genres || []).map(g => g.name),
    overview: item.synopsis
  };
}
```

### AniList → Card

```javascript
function parseAniListItem(item) {
  return {
    id: item.idMal ? `mal:${item.idMal}` : `anilist:${item.id}`,
    title: item.title.english || item.title.romaji,
    posterUrl: item.coverImage?.large || null,
    backdropUrl: item.bannerImage || null,
    year: String(item.seasonYear || ''),
    rating: item.averageScore ? item.averageScore / 10 : null, // AniList is 0-100
    mediaType: 'series',
    genres: item.genres || [],
    overview: item.description?.replace(/<[^>]*>/g, '') || '' // strip HTML
  };
}
```

### Trakt → Card (needs TMDB poster lookup)

```javascript
function parseTraktItem(item) {
  const media = item.movie || item.show;
  const type = item.movie ? 'movie' : 'series';
  return {
    id: media.ids.imdb || `tmdb:${media.ids.tmdb}`,
    tmdbId: media.ids.tmdb,  // use this to fetch poster from TMDB
    title: media.title,
    posterUrl: null, // must fetch from TMDB using tmdbId
    year: String(media.year || ''),
    rating: null,
    mediaType: type,
    genres: [],
    overview: media.overview || ''
  };
}

// Then batch-fetch posters:
async function enrichTraktItems(items) {
  const promises = items.map(async (item) => {
    if (!item.tmdbId) return item;
    const type = item.mediaType === 'movie' ? 'movie' : 'tv';
    const details = await tmdbGet(`/${type}/${item.tmdbId}?api_key=${KEY}`);
    item.posterUrl = details.poster_path
      ? `https://image.tmdb.org/t/p/w342${details.poster_path}`
      : null;
    item.rating = details.vote_average;
    return item;
  });
  return Promise.all(promises);
}
```

---

## 15. Full Homepage Blueprint

### Minimal Homepage (3 API calls)

```
Hero:           TMDB trending/all/day          (1 call)
Top Movies:     TMDB trending/movie/week       (1 call)
Top TV:         TMDB trending/tv/week          (1 call)
```

### Standard Homepage (10 API calls)

```
Hero:              TMDB trending/all/day
Top 10 Movies:     TMDB trending/movie/week
Top 10 TV:         TMDB trending/tv/week
Popular Movies:    TMDB movie/popular
Now Playing:       TMDB movie/now_playing
Popular TV:        TMDB tv/popular
Airing Today:      TMDB tv/airing_today
Comedy Movies:     TMDB discover/movie?genres=35
Action Movies:     TMDB discover/movie?genres=28
Top Rated:         TMDB movie/top_rated
```

### Full Homepage (20 API calls)

```
Hero:              TMDB trending/all/day              + 5x images (logos)
Top 10 Movies:     TMDB trending/movie/week
Top 10 TV:         TMDB trending/tv/week
Popular Movies:    TMDB movie/popular
Now Playing:       TMDB movie/now_playing
New This Year:     TMDB discover/movie?year=2026
Popular TV:        TMDB tv/popular
Airing Today:      TMDB tv/airing_today
Comedy Movies:     TMDB discover/movie?genres=35
Action Movies:     TMDB discover/movie?genres=28
Bingeworthy:       TMDB discover/tv?vote_avg≥8
Horror Movies:     TMDB discover/movie?genres=27
Sci-Fi TV:         TMDB discover/tv?genres=10765
K-Dramas:          TMDB discover/tv?language=ko&genres=18
Top Anime:         Jikan top/anime?type=tv
Trending Anime:    AniList trending query
This Season Anime: Jikan seasons/2026/winter
Top Rated Movies:  TMDB movie/top_rated
90s Classics:      TMDB discover/movie?dates=1990-1999
Documentaries:     TMDB discover/movie?genres=99
```

All 20 calls fired in parallel = full homepage data in ~1-2 seconds (before caching). After caching, it's instant.

### Full Homepage with Personalization (25+ API calls)

Add to above:
```
My Watchlist:      Trakt sync/watchlist/movies + shows
Continue Watching: Trakt sync/history + show progress
Recommended:       Trakt recommendations/movies + shows
My Favorites:      Trakt sync/favorites/movies
```

---

## 16. Pseudocode: Build the Homepage

### Architecture

```
Browser → Your Server → Redis Cache → [TMDB, Jikan, AniList, Trakt]
```

### Server-Side: Homepage Data Endpoint

```javascript
// GET /api/homepage?language=en-US

async function getHomepage(language) {
  const TMDB_KEY = process.env.TMDB_API;
  const YEAR = new Date().getFullYear();

  // Define all rows
  const rowDefinitions = [
    {
      id: 'hero',
      title: 'Featured',
      endpoint: `https://api.themoviedb.org/3/trending/all/day?api_key=${TMDB_KEY}&language=${language}`,
      parser: (data) => data.results.slice(0, 5).map(i => parseTmdbItem(i)),
      ttl: 3 * 3600  // 3 hours
    },
    {
      id: 'top10_movies',
      title: 'Top 10 Movies',
      endpoint: `https://api.themoviedb.org/3/trending/movie/week?api_key=${TMDB_KEY}&language=${language}`,
      parser: (data) => data.results.slice(0, 10).map(i => parseTmdbItem(i, 'movie')),
      ttl: 3 * 3600
    },
    {
      id: 'top10_tv',
      title: 'Top 10 TV Shows',
      endpoint: `https://api.themoviedb.org/3/trending/tv/week?api_key=${TMDB_KEY}&language=${language}`,
      parser: (data) => data.results.slice(0, 10).map(i => parseTmdbItem(i, 'tv')),
      ttl: 3 * 3600
    },
    {
      id: 'popular_movies',
      title: 'Popular Movies',
      endpoint: `https://api.themoviedb.org/3/movie/popular?api_key=${TMDB_KEY}&language=${language}&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 3 * 3600
    },
    {
      id: 'now_playing',
      title: 'Now Playing',
      endpoint: `https://api.themoviedb.org/3/movie/now_playing?api_key=${TMDB_KEY}&language=${language}&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 6 * 3600
    },
    {
      id: 'popular_tv',
      title: 'Popular TV Shows',
      endpoint: `https://api.themoviedb.org/3/tv/popular?api_key=${TMDB_KEY}&language=${language}&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'tv')),
      ttl: 3 * 3600
    },
    {
      id: 'airing_today',
      title: 'Airing Today',
      endpoint: `https://api.themoviedb.org/3/tv/airing_today?api_key=${TMDB_KEY}&language=${language}&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'tv')),
      ttl: 6 * 3600
    },
    {
      id: 'comedy_movies',
      title: 'Comedy Movies',
      endpoint: `https://api.themoviedb.org/3/discover/movie?api_key=${TMDB_KEY}&language=${language}&sort_by=popularity.desc&with_genres=35&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 24 * 3600
    },
    {
      id: 'action_movies',
      title: 'Action Movies',
      endpoint: `https://api.themoviedb.org/3/discover/movie?api_key=${TMDB_KEY}&language=${language}&sort_by=popularity.desc&with_genres=28&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 24 * 3600
    },
    {
      id: 'bingeworthy',
      title: 'Bingeworthy TV',
      endpoint: `https://api.themoviedb.org/3/discover/tv?api_key=${TMDB_KEY}&language=${language}&sort_by=vote_average.desc&vote_count.gte=500&vote_average.gte=8&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'tv')),
      ttl: 24 * 3600
    },
    {
      id: 'horror_movies',
      title: 'Horror Movies',
      endpoint: `https://api.themoviedb.org/3/discover/movie?api_key=${TMDB_KEY}&language=${language}&sort_by=popularity.desc&with_genres=27&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 24 * 3600
    },
    {
      id: 'scifi_tv',
      title: 'Sci-Fi & Fantasy TV',
      endpoint: `https://api.themoviedb.org/3/discover/tv?api_key=${TMDB_KEY}&language=${language}&sort_by=popularity.desc&with_genres=10765&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'tv')),
      ttl: 24 * 3600
    },
    {
      id: 'new_this_year',
      title: `New in ${YEAR}`,
      endpoint: `https://api.themoviedb.org/3/discover/movie?api_key=${TMDB_KEY}&language=${language}&sort_by=popularity.desc&primary_release_year=${YEAR}&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 24 * 3600
    },
    {
      id: 'top_rated',
      title: 'Top Rated All Time',
      endpoint: `https://api.themoviedb.org/3/movie/top_rated?api_key=${TMDB_KEY}&language=${language}&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'movie')),
      ttl: 24 * 3600
    },
    {
      id: 'kdramas',
      title: 'Korean Dramas',
      endpoint: `https://api.themoviedb.org/3/discover/tv?api_key=${TMDB_KEY}&language=${language}&sort_by=popularity.desc&with_original_language=ko&with_genres=18&page=1`,
      parser: (data) => data.results.map(i => parseTmdbItem(i, 'tv')),
      ttl: 24 * 3600
    }
  ];

  // Anime rows (Jikan - must be sequential due to rate limits!)
  const animeRows = [
    {
      id: 'top_anime',
      title: 'Top Anime',
      endpoint: 'https://api.jikan.moe/v4/top/anime?type=tv&limit=25&sfw=true',
      parser: (data) => data.data.map(parseJikanItem),
      ttl: 24 * 3600
    },
    {
      id: 'airing_anime',
      title: 'Anime Airing Now',
      endpoint: 'https://api.jikan.moe/v4/seasons/now?limit=25&sfw=true',
      parser: (data) => data.data.map(parseJikanItem),
      ttl: 6 * 3600
    },
    {
      id: 'upcoming_anime',
      title: 'Upcoming Anime',
      endpoint: 'https://api.jikan.moe/v4/seasons/upcoming?limit=25&sfw=true',
      parser: (data) => data.data.map(parseJikanItem),
      ttl: 6 * 3600
    }
  ];

  // AniList row
  const anilistRow = {
    id: 'trending_anime',
    title: 'Trending Anime',
    ttl: 3 * 3600,
    fetch: async () => {
      const res = await fetch('https://graphql.anilist.co', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          query: `query($page:Int,$perPage:Int){Page(page:$page,perPage:$perPage){media(type:ANIME,sort:TRENDING_DESC,format_not_in:[MUSIC,NOVEL],isAdult:false){id idMal title{english romaji}coverImage{large}bannerImage genres averageScore}}}`,
          variables: { page: 1, perPage: 20 }
        })
      });
      const json = await res.json();
      return json.data.Page.media.map(parseAniListItem);
    }
  };

  // Fetch all rows
  // TMDB rows: fire ALL in parallel (generous rate limit)
  // Jikan rows: fire sequentially (strict rate limit)
  // AniList: fire in parallel with TMDB

  const results = {};

  // Parallel group: TMDB + AniList
  const parallelPromises = rowDefinitions.map(row =>
    getRow(row.id, async () => {
      const res = await fetch(row.endpoint);
      const json = await res.json();
      return row.parser(json);
    }, row.ttl)
      .then(data => { results[row.id] = { title: row.title, items: data }; })
      .catch(err => { results[row.id] = { title: row.title, items: [], error: true }; })
  );

  parallelPromises.push(
    getRow(anilistRow.id, anilistRow.fetch, anilistRow.ttl)
      .then(data => { results[anilistRow.id] = { title: anilistRow.title, items: data }; })
      .catch(err => { results[anilistRow.id] = { title: anilistRow.title, items: [], error: true }; })
  );

  await Promise.all(parallelPromises);

  // Sequential group: Jikan (350ms between calls)
  for (const row of animeRows) {
    try {
      const data = await getRow(row.id, async () => {
        const res = await fetch(row.endpoint);
        const json = await res.json();
        return row.parser(json);
      }, row.ttl);
      results[row.id] = { title: row.title, items: data };
    } catch (err) {
      results[row.id] = { title: row.title, items: [], error: true };
    }
    await sleep(350); // Respect Jikan rate limit
  }

  // Fetch hero logos (parallel, after hero data is ready)
  if (results.hero?.items?.length) {
    const logoPromises = results.hero.items.map(async (item) => {
      const type = item.mediaType === 'movie' ? 'movie' : 'tv';
      const id = item.id.replace('tmdb:', '');
      try {
        const cached = await redis.get(`logo:${id}`);
        if (cached) { item.logoUrl = cached; return; }

        const res = await fetch(
          `https://api.themoviedb.org/3/${type}/${id}/images?api_key=${TMDB_KEY}&include_image_language=en,null`
        );
        const json = await res.json();
        if (json.logos?.[0]?.file_path) {
          item.logoUrl = `https://image.tmdb.org/t/p/w500${json.logos[0].file_path}`;
          await redis.setex(`logo:${id}`, 30 * 24 * 3600, item.logoUrl);
        }
      } catch {}
    });
    await Promise.all(logoPromises);
  }

  // Return ordered rows
  return {
    hero: results.hero,
    rows: [
      results.top10_movies,
      results.top10_tv,
      results.popular_movies,
      results.now_playing,
      results.new_this_year,
      results.popular_tv,
      results.airing_today,
      results.trending_anime,
      results.comedy_movies,
      results.bingeworthy,
      results.top_anime,
      results.action_movies,
      results.horror_movies,
      results.scifi_tv,
      results.airing_anime,
      results.kdramas,
      results.top_rated,
      results.upcoming_anime
    ].filter(row => row && row.items.length > 0)
  };
}
```

### Helper: Cache Wrapper

```javascript
async function getRow(rowId, fetchFn, ttlSeconds) {
  const cacheKey = `homepage:${rowId}`;

  // Check Redis
  const cached = await redis.get(cacheKey);
  if (cached) {
    try { return JSON.parse(cached); }
    catch { await redis.del(cacheKey); } // self-heal corrupted cache
  }

  // Fetch from API
  const data = await fetchFn();

  // Store with TTL
  if (data && data.length > 0) {
    await redis.setex(cacheKey, ttlSeconds, JSON.stringify(data));
  }

  return data;
}
```

### Detail Page: When User Clicks a Card

When a user clicks a card, you need full metadata. Use the card's `id` to fetch:

**For TMDB items** (`tmdb:12345`):
```
Movie: GET https://api.themoviedb.org/3/movie/{id}?api_key={KEY}&language=en-US&append_to_response=videos,credits,images,release_dates
TV:    GET https://api.themoviedb.org/3/tv/{id}?api_key={KEY}&language=en-US&append_to_response=videos,credits,images,content_ratings
```

**For MAL items** (`mal:5114`):
```
GET https://api.jikan.moe/v4/anime/{mal_id}/full
```

This single call gives you everything: synopsis, episodes, characters, relations, trailer, etc.

### Pagination: When User Scrolls Right

Each row can load more items. Just increment `page`:

```
Same endpoint + &page=2
```

TMDB returns 20 items per page, up to 500 pages. Jikan returns 25 per page.

---

## Appendix: TMDB Discover Filter Reference

The discover endpoint accepts all of these as query params:

| Param | Type | Example | Description |
|-------|------|---------|-------------|
| `sort_by` | string | `popularity.desc` | Sort order |
| `with_genres` | string | `28,35` (AND) or `28\|35` (OR) | Filter by genre |
| `without_genres` | string | `27` | Exclude genres |
| `primary_release_year` | int | `2026` | Exact year (movies) |
| `primary_release_date.gte` | date | `2020-01-01` | Released after (movies) |
| `primary_release_date.lte` | date | `2026-12-31` | Released before (movies) |
| `first_air_date_year` | int | `2026` | Exact year (TV) |
| `first_air_date.gte` | date | `2020-01-01` | First aired after (TV) |
| `first_air_date.lte` | date | `2026-12-31` | First aired before (TV) |
| `vote_average.gte` | float | `7.0` | Minimum rating |
| `vote_average.lte` | float | `10.0` | Maximum rating |
| `vote_count.gte` | int | `500` | Minimum vote count |
| `vote_count.lte` | int | `1000` | Maximum vote count |
| `with_original_language` | string | `ko` | Filter by language |
| `with_keywords` | string | `818\|9672` | Filter by keyword IDs |
| `without_keywords` | string | `210024` | Exclude keywords |
| `with_watch_providers` | string | `8` | Available on provider |
| `watch_region` | string | `US` | Region for provider filter |
| `with_runtime.gte` | int | `90` | Min runtime (minutes) |
| `with_runtime.lte` | int | `120` | Max runtime |
| `certification_country` | string | `US` | Country for cert filter |
| `certification` | string | `PG-13` | Exact certification |
| `certification.lte` | string | `PG-13` | Max certification |
| `with_type` | int | `2` | TV type (2=Miniseries, 4=Scripted) |
| `with_status` | int | `0` | TV status (0=Returning, 2=Ended) |
| `include_adult` | bool | `false` | Include adult content |
| `page` | int | `1` | Page number (1-500) |

### Sort Options

| Value | Description |
|-------|-------------|
| `popularity.desc` | Most popular first (default) |
| `popularity.asc` | Least popular first |
| `vote_average.desc` | Highest rated first |
| `vote_average.asc` | Lowest rated first |
| `primary_release_date.desc` | Newest first (movies) |
| `first_air_date.desc` | Newest first (TV) |
| `revenue.desc` | Highest grossing first |
| `vote_count.desc` | Most voted first |
