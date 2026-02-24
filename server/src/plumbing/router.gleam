import dev/reload
import gleam/bytes_tree
import gleam/erlang/application
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/option.{None}
import lib/img
import mist.{type Connection, type ResponseData}
import pages/home
import pog
import plumbing/auth
import plumbing/context.{Context, User}
import plumbing/route

pub fn handle(db: pog.Connection) {
  fn(req: Request(Connection)) -> Response(ResponseData) {
    let segments = request.path_segments(req)
    case segments {
      // -- Cached images (public, used by imgproxy) --
      ["cached-img", ..] -> img.serve_cached(req, db)

      // -- Auth (public) --
      ["auth", "login"] -> auth.login(req)
      ["auth", "callback"] -> auth.callback(req, db)
      ["auth", "logout"] -> auth.logout(req, db)

      // -- Dev --
      ["dev", "reload"] -> reload.serve(req)

      // -- Protected routes --
      _ ->
        case auth.get_user(req, db) {
          Ok(#(name, email)) -> {
            let ctx = Context(db:, user: User(name:, email:))
            case segments {
              // -- Static assets --
              ["client.js"] -> serve_client_js()
              ["output.css"] -> serve_output_css()
              ["lustre", "runtime.mjs"] -> serve_lustre_runtime()

              // -- Pages / WS / API --
              _ ->
                route.dispatch(req, ctx, segments, [
                  #("", home.routes()),
                ])
            }
          }
          Error(_) -> auth.redirect_to_login()
        }
    }
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

fn serve_output_css() -> Response(ResponseData) {
  case mist.send_file("priv/static/output.css", offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", "text/css")
      |> response.set_body(file)
    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("output.css not found")))
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
