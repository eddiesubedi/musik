import envoy
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result
import gleam/string
import lib/tmdb/errors.{type TmdbError}
import lib/tmdb/models

const base_url = "https://api.themoviedb.org/3"

fn api_key() {
  let assert Ok(api_key) = envoy.get("TMDB_API_KEY")
  api_key
}

pub fn get_trending() -> Result(models.Trending, TmdbError) {
  let url = base_url <> "/trending/all/day?api_key=" <> api_key()
  echo url
  let assert Ok(req) = request.to(url)
  httpc.send(req)
  |> result.map_error(fn(error) {
    errors.RequestError(error: string.inspect(error))
  })
  |> result.try(fn(res) {
    json.parse(res.body, models.trending_decoder())
    |> result.map_error(fn(error) {
      echo error
      error
    })
    |> result.replace_error(errors.JsonDecodeError)
  })
}
