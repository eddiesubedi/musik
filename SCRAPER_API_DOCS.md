# Torrent Scraper & Episode Selection — Complete API Documentation

A complete reference for building a torrent scraper with debrid cache checking and intelligent episode file selection. This documents every API endpoint, data format, algorithm, and edge case — everything needed to replicate what Comet does.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Stremio ID Format](#2-stremio-id-format)
3. [Data Structures](#3-data-structures)
4. [Phase 1: Scraping Torrents](#4-phase-1-scraping-torrents)
   - [4.1 StremThru Database](#41-stremthru-database)
   - [4.2 Torrentio](#42-torrentio)
   - [4.3 Comet](#43-comet)
   - [4.4 Zilean (DMM)](#44-zilean-dmm)
   - [4.5 AnimeTosho](#45-animetosho)
   - [4.6 TorrentsDB](#46-torrentsdb)
   - [4.7 Peerflix](#47-peerflix)
   - [4.8 MediaFusion](#48-mediafusion)
   - [4.9 Nyaa.si](#49-nyaasi)
5. [Phase 2: Deduplication](#5-phase-2-deduplication)
6. [Phase 3: Cache Checking](#6-phase-3-cache-checking)
7. [Phase 4: File Selection (Episode Picking)](#7-phase-4-file-selection-episode-picking)
   - [7.1 Filename Parsing](#71-filename-parsing)
   - [7.2 Video Detection](#72-video-detection)
   - [7.3 Scoring Algorithm](#73-scoring-algorithm)
   - [7.4 Complete Selection Function](#74-complete-selection-function)
8. [Phase 5: Getting Download Links](#8-phase-5-getting-download-links)
   - [8.1 Add Magnet](#81-add-magnet)
   - [8.2 Select File](#82-select-file)
   - [8.3 Generate Link](#83-generate-link)
9. [Batch Detection & Single-Episode Filtering](#9-batch-detection--single-episode-filtering)
10. [Metadata API (Cinemeta)](#10-metadata-api-cinemeta)
11. [Authentication Headers](#11-authentication-headers)
12. [Error Handling](#12-error-handling)
13. [Complete Flow (Pseudocode)](#13-complete-flow-pseudocode)
14. [HTTP Client Requirements](#14-http-client-requirements)
15. [Testing](#15-testing)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     YOUR APPLICATION                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Phase 1: SCRAPE         Phase 2: DEDUPE    Phase 3: CACHE  │
│  ┌──────────────┐                                            │
│  │ StremThru DB │──┐                                         │
│  │ Torrentio    │──┤      ┌──────────┐     ┌─────────────┐  │
│  │ Comet        │──┤─────▶│ Dedupe   │────▶│ Cache Check  │  │
│  │ Zilean       │──┤      │ by hash  │     │ (StremThru)  │  │
│  │ AnimeTosho   │──┤      └──────────┘     └──────┬──────┘  │
│  │ TorrentsDB   │──┤                              │         │
│  │ Peerflix      │──┤                              ▼         │
│  │ MediaFusion  │──┤              Phase 4: FILE SELECTION    │
│  │ Nyaa.si      │──┘              ┌──────────────────────┐   │
│  └──────────────┘                 │ Parse filenames (RTN) │   │
│                                   │ Score each file       │   │
│                                   │ Pick best match       │   │
│                                   └──────────┬───────────┘   │
│                                              │               │
│                              Phase 5: DOWNLOAD LINK          │
│                              ┌──────────────────────┐        │
│                              │ Add magnet to debrid  │        │
│                              │ Generate direct link  │        │
│                              └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

**The 5 phases:**
1. **Scrape** — Query 5-9 sources concurrently to find torrents for a given media ID
2. **Deduplicate** — Remove duplicate torrents (same info_hash from different sources)
3. **Cache Check** — Ask the debrid service which torrents are instantly available
4. **File Selection** — For batch/multi-episode torrents, pick the correct episode file using a scoring algorithm
5. **Download Link** — Add the magnet to debrid and generate a direct download URL

---

## 2. Stremio ID Format

Every source uses "Stremio IDs" to identify content. The format differs by media type.

### Construction Rules

| Media Type | ID Format | Example |
|-----------|-----------|---------|
| Movie | `{imdb_id}` | `tt0111161` |
| TV Episode | `{imdb_id}:{season}:{episode}` | `tt0944947:1:1` |
| Anime (Kitsu) | `kitsu:{id}:{episode}` | `kitsu:12345:1` |
| Anime (AniDB) | `anidb:{id}:{episode}` | `anidb:69:1` |
| Anime (MAL) | `mal:{id}:{episode}` | `mal:21:1` |

### Important Notes

- **Anime has NO season** — anime IDs use `{provider}:{id}:{episode}`, NOT `{provider}:{id}:{season}:{episode}`
- For anime, internally set `season = 1` for file matching purposes (anime files often contain S01)
- IMDb IDs always start with `tt` followed by digits
- The `sid` parameter for StremThru uses this same format
- Stremio addon stream endpoints use this as the `{id}` path parameter

### Parsing (Pseudocode)

```
function build_stremio_id(media_type, media_id, season, episode):
    if media_type == "anime":
        return media_id + ":" + episode      // "anidb:69:1"
    else if media_type == "series":
        return media_id + ":" + season + ":" + episode  // "tt0944947:1:1"
    else:
        return media_id                       // "tt0111161"
```

### StremThru vs Stremio Addon ID Differences

StremThru's `/v0/torrents` endpoint uses a `sid` query parameter with the same format.
Stremio addons use it as a URL path: `/stream/{type}/{id}.json`

For StremThru, the `sid` is constructed the same way but passed to a different API:
- StremThru: `GET /v0/torrents?sid=anidb:69:1`
- Stremio addon: `GET /stream/series/anidb:69:1.json`

---

## 3. Data Structures

### Torrent

Represents a scraped torrent from any source.

```
Torrent {
    info_hash: string        // 40-character lowercase hex hash
    title: string            // Release name (e.g., "One.Piece.S01E01.1080p.WEB-DL.mkv")
    size: integer | null     // Total torrent size in bytes
    seeders: integer | null  // Number of seeders (if available)
    source: string           // Which scraper found it: "stremthru", "torrentio", "comet", "zilean", etc.
    tracker: string          // Tracker/indexer name: "Nyaa", "DMM", "rd", etc.
    file_index: integer | null // Pre-selected file index (from Stremio addons)
    sources: string[]        // Tracker URLs for building magnet URI
    cached: boolean          // Whether debrid has this cached (set after cache check)
}
```

### TorrentFile

Represents a single file inside a torrent (returned by debrid after adding magnet).

```
TorrentFile {
    index: integer           // File index within the torrent
    name: string             // Filename (e.g., "One Piece - 001 [1080p].mkv")
    size: integer            // File size in bytes
    link: string | null      // Debrid-specific link for this file
    season: integer | null   // Parsed season number (from filename)
    episode: integer | null  // Parsed episode number (from filename)
    score: float             // Computed selection score
    match_reasons: string[]  // Why this score was given: ["exact_episode"], ["multi_episode"], etc.
}
```

### DownloadResult

The final output — a direct download URL.

```
DownloadResult {
    link: string             // Direct download URL (time-limited, usually expires in hours)
    file_name: string        // Selected filename
    file_size: integer       // File size in bytes
    file_index: integer      // Index of selected file
    score: float             // Selection confidence score
    match_reasons: string[]  // Why this file was chosen
}
```

---

## 4. Phase 1: Scraping Torrents

All sources should be scraped **concurrently**. Each returns a list of `Torrent` objects.

### 4.1 StremThru Database

The crowdsourced torrent database. This is usually the richest source.

**Base URL:** `https://stremthru.13377001.xyz`

**Endpoint:** `GET /v0/torrents?sid={stremio_id}`

**curl:**
```bash
curl "https://stremthru.13377001.xyz/v0/torrents?sid=anidb:69:1"
```

**Response:**
```json
{
  "data": {
    "items": [
      {
        "hash": "4470BA2293BF7005D89E787853FBF2BFBBA21056",
        "name": "[Judas] One Piece (Seasons 01-20) [1080p][HEVC x265 10bit][Multi-Subs]",
        "size": 1716685824000,
        "seeders": 50,
        "src": "rd"
      }
    ]
  }
}
```

**Field mapping:**
| Response Field | Torrent Field | Notes |
|---------------|---------------|-------|
| `hash` | `info_hash` | **Lowercase it** — API returns uppercase |
| `name` | `title` | |
| `size` | `size` | In bytes |
| `seeders` | `seeders` | |
| `src` | `tracker` | Source code (see table below) |

**Source codes (`src` field):**
| Code | Meaning |
|------|---------|
| `rd` | Real-Debrid user cache |
| `ad` | AllDebrid user cache |
| `pm` | Premiumize user cache |
| `tb` | TorBox user cache |
| `tio` | Torrentio |
| `dmm` | Debrid Media Manager |
| `dht` | DHT network |
| `ato` | AnimeTosho |
| `mfn` | MediaFusion |

**Notes:**
- Requires browser impersonation (Chrome User-Agent, TLS fingerprint via curl_cffi or similar)
- Returns ALL torrents associated with this media ID — includes single-episode and batch releases
- The `sid` parameter construction differs for anime vs TV (see Section 2)

---

### 4.2 Torrentio

The most popular Stremio torrent addon.

**Base URL:** `https://torrentio.strem.fun`

**Endpoint:** `GET /stream/{type}/{id}.json`

**curl:**
```bash
# Movie
curl "https://torrentio.strem.fun/stream/movie/tt0111161.json"

# TV Episode
curl "https://torrentio.strem.fun/stream/series/tt0944947:1:1.json"

# Anime
curl "https://torrentio.strem.fun/stream/series/anidb:69:1.json"
```

**Response:**
```json
{
  "streams": [
    {
      "infoHash": "abc123def456...",
      "title": "Torrentio\n[Judas] One Piece - 001\n👤 50 💾 1.5 GB ⚙️ Nyaa",
      "fileIdx": 0,
      "sources": ["tracker:udp://tracker.opentrackr.org:1337/announce"]
    }
  ]
}
```

**Parsing the `title` field:**

The title contains the release name AND metadata in a multi-line string:

```
Line 1: Source label (e.g., "Torrentio" or "Torrentio\n")
Line N-1: Release name
Last line: 👤 {seeders} 💾 {size} ⚙️ {tracker}
```

**Regex to extract metadata from the title:**
```regex
/(?:👤 (\d+) )?💾 ([\d.]+ [KMGT]?B)(?: ⚙️ (.+))?/
```

Groups:
1. Seeders (optional) — integer
2. Size — string like "1.5 GB" (parse with size parser, see Section 7)
3. Tracker name (optional)

**To extract the release name:** take everything before the `\n💾` line, split by `\n`, take the last non-metadata line.

**Field mapping:**
| Response Field | Torrent Field | Notes |
|---------------|---------------|-------|
| `infoHash` | `info_hash` | Lowercase it |
| (parsed from title) | `title` | Release name portion |
| (parsed from title) | `seeders` | From `👤` |
| (parsed from title) | `size` | From `💾`, parse to bytes |
| `fileIdx` | `file_index` | Pre-selected file index |
| `sources` | `sources` | Tracker URLs |

**Notes:**
- Does NOT require browser impersonation
- `type` is always `movie` or `series` (anime counts as `series`)
- `fileIdx` can be `null` for single-file torrents

---

### 4.3 Comet

Comet's shared database.

**Base URL:** `https://comet.feels.legal`

**Endpoint:** `GET /stream/{type}/{id}.json`

**curl:**
```bash
curl "https://comet.feels.legal/stream/series/anidb:69:1.json"
```

**Response:** Same structure as Torrentio (`streams` array) but different `description` format:

```json
{
  "streams": [
    {
      "infoHash": "abc123...",
      "description": "📄 [Judas] One Piece - 001 [1080p]\n👤 50\n🔎 Nyaa",
      "behaviorHints": {
        "videoSize": 1500000000
      }
    }
  ]
}
```

**Parsing the `description` field:**
- **Title:** after `📄 ` until newline
- **Seeders:** after `👤 ` parse integer
- **Tracker:** after `🔎 ` until newline
- **Size:** from `behaviorHints.videoSize` (in bytes)

---

### 4.4 Zilean (DMM)

Zilean indexes Debrid Media Manager hashlists. Uses a text search query (title) instead of Stremio ID.

**Base URL:** `https://zileanfortheweebs.midnightignite.me`

**Endpoint:** `GET /dmm/filtered`

**Parameters:**
| Param | Required | Description |
|-------|----------|-------------|
| `query` | Yes | Search title (e.g., "One Piece") |
| `season` | No | Season number (for filtering) |
| `episode` | No | Episode number (for filtering) |

**curl:**
```bash
curl "https://zileanfortheweebs.midnightignite.me/dmm/filtered?query=One%20Piece&season=1&episode=1"
```

**Response:**
```json
[
  {
    "info_hash": "abc123...",
    "raw_title": "One.Piece.S01E01.1080p.WEB-DL.mkv",
    "size": 1500000000
  }
]
```

**IMPORTANT:** The `size` field can be either an **integer** or a **string**. Your JSON parser must handle both:
```
"size": 1500000000      // integer
"size": "1500000000"    // string — parse to integer
```

**Field mapping:**
| Response Field | Torrent Field |
|---------------|---------------|
| `info_hash` | `info_hash` (lowercase it) |
| `raw_title` | `title` |
| `size` | `size` (handle string or int) |

**Notes:**
- Does NOT require browser impersonation
- Requires the media title (not just an ID), so you need either user input or a metadata API call
- Returns a flat array (not wrapped in `data`)

---

### 4.5 AnimeTosho

Anime-specific torrent indexer using the Torznab XML API.

**Base URL:** `https://feed.animetosho.org`

**Endpoint:** `GET /api`

**Parameters:**
| Param | Required | Description |
|-------|----------|-------------|
| `t` | Yes | Always `search` |
| `q` | Yes | Search query |
| `limit` | No | Max results (recommended: 150) |

**curl:**
```bash
curl "https://feed.animetosho.org/api?t=search&q=One%20Piece&limit=150"
```

**Response:** XML (Torznab format)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss>
  <channel>
    <item>
      <title>[SubsPlease] One Piece - 001 (1080p)</title>
      <torznab:attr name="infohash" value="abc123def456..."/>
      <torznab:attr name="size" value="1500000000"/>
      <torznab:attr name="seeders" value="50"/>
      <torznab:attr name="magneturl" value="magnet:?xt=urn:btih:abc123...&amp;tr=..."/>
    </item>
  </channel>
</rss>
```

**XML namespace:** `http://torznab.com/schemas/2015/feed`

**Extracting data from `torznab:attr` elements:**
| `name` attribute | Maps to | Type |
|-----------------|---------|------|
| `infohash` | `info_hash` | string (lowercase it) |
| `size` | `size` | integer (bytes) |
| `seeders` | `seeders` | integer |
| `magneturl` | (extract tracker URLs for `sources`) | string |

**Extracting tracker URLs from magnet:**
```regex
/tr=([^&]+)/g
```
Each match is a URL-encoded tracker URL — add to `sources` array.

**Notes:**
- Does NOT require browser impersonation
- Returns XML, not JSON — you need an XML parser
- Title-based search only (no Stremio IDs)

---

### 4.6 TorrentsDB

**Base URL:** `https://torrentsdb.com`

**Endpoint:** `GET /stream/{type}/{id}.json`

**curl:**
```bash
curl "https://torrentsdb.com/stream/series/tt0944947:1:1.json"
```

**Response:** Same Stremio stream format as Torrentio. Title format:
```
Release.Name.S01E01.1080p
📅 S01E01 👤 50 💾 1.5 GB ⚙️ TrackerName
```

Parse with the same regex as Torrentio.

---

### 4.7 Peerflix

**Base URL:** `https://peerflix.mov`

**Endpoint:** `GET /stream/{type}/{id}.json`

**curl:**
```bash
curl "https://peerflix.mov/stream/series/tt0944947:1:1.json"
```

**Response:** Stremio stream format. Extra fields:
```json
{
  "infoHash": "abc123...",
  "description": "Release.Name.S01E01\n🌐 tracker.example.com",
  "sizebytes": 1500000000,
  "seed": 50
}
```

**Notes:**
- May return 404 for anime IDs — handle gracefully
- `sizebytes` and `seed` are non-standard fields (specific to Peerflix)

---

### 4.8 MediaFusion

**Base URL:** `https://mediafusion.elfhosted.com` (public, but usually blocked)

**Endpoint:** `GET /stream/{type}/{id}.json`

**IMPORTANT:** The public ElfHosted instance returns HTTP 418 ("I'm a teapot") for unauthenticated requests. You need either:
1. A self-hosted MediaFusion instance
2. An API password

**Headers:** MediaFusion requires a base64-encoded user config:
```json
{
  "ap": "",       // API password (empty string if none)
  "nf": ["Disable"],
  "cf": ["Disable"],
  "lss": true
}
```

Base64url-encode this JSON and pass it in a header or URL path.

**Response format:**
```json
{
  "streams": [
    {
      "infoHash": "abc123...",
      "description": "📂 Release.Name/\n👤 50\n🔗 Tracker",
      "behaviorHints": {
        "videoSize": 1500000000
      }
    }
  ]
}
```

**Parsing:**
- Title: after `📂 ` remove trailing `/`
- Seeders: after `👤 ` parse integer
- Tracker: after `🔗 ` until newline
- Size: from `behaviorHints.videoSize`

---

### 4.9 Nyaa.si

Anime/Asian content tracker. Requires HTML scraping.

**Base URL:** `https://nyaa.si`

**Endpoint:** `GET /?q={query}`

**curl:**
```bash
curl "https://nyaa.si/?q=One%20Piece"
```

**IMPORTANT:** Requires browser impersonation (Chrome TLS fingerprint). Standard HTTP clients get blocked.

**Response:** HTML page. Extract data using these regex patterns:

| Data | Regex Pattern |
|------|--------------|
| Magnet links | `href="(magnet:[^"]+)"` |
| Hash from magnet | `btih:([a-fA-F0-9]{40})` |
| Sizes | `<td class="text-center">([\d.]+ (?:KiB\|MiB\|GiB\|TiB))</td>` |
| Seeders | 3rd `<td class="text-center">(\d+)</td>` per row |
| Titles | `href="/view/\d+" title="([^"]+)"` |

**Size conversion:** Nyaa uses binary units (KiB, MiB, GiB). Convert `iB` → `B` then parse normally.

---

## 5. Phase 2: Deduplication

After scraping all sources, remove duplicate torrents by `info_hash`.

```
function deduplicate(all_torrents):
    seen = {}  // hash → Torrent

    for torrent in all_torrents:
        hash = torrent.info_hash.lowercase()
        if hash not in seen:
            seen[hash] = torrent

    return seen.values()
```

**Notes:**
- Always lowercase hashes before comparing (some APIs return uppercase)
- When deduplicating, you can keep whichever copy has more metadata (size, seeders, etc.)
- Typical dedup ratio: scrape ~3000 total → ~1500 unique

---

## 6. Phase 3: Cache Checking

Check which torrents your debrid service has instantly available (already downloaded by someone).

### Endpoint

**URL:** `POST https://stremthru.13377001.xyz/v0/store/magnets/check` (also supports GET)

**Using GET (simpler):**
```
GET /v0/store/magnets/check?magnet={hash1},{hash2},{hash3}&sid={stremio_id}
```

**curl:**
```bash
curl -H "X-StremThru-Store-Name: realdebrid" \
     -H "X-StremThru-Store-Authorization: Bearer YOUR_RD_TOKEN" \
     "https://stremthru.13377001.xyz/v0/store/magnets/check?magnet=hash1,hash2,hash3&sid=anidb:69:1"
```

### Request Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `magnet` | Yes | Comma-separated hashes (max 100 per request) |
| `sid` | No | Stremio ID for context (improves accuracy) |
| `client_ip` | No | Client IP address |

### Response

```json
{
  "data": {
    "items": [
      {
        "hash": "4470ba2293bf7005d89e787853fbf2bfbba21056",
        "status": "cached",
        "files": [
          {
            "index": 0,
            "name": "One Piece - 001 [1080p].mkv",
            "size": 1500000000
          }
        ]
      },
      {
        "hash": "deadbeef...",
        "status": "not_cached"
      }
    ]
  }
}
```

**Status values:**
| Status | Meaning |
|--------|---------|
| `cached` | Instantly available — can download immediately |
| `not_cached` | Not in debrid cache — would need to download first |

### Batching

**Maximum 100 hashes per request.** Split into chunks:

```
function check_cache(hashes, rd_token, sid):
    cached_hashes = set()

    for chunk in split_into_chunks(hashes, 100):
        url = STREMTHRU_URL + "/v0/store/magnets/check"
        url += "?magnet=" + chunk.join(",")
        if sid:
            url += "&sid=" + url_encode(sid)

        response = http_get(url, headers=auth_headers(rd_token))

        for item in response.data.items:
            if item.status == "cached":
                cached_hashes.add(item.hash.lowercase())

    return cached_hashes
```

### Why Not Real-Debrid Directly?

Real-Debrid **disabled** their instant availability API (error code 37: `disabled_endpoint`). You MUST use StremThru's cache check instead — it maintains its own cache database and checks against the debrid provider.

---

## 7. Phase 4: File Selection (Episode Picking)

**This is the core algorithm.** When a torrent is a batch (e.g., "One Piece Complete Series"), it contains hundreds of files. You need to pick the one file that matches the requested episode.

This is an **exact replication** of Comet's algorithm from `comet/debrid/stremthru.py`.

### 7.1 Filename Parsing

Parse season and episode numbers from filenames. In Comet, this is done by the `RTN` (rank-torrent-name) library. If you're implementing from scratch, here are the regex patterns in priority order:

**Pattern 1: S01E01 format** (most common for TV)
```regex
/[Ss](\d{1,2})[Ee](\d{1,4})/
```
Match: `One.Piece.S01E001.1080p.mkv` → season=1, episode=1
Groups: (season, episode)

**Pattern 2: 1x01 format**
```regex
/(\d{1,2})x(\d{2,4})/
```
Match: `One.Piece.1x01.mkv` → season=1, episode=1
Groups: (season, episode)

**Pattern 3: Standalone E01** (common for anime)
```regex
/[.\s\-_][Ee](\d{2,4})[.\s\-_]/
```
Match: `One.Piece.E001.1080p.mkv` → episode=1 (no season)
Groups: (episode)

**Pattern 4: Episode XX** (spelled out)
```regex
/[Ee]pisode\s*(\d{1,4})/i
```
Match: `One Piece Episode 001.mkv` → episode=1
Groups: (episode)

**Pattern 5: Bare number with separators** (anime style: `- 001 -`)
```regex
/[\s.\-_](\d{2,4})[\s.\-_](?:v\d)?(?:[\s.\-_\[\(]|$)/
```
Match: `[SubsPlease] One Piece - 001 (1080p).mkv` → episode=1
Groups: (episode)

**Multi-episode detection:**
```regex
/[Ee](\d{2,4})\s*-\s*[Ee]?(\d{2,4})/
```
Match: `One.Piece.E01-E05.mkv` → episodes=[1,2,3,4,5]

**Implementation:**
```
function parse_filename(filename):
    result = { seasons: [], episodes: [] }

    // Try patterns in order, return on first match
    for each pattern:
        match = regex_search(pattern, filename)
        if match:
            extract season/episode from groups
            return result

    return result  // empty if no match
```

### 7.2 Video Detection

**Video extensions** (exact list from Comet `comet/utils/parsing.py`):
```
.3g2, .3gp, .amv, .asf, .avi, .drc, .f4a, .f4b, .f4p, .f4v,
.flv, .gif, .gifv, .m2v, .m4p, .m4v, .mkv, .mov, .mp2, .mp4,
.mpg, .mpeg, .mpv, .mng, .mpe, .mxf, .nsv, .ogg, .ogv, .qt,
.rm, .rmvb, .roq, .svi, .webm, .wmv, .yuv
```

```
function is_video(filename):
    return filename.lowercase().ends_with(any of VIDEO_EXTENSIONS)

function is_sample(filename):
    return "sample" in filename.lowercase()
```

### 7.3 Scoring Algorithm

**This is the exact Comet scoring system** (from `comet/debrid/stremthru.py` lines 300-347).

Each video file gets a score. The file with the highest score wins.

**Score components:**

| Points | Condition | Reason Label |
|--------|-----------|-------------|
| **+1000** | Season matches (or no season in filename) AND episode matches AND only 1 episode in file | `exact_episode` |
| **+500** | Season matches AND episode is one of multiple episodes in file | `multi_episode` |
| **+200** | Episode matches but season doesn't match | `episode_only` |
| **+100** | Filename exactly equals the torrent name | `exact_name` |
| **+50** | Title/alias matches (Comet uses RTN `title_match`) | `alias` or `title` |
| **+25** | File index matches the pre-selected index | `index` |
| **+0 to +10** | File size tiebreaker (larger = higher, capped at 10GB) | (no label) |

**Size tiebreaker formula:**
```
size_score = min(file_size_bytes / (10 * 1024 * 1024 * 1024), 10)
```
This normalizes file size to a 0-10 range so it only matters when other scores are tied.

**Season matching logic (important!):**
```
season_matches = (parsed.seasons is EMPTY) OR (target_season IN parsed.seasons)
```
If the filename has **no season info**, it's treated as a match. This handles anime files like `One Piece - 001.mkv` which don't include season numbers.

**Episode matching logic:**
```
episode_matches = (parsed.episodes is NOT EMPTY) AND (target_episode IN parsed.episodes)
```
The file MUST have a parseable episode number that matches.

### 7.4 Complete Selection Function

```
function select_best_file(files, target_season, target_episode, torrent_name):
    scored_files = []

    for file in files:
        filename = file.name

        // Step 1: Filter
        if is_sample(filename):
            continue
        if not is_video(filename):
            continue
        if file.link is null or empty:  // need a link to download
            continue

        // Step 2: Parse
        parsed = parse_filename(filename)

        // Step 3: Score
        score = 0.0
        match_reasons = []

        // Season + Episode matching (highest priority)
        if target_season is not null AND target_episode is not null:
            season_matches = (parsed.seasons is empty) OR (target_season in parsed.seasons)
            episode_matches = (parsed.episodes is not empty) AND (target_episode in parsed.episodes)

            if season_matches AND episode_matches:
                if length(parsed.episodes) == 1:
                    score += 1000    // Perfect single episode match
                    match_reasons.append("exact_episode")
                else:
                    score += 500     // Multi-episode file
                    match_reasons.append("multi_episode")
            else if episode_matches:
                score += 200         // Episode matches, season doesn't
                match_reasons.append("episode_only")

        // Exact filename match
        if filename == torrent_name:
            score += 100
            match_reasons.append("exact_name")

        // File size tiebreaker
        size_score = min(file.size / (10 * 1024 * 1024 * 1024), 10)
        score += size_score

        scored_files.append({
            ...file,
            season: parsed.seasons[0] if exists else null,
            episode: parsed.episodes[0] if exists else null,
            score: score,
            match_reasons: match_reasons
        })

    if scored_files is empty:
        return null

    // Sort by score descending
    scored_files.sort(by: score, descending)

    return scored_files[0]
```

### Score Examples

| File | Target | Score | Reason |
|------|--------|-------|--------|
| `One.Piece.S01E001.1080p.mkv` | S01E001 | ~1000.1 | exact_episode + size |
| `One.Piece.E001-E010.1080p.mkv` | S01E005 | ~500.5 | multi_episode + size |
| `One.Piece.001.mkv` | S01E001 | ~1000.1 | exact_episode (no season = match) |
| `One.Piece.S02E001.mkv` | S01E001 | ~200.1 | episode_only (season mismatch) |
| `Random.Video.mkv` | S01E001 | ~0.3 | size_fallback only |

---

## 8. Phase 5: Getting Download Links

Three API calls in sequence: add magnet → select file → generate link.

### 8.1 Add Magnet

**Endpoint:** `POST https://stremthru.13377001.xyz/v0/store/magnets`

**Headers:**
```
X-StremThru-Store-Name: realdebrid
X-StremThru-Store-Authorization: Bearer {rd_token}
Content-Type: application/json
```

**Body:**
```json
{
  "magnet": "magnet:?xt=urn:btih:{hash}&dn={url_encoded_name}&tr={tracker1}&tr={tracker2}"
}
```

**Building the magnet URI:**
```
function build_magnet(hash, name, trackers):
    magnet = "magnet:?xt=urn:btih:" + hash
    magnet += "&dn=" + url_encode(name)
    for tracker in trackers:
        magnet += "&tr=" + url_encode(tracker)
    return magnet
```

**curl:**
```bash
curl -X POST "https://stremthru.13377001.xyz/v0/store/magnets" \
     -H "X-StremThru-Store-Name: realdebrid" \
     -H "X-StremThru-Store-Authorization: Bearer YOUR_RD_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"magnet":"magnet:?xt=urn:btih:HASH&dn=NAME"}'
```

**Response:**
```json
{
  "data": {
    "id": "magnet_id_123",
    "hash": "4470ba2293bf7005d89e787853fbf2bfbba21056",
    "name": "One Piece Complete",
    "status": "downloaded",
    "files": [
      {
        "index": 0,
        "name": "One Piece - 001 [1080p].mkv",
        "size": 1580000000,
        "link": "https://real-debrid.com/d/XXXXX"
      },
      {
        "index": 1,
        "name": "One Piece - 002 [1080p].mkv",
        "size": 1520000000,
        "link": "https://real-debrid.com/d/YYYYY"
      }
    ]
  }
}
```

**Status values:**
| Status | Meaning | Action |
|--------|---------|--------|
| `downloaded` | Ready — proceed to file selection | Continue |
| `downloading` | Still being downloaded | Abort or wait |
| `queued` | In download queue | Abort or wait |
| `error` | Failed | Abort, try next torrent |

**IMPORTANT:** Only proceed if `status == "downloaded"`. If not downloaded, the file links won't work.

### 8.2 Select File

Take the `files` array from the magnet response and run it through the scoring algorithm (Section 7.4):

```
best_file = select_best_file(
    files = response.data.files,
    target_season = season,
    target_episode = episode,
    torrent_name = original_torrent.title
)

if best_file is null:
    // No suitable video file found — try next torrent
    return null
```

### 8.3 Generate Link

**Endpoint:** `POST https://stremthru.13377001.xyz/v0/store/link/generate`

**Headers:** Same auth headers as above.

**Body:**
```json
{
  "link": "https://real-debrid.com/d/XXXXX"
}
```

The `link` value comes from the selected file's `link` field.

**curl:**
```bash
curl -X POST "https://stremthru.13377001.xyz/v0/store/link/generate" \
     -H "X-StremThru-Store-Name: realdebrid" \
     -H "X-StremThru-Store-Authorization: Bearer YOUR_RD_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"link":"https://real-debrid.com/d/XXXXX"}'
```

**Response:**
```json
{
  "data": {
    "link": "https://lax2-4.download.real-debrid.com/d/CKAGTUSCAWMDA23/One.Piece.001.1080p.mkv"
  }
}
```

This is the **direct download URL** — time-limited, usually valid for a few hours. Stream or download from this URL directly.

---

## 9. Batch Detection & Single-Episode Filtering

Before cache checking, you may want to filter out batch torrents to only keep single-episode releases. This is useful when you want the exact episode, not a 500GB complete series.

### Batch Detection Patterns (to EXCLUDE)

```regex
/\d+\s*[-~]\s*\d{2,}/          // 1-100, 01~50, 001-928
/[Ss]\d+\s*-\s*[Ss]\d+/        // S01-S22
/\bbatch\b/i
/\bcomplete\b/i
/\bcollection\b/i
/\ball\s*episodes?\b/i
/\[\s*\d+\s*[-~]\s*\d+\s*\]/   // [1-100], [001~100]
/\(\s*\d+\s*[-~]\s*\d+\s*\)/   // (1-100), (001~100)
/[Ss]eason\s*\d+\s*-\s*\d+/    // Season 1-20
/[Ss]\d+-[Ss]\d+/               // S01-S21
```

### Single-Episode Patterns (to MATCH)

```regex
/\b[Ee]p?\.?\s*{ep2}\b/        // E01, Ep01, Ep.01
/\b[Ee]p?\.?\s*{ep3}\b/        // E001, Ep001
/\b[Ee]pisode\s*{ep2}\b/       // Episode 01
/\b[Ee]pisode\s*{ep3}\b/       // Episode 001
/\s-\s*{ep2}\b/                 // - 01
/\s-\s*{ep3}\b/                 // - 001
/\[{ep2}\]/                     // [01]
/\[{ep3}\]/                     // [001]
/\({ep2}\)/                     // (01)
/\({ep3}\)/                     // (001)
/[Ss]\d+[Ee]{ep2}\b/           // S01E01
/\b{ep2}v\d/                    // 01v2 (version)
/\b{ep3}v\d/                    // 001v2
```

Where `{ep2}` = zero-padded to 2 digits, `{ep3}` = zero-padded to 3 digits.

### Filter Function

```
function is_single_episode(title, episode):
    ep2 = zero_pad(episode, 2)  // "01"
    ep3 = zero_pad(episode, 3)  // "001"

    // First check if it's a batch — exclude
    for pattern in BATCH_PATTERNS:
        if regex_match(pattern, title):
            return false

    // Then check if it matches the specific episode
    for pattern in EPISODE_PATTERNS:
        if regex_match(pattern, title):
            return true

    return false  // unknown — exclude to be safe
```

---

## 10. Metadata API (Cinemeta)

If you need movie/show metadata (title, poster, description, etc.) to feed into title-based scrapers like Zilean.

**Base URL:** `https://v3-cinemeta.strem.io`

### Search

```bash
curl "https://v3-cinemeta.strem.io/catalog/series/top/search=breaking%20bad.json"
```

### Get Metadata

```bash
# Movie
curl "https://v3-cinemeta.strem.io/meta/movie/tt0111161.json"

# Series
curl "https://v3-cinemeta.strem.io/meta/series/tt0944947.json"
```

Returns title, description, cast, genres, poster, background, year, runtime, IMDb rating, trailers, and episode lists.

### Images

| Type | URL Pattern | Sizes |
|------|------------|-------|
| Poster | `https://images.metahub.space/poster/{size}/{imdb_id}/img` | small, medium, large |
| Background | `https://images.metahub.space/background/{size}/{imdb_id}/img` | small, medium, large |
| Logo | `https://images.metahub.space/logo/{size}/{imdb_id}/img` | small, medium, large |
| Episode Thumb | `https://episodes.metahub.space/{imdb_id}/{season}/{episode}/w780.jpg` | w780 only |

---

## 11. Authentication Headers

All debrid-related endpoints (cache check, add magnet, generate link) require these headers:

```
X-StremThru-Store-Name: {debrid_service}
X-StremThru-Store-Authorization: Bearer {api_token}
```

**Supported debrid services** (for `X-StremThru-Store-Name`):
| Value | Service |
|-------|---------|
| `realdebrid` | Real-Debrid |
| `alldebrid` | AllDebrid |
| `premiumize` | Premiumize |
| `torbox` | TorBox |
| `offcloud` | Offcloud |
| `pikpak` | PikPak |
| `easydebrid` | EasyDebrid |
| `debridlink` | DebridLink |
| `1fichier` | 1Fichier |

---

## 12. Error Handling

### API Error Format

All StremThru endpoints return errors in this format:
```json
{
  "error": {
    "code": "error_code",
    "message": "Human readable description"
  }
}
```

### Common Errors

| Code | Message | Action |
|------|---------|--------|
| `invalid_token` | Bad API key | Check your debrid token |
| `no_subscription` | Subscription expired | Renew debrid account |
| `disabled_endpoint` | API disabled | Use alternative endpoint |
| `rate_limited` | Too many requests | Back off and retry |

### HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Process response |
| 400 | Bad request | Check parameters |
| 401 | Unauthorized | Check API token |
| 403 | Forbidden | Need browser impersonation |
| 404 | Not found | Content not available on this source |
| 418 | I'm a teapot | Bot protection (MediaFusion) |
| 429 | Rate limited | Retry with exponential backoff |
| 500+ | Server error | Retry with backoff |

### Retry Strategy

```
function fetch_with_retry(url, options, max_retries=3):
    for attempt in 0..max_retries:
        response = http_request(url, options)

        if response.status == 429:
            delay = response.headers["Retry-After"] or (2 ^ attempt) seconds
            sleep(delay)
            continue

        return response

    throw "Max retries exceeded"
```

### Graceful Source Failure

Each scraper source should fail independently. If Torrentio is down, still return results from other sources:

```
results = parallel_map(scrapers, catch_errors=true)
valid_results = results.filter(r => r is not error)
```

---

## 13. Complete Flow (Pseudocode)

```
function stream_episode(media_type, media_id, season, episode, title, rd_token):
    //
    // PHASE 1: Build IDs
    //
    if media_type == "anime":
        stremio_id = media_id + ":" + episode   // "anidb:69:1"
        internal_season = 1                      // anime uses season=1
        internal_episode = episode
    else if media_type == "series":
        stremio_id = media_id + ":" + season + ":" + episode
        internal_season = season
        internal_episode = episode
    else:
        stremio_id = media_id
        internal_season = null
        internal_episode = null

    //
    // PHASE 2: Scrape all sources concurrently
    //
    all_torrents = parallel([
        scrape_stremthru(media_id, internal_season, internal_episode, is_anime),
        scrape_addon(TORRENTIO_URL, "series", stremio_id),
        scrape_addon(COMET_URL, "series", stremio_id),
        scrape_addon(TORRENTSDB_URL, "series", stremio_id),
        scrape_addon(PEERFLIX_URL, "series", stremio_id),
        scrape_zilean(title, internal_season, internal_episode),  // needs title
        scrape_animetosho(title),                                  // needs title
    ])

    //
    // PHASE 3: Deduplicate
    //
    unique = deduplicate_by_hash(flatten(all_torrents))

    //
    // PHASE 4: Cache check
    //
    hashes = unique.map(t => t.info_hash)
    cached = check_cache(hashes, rd_token, stremio_id)  // chunks of 100

    cached_torrents = unique.filter(t => t.info_hash in cached)

    if cached_torrents is empty:
        return error("No cached torrents")

    //
    // PHASE 5: Sort (prefer larger, more seeders)
    //
    cached_torrents.sort(by: [size desc, seeders desc])

    //
    // PHASE 6: Get download link (try each cached torrent)
    //
    for torrent in cached_torrents:
        // Add magnet to debrid
        magnet = build_magnet(torrent.info_hash, torrent.title, torrent.sources)
        magnet_response = POST /v0/store/magnets { magnet: magnet }

        if magnet_response.data.status != "downloaded":
            continue  // try next

        // Select correct file
        best_file = select_best_file(
            magnet_response.data.files,
            internal_season,
            internal_episode,
            torrent.title
        )

        if best_file is null or best_file.link is null:
            continue  // try next

        // Generate direct link
        link_response = POST /v0/store/link/generate { link: best_file.link }

        return {
            url: link_response.data.link,
            filename: best_file.name,
            size: best_file.size,
            score: best_file.score,
            reasons: best_file.match_reasons
        }

    return error("Could not get download link from any cached torrent")
```

---

## 14. HTTP Client Requirements

### Browser Impersonation

Some endpoints (StremThru, Nyaa) require TLS fingerprint impersonation to avoid bot detection.

| Language | Library |
|----------|---------|
| Python | `curl_cffi` (`pip install curl_cffi`) |
| Go | Standard `net/http` works for most; `github.com/nicjohnson145/curl-cffi-go` for Nyaa |
| Node.js | `got-scraping` or `undici` |
| Rust | `reqwest` with impersonate feature |

### Minimum Headers

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36
```

### Timeouts

Recommended: 30 seconds per request. Some sources (Zilean, AnimeTosho) can be slow.

### Concurrency

All source scrapers should run concurrently. Cache check chunks can also be parallelized.

---

## 15. Testing

### Test Cases

| Scenario | Type | ID | Season | Episode |
|----------|------|----|--------|---------|
| Movie | movie | `tt0111161` | - | - |
| TV Episode | series | `tt0944947` | 1 | 1 |
| Anime (single ep) | anime | `anidb:69` | - | 1 |
| Anime (from batch) | anime | `anidb:69` | - | 500 |

### Hash for Batch Testing

Use this hash for testing file selection from a batch torrent:
```
4470ba2293bf7005d89e787853fbf2bfbba21056
```
This is a One Piece complete series batch. Test with episodes 1, 500, 1000 to verify the scoring algorithm picks the right file.

### Expected Scores

| File in Torrent | Target Episode | Expected Score | Reason |
|----------------|---------------|----------------|--------|
| `One Piece - 001 [1080p].mkv` | 1 | ~1000.1 | exact_episode |
| `One Piece - 500 [1080p].mkv` | 500 | ~1000.1 | exact_episode |
| `One Piece - E01-E10.mkv` | 5 | ~500.5 | multi_episode |
| `One Piece - S02E001.mkv` | 1 (target S01) | ~200.1 | episode_only |
| `Extras/Making.Of.mkv` | 1 | skipped | sample/non-match |

### Verification Steps

1. **Scraping:** Run scraper for `anidb:69:1` — should return 400+ torrents from StremThru alone
2. **Dedup:** Unique count should be ~60-70% of total
3. **Cache:** With a valid RD token, should find 50-200 cached torrents
4. **File selection:** For the batch hash above with episode 1, should return a file matching `001` or `E01` or `Episode 1`
5. **Download link:** Should return a `https://*.download.real-debrid.com/...` URL

---

## Size Parsing Reference

Multiple sources return sizes as strings. Here's how to convert:

```
function parse_size(size_string):
    // Match: "1.5 GB", "500 MB", "2.3 TB", "750 KiB"
    match = regex(/([\d.]+)\s*([KMGT]?)i?[Bb]/, size_string)
    if not match:
        return null

    number = float(match[1])
    unit = match[2].uppercase()

    multipliers = {
        "":  1,
        "K": 1024,
        "M": 1024 * 1024,         // 1,048,576
        "G": 1024 * 1024 * 1024,  // 1,073,741,824
        "T": 1024^4               // 1,099,511,627,776
    }

    return integer(number * multipliers[unit])
```

**Note:** Some sources use binary (KiB, MiB, GiB) and some use decimal (KB, MB, GB). The regex handles both by optionally matching the `i`.
