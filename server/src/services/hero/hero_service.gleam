import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lib/cache
import lib/cinemeta/models as cinemeta_models
import lib/cinemeta/operations as cinemeta
import lib/fanart/fanart
import lib/reelgood/operations as reelgood
import pog
import plumbing/sql
import services/hero/errors
import services/hero/models.{type HeroContent, HeroContent}

// --- Public ---

// Refresh if heroes are older than 11 hours (in minutes).
// Scheduler runs every 12h, threshold is 11h so we don't skip a cycle
// due to timing drift.
const refresh_threshold_minutes = 660

pub fn start(db: pog.Connection) -> Nil {
  let age = case sql.hero_content_age_minutes(db) {
    Ok(pog.Returned(_, [row])) -> row.age_minutes
    _ -> 999_999
  }

  case age >= refresh_threshold_minutes {
    False -> {
      echo "[hero] content is "
        <> int.to_string(age)
        <> "min old, skipping refresh"
      Nil
    }
    True -> {
      echo "[hero] content is "
        <> int.to_string(age)
        <> "min old, refreshing"
      let _ = sql.delete_hero_content(db, "movie")
      let _ = sql.delete_hero_content(db, "series")
      Nil
    }
  }

  // Clean up any rows with missing images (from older code or failed runs)
  let _ = sql.delete_incomplete_heroes(db)

  // Always top up to target in case previous fetches had errors
  fill_heroes(db, "movie", 20)
  fill_heroes(db, "series", 20)
  let _ = echo "[hero] done"
  Nil
}

pub fn get_random_heroes(
  db: pog.Connection,
  media_type: String,
  count: Int,
) -> List(HeroContent) {
  case sql.get_hero_content(db, media_type, count) {
    Ok(pog.Returned(_, rows)) ->
      list.map(rows, fn(row) {
        HeroContent(
          id: row.id,
          imdb_id: row.imdb_id,
          name: row.name,
          description: row.description,
          year: row.year,
          imdb_rating: row.imdb_rating,
          genres: row.genres,
          media_type: row.media_type,
          background: row.background,
          logo: row.logo,
          poster: row.poster,
        )
      })
    Error(_) -> []
  }
}

// --- Fill loop ---

fn fill_heroes(db: pog.Connection, content_kind: String, target: Int) -> Nil {
  let current = case sql.count_hero_content(db, content_kind) {
    Ok(pog.Returned(_, [row])) -> row.total
    _ -> 0
  }

  let needed = target - current
  echo "Fetching " <> string.inspect(needed) <> " " <> content_kind
  fetch_loop(db, content_kind, needed, 40)
}

fn fetch_loop(
  db: pog.Connection,
  content_kind: String,
  remaining: Int,
  retries: Int,
) -> Nil {
  case remaining <= 0 || retries <= 0 {
    True -> Nil
    False -> {
      case fetch_one(content_kind) {
        Ok(hero) -> {
          let _ =
            sql.insert_hero_content(
              db,
              hero.id,
              hero.imdb_id,
              hero.name,
              hero.description,
              hero.year,
              hero.imdb_rating,
              hero.genres,
              hero.media_type,
              hero.background,
              hero.logo,
              hero.poster,
            )
          echo "Cached: " <> hero.name
          process.sleep(2000)
          fetch_loop(db, content_kind, remaining - 1, retries)
        }
        Error(err) -> {
          echo err
          process.sleep(2000)
          fetch_loop(db, content_kind, remaining, retries - 1)
        }
      }
    }
  }
}

// --- Single item fetch ---

fn fetch_one(content_kind: String) -> Result(HeroContent, errors.HeroError) {
  // 1. Random content from reelgood (reelgood uses "show", cinemeta uses "series")
  let reelgood_kind = case content_kind {
    "series" -> "show"
    other -> other
  }
  use content <- result.try(
    reelgood.get_random_content(80, reelgood_kind)
    |> result.map_error(errors.ReelgoodErr),
  )

  // 2. Search cinemeta for IMDB ID
  echo "[hero] searching: " <> content.title
  let search_fn = case content_kind {
    "series" -> cinemeta.search_series
    _ -> cinemeta.search
  }
  use search_result <- result.try(
    search_fn(content.title)
    |> result.map_error(errors.CinemetaErr),
  )

  // 3. Full metadata
  let media_type = case content_kind {
    "movie" -> cinemeta_models.MovieType
    _ -> cinemeta_models.SeriesType
  }

  use meta <- result.try(
    case media_type {
      cinemeta_models.MovieType ->
        cinemeta.get_movie(search_result.imdb_id)
      cinemeta_models.SeriesType ->
        cinemeta.get_series(search_result.imdb_id)
    }
    |> result.map_error(errors.CinemetaErr),
  )

  echo "[hero] got meta: " <> meta.name <> " (" <> meta.imdb_id <> ")"

  // 4. Try fanart, fall back to cinemeta/metahub (same as fetch_home)
  let art = fanart.get_best_art(media_type, meta.imdb_id, meta.tvdb_id)
  let metahub_bg =
    "https://images.metahub.space/background/large/"
    <> meta.imdb_id
    <> "/img"

  let #(background, logo, poster) = case art {
    Ok(a) -> {
      // Background: fanart > metahub
      let bg = case a.background {
        "" -> metahub_bg
        url -> url
      }
      // Logo: fanart (validated) > cinemeta
      let lg = case a.logo {
        "" -> meta.logo
        url ->
          case cache.fetch_bytes(url) {
            Ok(_) -> url
            Error(_) -> meta.logo
          }
      }
      #(bg, lg, a.poster)
    }
    Error(_) -> {
      // No fanart at all — metahub bg, cinemeta logo
      #(metahub_bg, meta.logo, "")
    }
  }

  // 5. Cache ALL images
  let background = cache_image(background)
  let logo = cache_image(logo)
  let poster = cache_image(poster)

  // 6. Build hero with year fallback
  let year = extract_year(meta.year, content.released_on)
  let genres = string.join(meta.genres, ", ")

  let hero =
    HeroContent(
      id: meta.imdb_id,
      imdb_id: meta.imdb_id,
      name: meta.name,
      description: meta.description,
      year: year,
      imdb_rating: meta.imdb_rating,
      genres: genres,
      media_type: content_kind,
      background: background,
      logo: logo,
      poster: poster,
    )

  // 7. Reject if ANY field is empty
  validate_hero(hero)
}

/// Cache an image URL, return the URL if successful, "" if not
fn cache_image(url: String) -> String {
  case url {
    "" -> ""
    u ->
      case cache.fetch_bytes(u) {
        Ok(_) -> u
        Error(_) -> ""
      }
  }
}

/// Extract starting year from cinemeta ("2015-2022" -> "2015", "2021-" -> "2021")
/// Falls back to reelgood released_on ("2012-12-12T00:00:00" -> "2012")
fn extract_year(cinemeta_year: String, reelgood_released_on: String) -> String {
  let year = case string.split(cinemeta_year, "–") {
    [first, ..] -> string.trim(first)
    _ -> ""
  }
  // Also try splitting on regular hyphen
  let year = case year {
    "" ->
      case string.split(cinemeta_year, "-") {
        [first, ..] -> string.trim(first)
        _ -> ""
      }
    y -> y
  }
  case year {
    "" -> string.slice(reelgood_released_on, 0, 4)
    y -> y
  }
}

/// Reject hero if any field is empty
fn validate_hero(
  hero: HeroContent,
) -> Result(HeroContent, errors.HeroError) {
  case hero {
    _ if hero.name == "" ->
      Error(errors.MissingData(hero.imdb_id <> ": no name"))
    _ if hero.description == "" ->
      Error(errors.MissingData(hero.imdb_id <> ": no description"))
    _ if hero.year == "" ->
      Error(errors.MissingData(hero.name <> ": no year"))
    _ if hero.imdb_rating == "" ->
      Error(errors.MissingData(hero.name <> ": no rating"))
    _ if hero.genres == "" ->
      Error(errors.MissingData(hero.name <> ": no genres"))
    _ if hero.background == "" ->
      Error(errors.NoImages(hero.name <> ": no background"))
    _ if hero.logo == "" ->
      Error(errors.NoImages(hero.name <> ": no logo"))
    _ if hero.poster == "" ->
      Error(errors.NoImages(hero.name <> ": no poster"))
    _ -> Ok(hero)
  }
}
