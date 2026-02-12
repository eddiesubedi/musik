import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/option.{type Option, Some}
import mist.{type Connection, type ResponseData}

const watch_path = "priv/static/client.js"

type ReloadSocket {
  ReloadSocket(self: Subject(ReloadCheck), last_mtime: Int)
}

type ReloadCheck {
  Check
}

pub fn serve(req: Request(Connection)) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: init_socket,
    handler: loop_socket,
    on_close: fn(_) { Nil },
  )
}

pub fn script() -> String {
  "
  (function() {
    var was = false;
    function connect() {
      var ws = new WebSocket('ws://' + location.host + '/dev/reload');
      ws.onopen = function() { if (was) location.reload(); was = true; };
      ws.onmessage = function() { location.reload(); };
      ws.onclose = function() { setTimeout(connect, 1000); };
    }
    connect();
  })();
  "
}

fn init_socket(
  _connection,
) -> #(ReloadSocket, Option(Selector(ReloadCheck))) {
  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)
  let mtime = file_mtime(watch_path)
  process.send_after(self, 0, Check)
  #(ReloadSocket(self:, last_mtime: mtime), Some(selector))
}

fn loop_socket(
  state: ReloadSocket,
  message: mist.WebsocketMessage(ReloadCheck),
  connection: mist.WebsocketConnection,
) -> mist.Next(ReloadSocket, ReloadCheck) {
  case message {
    mist.Custom(Check) -> {
      let mtime = file_mtime(watch_path)
      case mtime == state.last_mtime {
        True -> {
          process.send_after(state.self, 0, Check)
          mist.continue(state)
        }
        False -> {
          let assert Ok(_) = mist.send_text_frame(connection, "reload")
          process.send_after(state.self, 0, Check)
          mist.continue(ReloadSocket(..state, last_mtime: mtime))
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    _ -> mist.continue(state)
  }
}

@external(erlang, "dev_ffi", "file_mtime")
fn file_mtime(path: String) -> Int
