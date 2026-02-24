import components/homepage
import components/homepage/model
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import lustre/server_component
import mist.{type Connection, type ResponseData}
import pages/layout
import plumbing/context.{type Context}
import plumbing/route
import plumbing/ws

pub fn routes() -> route.Route {
  route.new(page)
  |> route.with_ws("rate", ws_handler)
}

/// GET / — the home page
pub fn page(_req: Request(Connection), _ctx: Context) -> Response(ResponseData) {
  layout.render(title: "Anime Tracker", head: [], body: [
    server_component.element(
      [
        server_component.route("/ws/rate"),
      ],
      [],
    ),
  ])
}

/// WS /ws/rate — the rating server component
pub fn ws_handler(
  req: Request(Connection),
  ctx: Context,
) -> Response(ResponseData) {
  io.println("[ws] new connection for: " <> ctx.user.name)
  let flags = model.Flags(name: ctx.user.name, email: ctx.user.email, db: ctx.db)
  ws.serve(req, homepage.component(), flags)
}
