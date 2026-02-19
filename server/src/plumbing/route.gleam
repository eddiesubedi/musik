import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import mist.{type Connection, type ResponseData}
import plumbing/context.{type Context}

// --- Types ---

pub type Handler =
  fn(Request(Connection), Context) -> Response(ResponseData)

pub type Route {
  Route(
    page: Handler,
    ws: List(#(String, Handler)),
    api: List(#(String, Handler)),
  )
}

// --- Builder API ---

pub fn new(handler: Handler) -> Route {
  Route(page: handler, ws: [], api: [])
}

pub fn with_ws(route: Route, name: String, handler: Handler) -> Route {
  Route(..route, ws: [#(name, handler), ..route.ws])
}

pub fn with_api(route: Route, name: String, handler: Handler) -> Route {
  Route(..route, api: [#(name, handler), ..route.api])
}

// --- Dispatcher ---

pub fn dispatch(
  req: Request(Connection),
  ctx: Context,
  segments: List(String),
  routes: List(#(String, Route)),
) -> Response(ResponseData) {
  case segments {
    [path] ->
      case list.key_find(routes, path) {
        Ok(route) -> route.page(req, ctx)
        Error(_) -> not_found()
      }

    [] ->
      case list.key_find(routes, "") {
        Ok(route) -> route.page(req, ctx)
        Error(_) -> not_found()
      }

    ["ws", name] -> find_ws(req, ctx, name, routes)
    ["api", name] -> find_api(req, ctx, name, routes)
    _ -> not_found()
  }
}

fn find_ws(
  req: Request(Connection),
  ctx: Context,
  name: String,
  routes: List(#(String, Route)),
) -> Response(ResponseData) {
  case routes {
    [] -> not_found()
    [#(_, route), ..rest] ->
      case list.key_find(route.ws, name) {
        Ok(handler) -> handler(req, ctx)
        Error(_) -> find_ws(req, ctx, name, rest)
      }
  }
}

fn find_api(
  req: Request(Connection),
  ctx: Context,
  name: String,
  routes: List(#(String, Route)),
) -> Response(ResponseData) {
  case routes {
    [] -> not_found()
    [#(_, route), ..rest] ->
      case list.key_find(route.api, name) {
        Ok(handler) -> handler(req, ctx)
        Error(_) -> find_api(req, ctx, name, rest)
      }
  }
}

fn not_found() -> Response(ResponseData) {
  response.new(404)
  |> response.set_body(mist.Bytes(bytes_tree.new()))
}
