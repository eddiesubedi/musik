import gleam/dynamic/decode
import gleam/int
import gleam/option.{type Option}

/// Accepts both JSON ints and floats, returns Float
fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, or: [decode.map(decode.int, int.to_float)])
}

/// Accepts a string or null, returns "" for null
fn nullable_string() -> decode.Decoder(String) {
  decode.one_of(decode.string, or: [decode.success("")])
}

pub type Series {
  Series(meta: Meta)
}

pub type Movie {
  Movie(meta: Meta)
}

pub type MediaType {
  SeriesType
  MovieType
}

pub type Meta {
  Meta(
    name: String,
    description: String,
    genres: List(String),
    year: String,
    imdb_rating: String,
    background: String,
    logo: String,
    imdb_id: String,
    tvdb_id: String,
    media_type: MediaType,
    trailers: List(Trailers),
  )
}

// --- Decoders ---

pub fn series_decoder() -> decode.Decoder(Series) {
  use meta <- decode.field("meta", meta_decoder())
  decode.success(Series(meta:))
}

pub fn movie_decoder() -> decode.Decoder(Movie) {
  use meta <- decode.field("meta", movie_meta_decoder())
  decode.success(Movie(meta:))
}

fn meta_decoder() -> decode.Decoder(Meta) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use genres <- decode.optional_field("genres", [], decode.list(decode.string))
  use year <- decode.optional_field("year", "", decode.string)
  use imdb_rating <- decode.optional_field("imdbRating", "", decode.string)
  use background <- decode.optional_field("background", "", decode.string)
  use logo <- decode.optional_field("logo", "", decode.string)
  use imdb_id <- decode.optional_field("imdb_id", "", decode.string)
  use tvdb_id <- decode.optional_field(
    "tvdb_id",
    "",
    decode.one_of(decode.string, or: [
      decode.map(decode.int, int.to_string),
    ]),
  )
  use trailers <- decode.optional_field(
    "trailers",
    [],
    decode.one_of(decode.list(trailers_decoder()), or: [decode.success([])]),
  )
  decode.success(Meta(
    name:,
    description:,
    genres:,
    year:,
    imdb_rating:,
    background:,
    logo:,
    imdb_id:,
    tvdb_id:,
    media_type: SeriesType,
    trailers:,
  ))
}

fn movie_meta_decoder() -> decode.Decoder(Meta) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use genres <- decode.optional_field("genres", [], decode.list(decode.string))
  use year <- decode.optional_field("releaseInfo", "", decode.string)
  use imdb_rating <- decode.optional_field("imdbRating", "", decode.string)
  use background <- decode.optional_field("background", "", decode.string)
  use logo <- decode.optional_field("logo", "", decode.string)
  use imdb_id <- decode.optional_field("imdb_id", "", decode.string)
  use trailers <- decode.optional_field(
    "trailers",
    [],
    decode.one_of(decode.list(trailers_decoder()), or: [decode.success([])]),
  )
  decode.success(Meta(
    name:,
    description:,
    genres:,
    year:,
    imdb_rating:,
    background:,
    logo:,
    imdb_id:,
    tvdb_id: "",
    media_type: MovieType,
    trailers:,
  ))
}

// --- Search (lightweight) ---

pub type SearchHit {
  SearchHit(imdb_id: String, name: String)
}

pub type SearchResult {
  SearchResult(metas: List(SearchHit))
}

// --- Types ---

pub type Search {
  Search(query: String, rank: Float, cache_max_age: Int, metas: List(Metas))
}

pub type Metas {
  Metas(
    id: String,
    imdb_id: String,
    type_: String,
    name: String,
    poster: String,
    background: String,
    release_info: String,
    links: List(Links),
    behavior_hints: BehaviorHints,
    awards: String,
    cast: List(String),
    description: String,
    director: List(String),
    dvd_release: String,
    genre: List(String),
    imdb_rating: String,
    popularity: Float,
    released: String,
    runtime: String,
    trailers: List(Trailers),
    writer: List(String),
    year: String,
    popularities: Option(Popularities),
    logo: String,
    slug: String,
    score: Float,
    genres: List(String),
    trailer_streams: List(TrailerStreams),
  )
}

pub type BehaviorHints {
  BehaviorHints(default_video_id: String, has_scheduled_videos: Bool)
}

pub type Trailers {
  Trailers(source: String, type_: String)
}

pub type Popularities {
  Popularities(moviedb: Float, stremio: Float, stremio_lib: Float, trakt: Float)
}

pub type Links {
  Links(name: String, category: String, url: String)
}

pub type TrailerStreams {
  TrailerStreams(title: String, yt_id: String)
}

// --- Decoders ---

pub fn search_hit_decoder() -> decode.Decoder(SearchResult) {
  use metas <- decode.field(
    "metas",
    decode.list({
      use imdb_id <- decode.field("imdb_id", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(SearchHit(imdb_id:, name:))
    }),
  )
  decode.success(SearchResult(metas:))
}

pub fn search_decoder() -> decode.Decoder(Search) {
  use query <- decode.field("query", decode.string)
  use rank <- decode.field("rank", number())
  use cache_max_age <- decode.field("cacheMaxAge", decode.int)
  use metas <- decode.field("metas", decode.list(metas_decoder()))
  decode.success(Search(query:, rank:, cache_max_age:, metas:))
}

pub fn metas_decoder() -> decode.Decoder(Metas) {
  use id <- decode.field("id", decode.string)
  use imdb_id <- decode.field("imdb_id", decode.string)
  use type_ <- decode.field("type", decode.string)
  use name <- decode.field("name", decode.string)
  use poster <- decode.field("poster", decode.string)
  use background <- decode.field("background", decode.string)
  use release_info <- decode.optional_field("releaseInfo", "", nullable_string())
  use links <- decode.optional_field("links", [], decode.list(links_decoder()))
  use behavior_hints <- decode.field("behaviorHints", behavior_hints_decoder())
  use awards <- decode.optional_field("awards", "", nullable_string())
  use cast <- decode.optional_field("cast", [], decode.one_of(decode.list(decode.string), or: [decode.success([])]))
  use description <- decode.optional_field("description", "", nullable_string())
  use director <- decode.optional_field(
    "director",
    [],
    decode.one_of(decode.list(decode.string), or: [decode.success([])]),
  )
  use dvd_release <- decode.optional_field("dvdRelease", "", nullable_string())
  use genre <- decode.optional_field("genre", [], decode.one_of(decode.list(decode.string), or: [decode.success([])]))
  use imdb_rating <- decode.optional_field("imdbRating", "", nullable_string())
  use popularity <- decode.optional_field("popularity", 0.0, number())
  use released <- decode.optional_field("released", "", nullable_string())
  use runtime <- decode.optional_field("runtime", "", nullable_string())
  use trailers <- decode.optional_field(
    "trailers",
    [],
    decode.one_of(decode.list(trailers_decoder()), or: [decode.success([])]),
  )
  use writer <- decode.optional_field(
    "writer",
    [],
    decode.one_of(decode.list(decode.string), or: [decode.success([])]),
  )
  use year <- decode.optional_field("year", "", nullable_string())
  use popularities <- decode.optional_field(
    "popularities",
    option.None,
    decode.optional(popularities_decoder()),
  )
  use logo <- decode.optional_field("logo", "", nullable_string())
  use slug <- decode.optional_field("slug", "", nullable_string())
  use score <- decode.optional_field("score", 0.0, number())
  use genres <- decode.optional_field("genres", [], decode.list(decode.string))
  use trailer_streams <- decode.optional_field(
    "trailerStreams",
    [],
    decode.list(trailer_streams_decoder()),
  )
  decode.success(Metas(
    id:,
    imdb_id:,
    type_:,
    name:,
    poster:,
    background:,
    release_info:,
    links:,
    behavior_hints:,
    awards:,
    cast:,
    description:,
    director:,
    dvd_release:,
    genre:,
    imdb_rating:,
    popularity:,
    released:,
    runtime:,
    trailers:,
    writer:,
    year:,
    popularities:,
    logo:,
    slug:,
    score:,
    genres:,
    trailer_streams:,
  ))
}

pub fn behavior_hints_decoder() -> decode.Decoder(BehaviorHints) {
  use default_video_id <- decode.field("defaultVideoId", nullable_string())
  use has_scheduled_videos <- decode.field("hasScheduledVideos", decode.bool)
  decode.success(BehaviorHints(default_video_id:, has_scheduled_videos:))
}

pub fn trailers_decoder() -> decode.Decoder(Trailers) {
  use source <- decode.field("source", decode.string)
  use type_ <- decode.field("type", decode.string)
  decode.success(Trailers(source:, type_:))
}

pub fn popularities_decoder() -> decode.Decoder(Popularities) {
  use moviedb <- decode.field("moviedb", number())
  use stremio <- decode.field("stremio", number())
  use stremio_lib <- decode.field("stremio_lib", number())
  use trakt <- decode.optional_field("trakt", 0.0, number())
  decode.success(Popularities(moviedb:, stremio:, stremio_lib:, trakt:))
}

pub fn links_decoder() -> decode.Decoder(Links) {
  use name <- decode.field("name", decode.string)
  use category <- decode.field("category", decode.string)
  use url <- decode.field("url", decode.string)
  decode.success(Links(name:, category:, url:))
}

pub fn trailer_streams_decoder() -> decode.Decoder(TrailerStreams) {
  use title <- decode.field("title", decode.string)
  use yt_id <- decode.field("ytId", decode.string)
  decode.success(TrailerStreams(title:, yt_id:))
}
