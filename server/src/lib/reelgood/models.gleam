import gleam/dynamic/decode
import gleam/int
import gleam/option.{type Option}

// --- Types ---

// --- Types ---

pub type RandomContent {
  RandomContent(
    id: String,
    slug: String,
    title: String,
    overview: String,
    tagline: Option(String),
    classification: Option(String),
    runtime: Int,
    released_on: String,
    has_poster: Bool,
    poster_blur: String,
    has_backdrop: Bool,
    backdrop_blur: Option(String),
    imdb_rating: Option(String),
    rt_critics_rating: Option(String),
    reelgood_score: Option(String),
    genres: List(Int),
    tracking: Bool,
    watchlisted: Bool,
    seen: Bool,
    season_count: Int,
    content_type: String,
    sources: List(String),
    meta: Option(String),
  )
}

// --- Decoders ---

pub fn random_content_decoder() -> decode.Decoder(RandomContent) {
  use id <- decode.field("id", decode.string)
  use slug <- decode.field("slug", decode.string)
  use title <- decode.field("title", decode.string)
  use overview <- decode.field("overview", decode.string)
  use tagline <- decode.field("tagline", decode.optional(decode.string))
  use classification <- decode.field(
    "classification",
    decode.optional(decode.string),
  )
  use runtime <- decode.field("runtime", decode.int)
  use released_on <- decode.field(
    "released_on",
    decode.one_of(decode.string, or: [decode.success("")]),
  )
  use has_poster <- decode.field("has_poster", decode.bool)
  use poster_blur <- decode.field("poster_blur", decode.string)
  use has_backdrop <- decode.field("has_backdrop", decode.bool)
  use backdrop_blur <- decode.field(
    "backdrop_blur",
    decode.optional(decode.string),
  )
  use imdb_rating <- decode.field("imdb_rating", decode.optional(decode.string))
  use rt_critics_rating <- decode.field(
    "rt_critics_rating",
    decode.optional(
      decode.one_of(decode.string, or: [
        decode.map(decode.int, int.to_string),
      ]),
    ),
  )
  use reelgood_score <- decode.field(
    "reelgood_score",
    decode.optional(decode.string),
  )
  use genres <- decode.field("genres", decode.list(decode.int))
  use tracking <- decode.field("tracking", decode.bool)
  use watchlisted <- decode.field("watchlisted", decode.bool)
  use seen <- decode.field("seen", decode.bool)
  use season_count <- decode.field("season_count", decode.int)
  use content_type <- decode.field("content_type", decode.string)
  use sources <- decode.field("sources", decode.list(decode.string))
  use meta <- decode.field("meta", decode.optional(decode.string))
  decode.success(RandomContent(
    id:,
    slug:,
    title:,
    overview:,
    tagline:,
    classification:,
    runtime:,
    released_on:,
    has_poster:,
    poster_blur:,
    has_backdrop:,
    backdrop_blur:,
    imdb_rating:,
    rt_critics_rating:,
    reelgood_score:,
    genres:,
    tracking:,
    watchlisted:,
    seen:,
    season_count:,
    content_type:,
    sources:,
    meta:,
  ))
}
