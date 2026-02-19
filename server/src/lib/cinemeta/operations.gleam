import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lib/cache
import lib/cinemeta/errors.{type FetchError, NetworkError, ParseError}
import lib/cinemeta/imdb_ids
import lib/cinemeta/models.{type Meta}

pub fn get_random_series() -> Result(Meta, FetchError) {
  let ids = imdb_ids.imdb_ids
  let index = int.random(list.length(ids))
  let assert Ok(id) = ids |> list.drop(index) |> list.first
  get_series(id)
}

pub fn get_series(imdb_id: String) -> Result(Meta, FetchError) {
  let url = "https://v3-cinemeta.strem.io/meta/series/" <> imdb_id <> ".json"

  cache.fetch(url)
  |> result.replace_error(NetworkError)
  |> result.try(fn(body) {
    json.parse(body, models.series_decoder())
    |> result.replace_error(ParseError)
  })
  |> result.map(fn(series) { series.meta })
}

pub fn parse_year(year: String) -> Int {
  case year |> string.split("–") {
    [first, ..] ->
      case int.parse(first) {
        Ok(n) -> n
        Error(_) -> 0
      }
    _ -> 0
  }
}
