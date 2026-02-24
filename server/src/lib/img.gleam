import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{type Attribute, attribute as attr}
import mist.{type Connection, type ResponseData}
import pog
import plumbing/sql

@external(erlang, "persistent_term", "put")
fn pt_put(key: String, value: String) -> Nil

@external(erlang, "persistent_term", "get")
fn pt_get(key: String) -> String

const pt_key = "imgproxy_url"

const pt_server_key = "server_url"

/// Store the imgproxy base URL. Call once at startup.
pub fn init(imgproxy_url: String) -> Nil {
  pt_put(pt_key, imgproxy_url)
}

/// Store the server's own URL (e.g. "http://192.168.x.x:3000"). Call once at startup.
pub fn init_server_url(server_url: String) -> Nil {
  pt_put(pt_server_key, server_url)
}

fn proxy() -> String {
  pt_get(pt_key)
}

pub fn server_url() -> String {
  pt_get(pt_server_key)
}

/// Build a proxied URL with optional width.
pub fn url(source: String, options: String) -> String {
  proxy() <> options <> "plain/" <> source
}

/// Generate `src` and `srcset` attributes for responsive images.
/// Pass the raw source URL and a list of widths (e.g. [640, 1280, 1920]).
pub fn srcset(
  source: String,
  widths: List(Int),
  options: String,
) -> List(Attribute(a)) {
  let default_width = case list.last(widths) {
    Ok(w) -> w
    Error(_) -> 1280
  }

  let src = url(source, options <> "w:" <> int.to_string(default_width) <> "/")

  let srcset_value =
    widths
    |> list.map(fn(w) {
      url(source, options <> "w:" <> int.to_string(w) <> "/")
      <> " "
      <> int.to_string(w)
      <> "w"
    })
    |> string.join(", ")

  [attribute.src(src), attr("srcset", srcset_value), attr("sizes", "100vw")]
}

/// Wrap an external URL so it's served from the local DB cache.
pub fn cached(original_url: String) -> String {
  server_url() <> "/cached-img/" <> original_url
}

/// Serve a cached image from http_cache by extracting the URL from the request path.
pub fn serve_cached(
  req: Request(Connection),
  db: pog.Connection,
) -> Response(ResponseData) {
  let url = string.drop_start(req.path, string.length("/cached-img/"))

  case url {
    "" ->
      response.new(400)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("missing url")),
      )
    _ ->
      case sql.get_cached_image(db, url) {
        Ok(pog.Returned(_, [row])) ->
          response.new(200)
          |> response.set_header("content-type", row.content_type)
          |> response.set_header("cache-control", "public, max-age=86400")
          |> response.set_body(mist.Bytes(bytes_tree.from_bit_array(row.body)))
        _ ->
          response.new(404)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("not found")),
          )
      }
  }
}
