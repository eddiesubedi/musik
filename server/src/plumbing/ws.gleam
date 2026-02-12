import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, Some}
import lustre
import lustre/server_component
import mist.{type Connection, type ResponseData}

// --- Types ---

type ComponentSocket(msg) {
  ComponentSocket(
    runtime: lustre.Runtime(msg),
    self: Subject(server_component.ClientMessage(msg)),
  )
}

// --- Public API ---

/// Serve any Lustre app as a server component over WebSocket.
/// Just pass the request and the app — all plumbing is handled here.
pub fn serve(
  req: Request(Connection),
  app: lustre.App(Nil, model, msg),
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_connection) { init_socket(app) },
    handler: loop_socket,
    on_close: close_socket,
  )
}

// --- Internals ---

fn init_socket(
  app: lustre.App(Nil, model, msg),
) -> #(
  ComponentSocket(msg),
  Option(Selector(server_component.ClientMessage(msg))),
) {
  let assert Ok(runtime) = lustre.start_server_component(app, Nil)

  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  #(ComponentSocket(runtime:, self:), Some(selector))
}

fn loop_socket(
  state: ComponentSocket(msg),
  message: mist.WebsocketMessage(server_component.ClientMessage(msg)),
  connection: mist.WebsocketConnection,
) -> mist.Next(ComponentSocket(msg), server_component.ClientMessage(msg)) {
  case message {
    // Browser → Server: user event (click, input, attribute change)
    mist.Text(raw_json) -> {
      case json.parse(raw_json, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.runtime, runtime_message)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

    // Server → Browser: DOM patch
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

fn close_socket(state: ComponentSocket(msg)) -> Nil {
  lustre.shutdown()
  |> lustre.send(to: state.runtime)
}
