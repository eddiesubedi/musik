import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{type Attribute, attribute as attr}

const proxy = "http://68.67.86.21:6969/insecure/"

/// Build a proxied URL with optional width.
pub fn url(source: String, options: String) -> String {
  proxy <> options <> "plain/" <> source
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
