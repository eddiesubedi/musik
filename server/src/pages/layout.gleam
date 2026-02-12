import dev/reload
import gleam/bytes_tree
import gleam/http/response.{type Response}
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html.{html}
import mist.{type ResponseData}

/// Render a full HTML page with the common shell.
/// Each page only provides its title and body content.
pub fn render(
  title page_title: String,
  head head_extra: List(Element(Nil)),
  body body_children: List(Element(Nil)),
) -> Response(ResponseData) {
  let head_children = [
    html.meta([attribute.charset("utf-8")]),
    html.meta([
      attribute.content("width=device-width, initial-scale=1"),
      attribute.name("viewport"),
    ]),
    html.title([], page_title),
    html.script([attribute.src("/client.js"), attribute.type_("module")], ""),
    html.script(
      [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
      "",
    ),
    ..head_extra
  ]

  let page =
    html([], [
      html.head([], head_children),
      html.body(
        [
          attribute.styles([
            #("max-width", "40rem"),
            #("margin", "2rem auto"),
            #("font-family", "sans-serif"),
          ]),
        ],
        list.append(body_children, [
          html.script([], reload.script()),
        ]),
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}
