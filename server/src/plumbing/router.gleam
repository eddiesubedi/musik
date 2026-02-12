import dev/reload
import gleam/bytes_tree
import gleam/erlang/application
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/option.{None}
import mist.{type Connection, type ResponseData}
import pages/home
import plumbing/route

pub fn handle(req: Request(Connection)) -> Response(ResponseData) {
  let segments = request.path_segments(req)
  case segments {
    // -- Dev --
    ["dev", "reload"] -> reload.serve(req)

    // -- Static assets --
    ["client.js"] -> serve_client_js()
    ["lustre", "runtime.mjs"] -> serve_lustre_runtime()

    // -- Pages / WS / API --
    _ ->
      route.dispatch(req, segments, [
        #("", home.routes()),
      ])
  }
}

fn serve_client_js() -> Response(ResponseData) {
  case mist.send_file("priv/static/client.js", offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(_) ->
      response.new(404)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string(
          "client.js not found. Run: cd client && gleam run -m lustre/dev build --outdir=../server/priv/static",
        )),
      )
  }
}

fn serve_lustre_runtime() -> Response(ResponseData) {
  let assert Ok(lustre_priv) = application.priv_directory("lustre")
  let path = lustre_priv <> "/static/lustre-server-component.mjs"
  case mist.send_file(path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.prepend_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}
