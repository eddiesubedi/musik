import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import lib/reelgood/errors.{type ReelgoodError, JsonDecodeError, RequestError}
import lib/reelgood/models.{type RandomContent}

// https://api.reelgood.com/v3.0/content/random?content_kind=movie&minimum_rg=80&nocache=true&region=us&sources=netflix,amazon_prime,hulu_plus,hbo_max,disney_plus,a%20%20pple_tv_plus,paramount_plus,peacock,starz,showtime,crunchyroll,tubi_tv,plutotv,roku_channel,mubi,criterion_channel,shudder,fubo_tv,kanopy,hoopla,cinemax,directv,amc_%20%20plus,philo&spin_count=0
const api_base = "https://api.reelgood.com/v3.0/content"

pub fn get_random_content(
  min_raiting: Int,
  content_kind: String,
) -> Result(RandomContent, ReelgoodError) {
  let url =
    api_base
    <> "/random?content_kind="
    <> content_kind
    <> "&minimum_rg="
    <> int.to_string(min_raiting)
    <> "&nocache=true&region=us&sources=netflix,amazon_prime,hulu_plus,hbo_max,disney_plus,a%20%20pple_tv_plus,paramount_plus,peacock,starz,showtime,crunchyroll,tubi_tv,plutotv,roku_channel,mubi,criterion_channel,shudder,fubo_tv,kanopy,hoopla,cinemax,directv,amc_%20%20plus,philo&spin_count=0"

  let assert Ok(req) = request.to(url)
  httpc.send(req)
  |> result.map_error(fn(error) { RequestError(error: string.inspect(error)) })
  |> result.try(fn(res) {
    json.parse(res.body, models.random_content_decoder())
    |> result.map_error(fn(error) {
      echo error
      error
    })
    |> result.replace_error(JsonDecodeError)
  })
}
