import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import lib/cache
import lib/cinemeta/errors.{type CinemetaErrors, NetworkError, ParseError}
import lib/cinemeta/imdb_ids
import lib/cinemeta/models.{type Meta}

const base_url = "https://v3-cinemeta.strem.io"

pub fn get_random() -> Result(Meta, CinemetaErrors) {
  let ids = imdb_ids.imdb_ids
  let index = int.random(list.length(ids))
  let assert Ok(id) = ids |> list.drop(index) |> list.first
  case get_series(id) {
    Ok(meta) -> Ok(meta)
    Error(_) -> get_movie(id)
  }
}

pub fn get_series(imdb_id: String) -> Result(Meta, CinemetaErrors) {
  let url = "https://v3-cinemeta.strem.io/meta/series/" <> imdb_id <> ".json"

  cache.fetch(url)
  |> result.replace_error(NetworkError)
  |> result.try(fn(body) {
    let parsed = json.parse(body, models.series_decoder())
    case parsed {
      Error(e) -> {
        echo "[get_series] parse error for " <> imdb_id <> ":"
        echo e
        Error(ParseError)
      }
      Ok(series) -> Ok(series.meta)
    }
  })
}

pub fn get_movie(imdb_id: String) -> Result(Meta, CinemetaErrors) {
  let url = base_url <> "/meta/movie/" <> imdb_id <> ".json"

  cache.fetch(url)
  |> result.replace_error(NetworkError)
  |> result.try(fn(body) {
    json.parse(body, models.movie_decoder())
    |> result.replace_error(ParseError)
  })
  |> result.map(fn(movie) { movie.meta })
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

pub fn search(title: String) -> Result(models.SearchHit, CinemetaErrors) {
  search_by_type(title, "movie")
}

pub fn search_series(title: String) -> Result(models.SearchHit, CinemetaErrors) {
  search_by_type(title, "series")
}

fn search_by_type(
  title: String,
  content_type: String,
) -> Result(models.SearchHit, CinemetaErrors) {
  let url =
    base_url
    <> "/catalog/"
    <> content_type
    <> "/top/search="
    <> uri.percent_encode(title)
    <> ".json"
  let assert Ok(req) = request.to(url)
  httpc.send(req)
  |> result.replace_error(NetworkError)
  |> result.try(fn(res) {
    json.parse(res.body, models.search_hit_decoder())
    |> result.replace_error(ParseError)
    |> result.try(fn(search_result) {
      list.first(search_result.metas)
      |> result.replace_error(ParseError)
    })
  })
}
