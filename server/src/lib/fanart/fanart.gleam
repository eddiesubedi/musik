import envoy
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import lib/cache
import lib/cinemeta/models.{MovieType, SeriesType, type MediaType}

// --- Types ---

pub type Art {
  Art(id: String, lang: String, likes: Int, url: String)
}

pub type FanArt {
  FanArt(
    name: String,
    logos: List(Art),
    backgrounds: List(Art),
    posters: List(Art),
  )
}

pub type BestArt {
  BestArt(logo: String, background: String, poster: String)
}

// --- Public API ---

pub fn get_art(
  media_type: MediaType,
  imdb_id: String,
  tvdb_id: String,
) -> Result(FanArt, Nil) {
  let assert Ok(api_key) = envoy.get("FANART_API_KEY")

  case media_type {
    MovieType -> {
      let url =
        "https://webservice.fanart.tv/v3/movies/"
        <> imdb_id
        <> "?api_key="
        <> api_key
      fetch_and_decode(url, movie_decoder())
    }
    SeriesType -> {
      let id = case tvdb_id {
        "" -> imdb_id
        id -> id
      }
      let url =
        "https://webservice.fanart.tv/v3/tv/"
        <> id
        <> "?api_key="
        <> api_key
      fetch_and_decode(url, tv_decoder())
    }
  }
}

/// Get the best logo and background, sorted by likes.
/// Also pre-caches the actual image files via postgres http_cache.
pub fn get_best_art(
  media_type: MediaType,
  imdb_id: String,
  tvdb_id: String,
) -> Result(BestArt, Nil) {
  use art <- result.try(get_art(media_type, imdb_id, tvdb_id))

  let best_logo = best_by_likes(art.logos)
  let best_bg = best_by_likes(art.backgrounds)
  let best_poster = best_by_likes(art.posters)

  // Pre-cache the actual images
  pre_cache(best_logo)
  pre_cache(best_bg)
  pre_cache(best_poster)

  Ok(BestArt(logo: best_logo, background: best_bg, poster: best_poster))
}

// --- Internal ---

fn fetch_and_decode(
  url: String,
  decoder: decode.Decoder(FanArt),
) -> Result(FanArt, Nil) {
  cache.fetch(url)
  |> result.try(fn(body) {
    json.parse(body, decoder)
    |> result.replace_error(Nil)
  })
}

fn best_by_likes(items: List(Art)) -> String {
  let english =
    items
    |> list.filter(fn(a) { a.lang == "en" || a.lang == "" })

  // Prefer English, fall back to all if none found
  let candidates = case english {
    [] -> items
    _ -> english
  }

  candidates
  |> list.sort(fn(a, b) { int.compare(b.likes, a.likes) })
  |> list.first
  |> result.map(fn(a) { a.url })
  |> result.unwrap("")
}

fn pre_cache(url: String) -> Nil {
  case url {
    "" -> Nil
    u -> {
      let _ = cache.fetch_bytes(u)
      Nil
    }
  }
}

// --- Decoders ---

fn movie_decoder() -> decode.Decoder(FanArt) {
  use name <- decode.optional_field("name", "", decode.string)
  use logos <- decode.optional_field(
    "hdmovielogo",
    [],
    decode.list(art_decoder()),
  )
  use backgrounds <- decode.optional_field(
    "moviebackground",
    [],
    decode.list(art_decoder()),
  )
  use posters <- decode.optional_field(
    "movieposter",
    [],
    decode.list(art_decoder()),
  )
  decode.success(FanArt(name:, logos:, backgrounds:, posters:))
}

fn tv_decoder() -> decode.Decoder(FanArt) {
  use name <- decode.optional_field("name", "", decode.string)
  use logos <- decode.optional_field(
    "hdtvlogo",
    [],
    decode.list(art_decoder()),
  )
  use backgrounds <- decode.optional_field(
    "showbackground",
    [],
    decode.list(art_decoder()),
  )
  use posters <- decode.optional_field(
    "tvposter",
    [],
    decode.list(art_decoder()),
  )
  decode.success(FanArt(name:, logos:, backgrounds:, posters:))
}

fn art_decoder() -> decode.Decoder(Art) {
  use id <- decode.optional_field("id", "", decode.string)
  use lang <- decode.optional_field("lang", "", decode.string)
  use likes_str <- decode.optional_field("likes", "0", decode.string)
  use url <- decode.optional_field("url", "", decode.string)
  let likes = int.parse(likes_str) |> result.unwrap(0)
  decode.success(Art(id:, lang:, likes:, url:))
}
