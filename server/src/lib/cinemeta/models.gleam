import gleam/dynamic/decode

pub type Series {
  Series(meta: Meta)
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
  )
}

// --- Decoders ---

pub fn series_decoder() -> decode.Decoder(Series) {
  use meta <- decode.field("meta", meta_decoder())
  decode.success(Series(meta:))
}

fn meta_decoder() -> decode.Decoder(Meta) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use genres <- decode.optional_field("genres", [], decode.list(decode.string))
  use year <- decode.optional_field("year", "", decode.string)
  use imdb_rating <- decode.optional_field("imdbRating", "", decode.string)
  use background <- decode.optional_field("background", "", decode.string)
  use logo <- decode.optional_field("logo", "", decode.string)
  decode.success(Meta(
    name:,
    description:,
    genres:,
    year:,
    imdb_rating:,
    background:,
    logo:,
  ))
}
