import dev_reload
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}
import raiting
import shared.{Anime}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["client.js"] -> serve_client_js()
        ["api", "anime"] -> serve_anime_api()
        ["dev", "reload"] -> dev_reload.serve(req)
        ["lustre", "runtime.mjs"] -> serve_lustre_runtime()
        ["ws", "rate"] -> serve_rating_ws(req)
        _ ->
          response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

fn serve_html() -> Response(ResponseData) {
  let anime_list = get_anime_from_db()

  let page =
    html([], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.content("width=device-width, initial-scale=1"),
          attribute.name("viewport"),
        ]),
        html.title([], "Anime Tracker"),
        html.script(
          [attribute.src("/client.js"), attribute.type_("module")],
          "",
        ),
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
      ]),
      html.body(
        [
          attribute.styles([
            #("max-width", "40rem"),
            #("margin", "2rem auto"),
            #("font-family", "sans-serif"),
          ]),
        ],
        [
          html.script(
            [attribute.id("model"), attribute.type_("application/json")],
            json.to_string(shared.anime_list_to_json(anime_list)),
          ),
          html.div([attribute.id("app")], []),

          html.hr([]),
          html.h2([], [html.text("Rate this anime")]),

          server_component.element([
          server_component.route("/ws/rate"),
          // Set initial value via attribute — the component's
          // on_attribute_change handler will pick this up.
            raiting.value(5),
          ],[]),
          html.script([], dev_reload.script()),
        ],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}

fn get_anime_from_db() {
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Cowboy Bebop", episodes: 69),
    Anime(id: 3, title: "Cowboy Bebop", episodes: 420),
  ]
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

fn serve_anime_api() -> Response(ResponseData) {
  let body =
    get_anime_from_db()
    |> shared.anime_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
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

fn serve_rating_ws(req: Request(Connection)) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: init_rating_socket,
    handler: loop_rating_socket,
    on_close: close_rating_socket,
  )
}

type RatingSocket {
  RatingSocket(
    runtime: lustre.Runtime(raiting.Msg),
    self: Subject(server_component.ClientMessage(raiting.Msg)),
  )
}

type RatingSocketMsg =
  server_component.ClientMessage(raiting.Msg)

fn init_rating_socket(
  _connection,
) -> #(RatingSocket, Option(Selector(RatingSocketMsg))) {
  // 1. Create the component (same constructor as client version)
  let app = raiting.component()

  // 2. Start it as a server component — creates an OTP actor
  let assert Ok(runtime) = lustre.start_server_component(app, Nil)

  // 3. Create a Subject so the runtime can send us DOM patches
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  // 4. Subscribe to the runtime. When the view changes, we hear about it.
  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  #(RatingSocket(runtime:, self:), Some(selector))
}

fn loop_rating_socket(
  state: RatingSocket,
  message: mist.WebsocketMessage(RatingSocketMsg),
  connection: mist.WebsocketConnection,
) -> mist.Next(RatingSocket, RatingSocketMsg) {
  case message {
    // Browser sent an event (click, input, attribute change).
    // Decode it and forward to the Lustre runtime.
    mist.Text(raw_json) -> {
      case json.parse(raw_json, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.runtime, runtime_message)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

    // The Lustre runtime computed a DOM patch.
    // Encode as JSON and push over the WebSocket.
    mist.Custom(client_message) -> {
      let patch_json = server_component.client_message_to_json(client_message)
      let assert Ok(_) =
        mist.send_text_frame(connection, json.to_string(patch_json))
      mist.continue(state)
    }

    mist.Binary(_) -> mist.continue(state)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn close_rating_socket(state: RatingSocket) -> Nil {
  // Shut down the OTP actor. Without this: memory leak + zombie process.
  lustre.shutdown()
  |> lustre.send(to: state.runtime)
}
