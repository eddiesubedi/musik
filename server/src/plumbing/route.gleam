import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import mist.{type Connection, type ResponseData}

// --- Types ---

pub type Handler =
  fn(Request(Connection)) -> Response(ResponseData)

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
  segments: List(String),
  routes: List(#(String, Route)),
) -> Response(ResponseData) {
  case segments {
    // Page route: match path to route name
    [path] ->
      case list.key_find(routes, path) {
        Ok(route) -> route.page(req)
        Error(_) -> not_found()
      }

    // Root page: match empty path to "" route
    [] ->
      case list.key_find(routes, "") {
        Ok(route) -> route.page(req)
        Error(_) -> not_found()
      }

    // WebSocket: /ws/<name>
    ["ws", name] -> find_ws(req, name, routes)

    // API: /api/<name>
    ["api", name] -> find_api(req, name, routes)

    _ -> not_found()
  }
}

fn find_ws(
  req: Request(Connection),
  name: String,
  routes: List(#(String, Route)),
) -> Response(ResponseData) {
  case routes {
    [] -> not_found()
    [#(_, route), ..rest] ->
      case list.key_find(route.ws, name) {
        Ok(handler) -> handler(req)
        Error(_) -> find_ws(req, name, rest)
      }
  }
}

fn find_api(
  req: Request(Connection),
  name: String,
  routes: List(#(String, Route)),
) -> Response(ResponseData) {
  case routes {
    [] -> not_found()
    [#(_, route), ..rest] ->
      case list.key_find(route.api, name) {
        Ok(handler) -> handler(req)
        Error(_) -> find_api(req, name, rest)
      }
  }
}

fn not_found() -> Response(ResponseData) {
  response.new(404)
  |> response.set_body(mist.Bytes(bytes_tree.new()))
}
