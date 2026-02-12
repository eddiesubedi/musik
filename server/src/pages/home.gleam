import components/raiting
import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import lustre/attribute
import lustre/element/html
import lustre/server_component
import mist.{type Connection, type ResponseData}
import pages/layout
import plumbing/route
import plumbing/ws
import shared.{Anime}

pub fn routes() -> route.Route {
  route.new(page)
  |> route.with_ws("rate", ws)
  |> route.with_api("anime", api)
}

/// GET / — the home page
pub fn page(_req: Request(Connection)) -> Response(ResponseData) {
  let anime_list = get_anime_from_db()

  layout.render(title: "Anime Tracker", head: [], body: [
    html.script(
      [attribute.id("model"), attribute.type_("application/json")],
      json.to_string(shared.anime_list_to_json(anime_list)),
    ),
    html.div([attribute.id("app")], []),
    html.hr([]),
    html.h2([], [html.text("Rate this anime")]),
    server_component.element(
      [
        server_component.route("/ws/rate"),
        raiting.value(5),
      ],
      [],
    ),
  ])
}

/// WS /ws/rate — the rating server component
pub fn ws(req: Request(Connection)) -> Response(ResponseData) {
  ws.serve(req, raiting.component())
}

/// GET /api/anime — JSON endpoint
pub fn api(_req: Request(Connection)) -> Response(ResponseData) {
  let body =
    get_anime_from_db()
    |> shared.anime_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
}

fn get_anime_from_db() {
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Cowboy Bebop", episodes: 69),
    Anime(id: 3, title: "Cowboy Bebop", episodes: 420),
  ]
}
