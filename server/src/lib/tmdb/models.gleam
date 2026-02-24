import gleam/dynamic/decode

// --- Types ---

pub type Trending {
  Trending(
    page: Int,
    results: List(Results),
    total_pages: Int,
    total_results: Int,
  )
}

pub type Results {
  Results(
    adult: Bool,
    backdrop_path: String,
    id: Int,
    title: String,
    original_title: String,
    overview: String,
    poster_path: String,
    media_type: String,
    original_language: String,
    genre_ids: List(Int),
    popularity: Float,
    release_date: String,
    video: Bool,
    vote_average: Float,
    vote_count: Int,
    name: String,
    original_name: String,
    first_air_date: String,
    origin_country: List(String),
  )
}

// --- Decoders ---

pub fn trending_decoder() -> decode.Decoder(Trending) {
  use page <- decode.field("page", decode.int)
  use results <- decode.field("results", decode.list(results_decoder()))
  use total_pages <- decode.field("total_pages", decode.int)
  use total_results <- decode.field("total_results", decode.int)
  decode.success(Trending(page:, results:, total_pages:, total_results:))
}

pub fn results_decoder() -> decode.Decoder(Results) {
  use adult <- decode.field("adult", decode.bool)
  use backdrop_path <- decode.field("backdrop_path", decode.string)
  use id <- decode.field("id", decode.int)
  use title <- decode.optional_field("title", "", decode.string)
  use original_title <- decode.optional_field(
    "original_title",
    "",
    decode.string,
  )
  use overview <- decode.field("overview", decode.string)
  use poster_path <- decode.field("poster_path", decode.string)
  use media_type <- decode.field("media_type", decode.string)
  use original_language <- decode.field("original_language", decode.string)
  use genre_ids <- decode.field("genre_ids", decode.list(decode.int))
  use popularity <- decode.field("popularity", decode.float)
  use release_date <- decode.optional_field("release_date", "", decode.string)
  use video <- decode.optional_field("video", False, decode.bool)
  use vote_average <- decode.field("vote_average", decode.float)
  use vote_count <- decode.field("vote_count", decode.int)
  use name <- decode.optional_field("name", "", decode.string)
  use original_name <- decode.optional_field("original_name", "", decode.string)
  use first_air_date <- decode.optional_field(
    "first_air_date",
    "",
    decode.string,
  )
  use origin_country <- decode.optional_field(
    "origin_country",
    [],
    decode.list(decode.string),
  )
  decode.success(Results(
    adult:,
    backdrop_path:,
    id:,
    title:,
    original_title:,
    overview:,
    poster_path:,
    media_type:,
    original_language:,
    genre_ids:,
    popularity:,
    release_date:,
    video:,
    vote_average:,
    vote_count:,
    name:,
    original_name:,
    first_air_date:,
    origin_country:,
  ))
}
