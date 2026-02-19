import exception
import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/otp/actor
import gleam/result
import pog

// --- Actor plumbing ---

type State {
  State(db: pog.Connection)
}

type Msg {
  Fetch(url: String, reply: process.Subject(Result(BitArray, Nil)))
}

/// Start the cache actor and create the table. Call once on startup.
pub fn start(db: pog.Connection) -> Nil {
  let assert Ok(_) =
    pog.query(
      "CREATE TABLE IF NOT EXISTS http_cache (
        url          TEXT PRIMARY KEY,
        body         BYTEA NOT NULL,
        content_type TEXT NOT NULL DEFAULT '',
        fetched_at   TIMESTAMPTZ DEFAULT now()
      )",
    )
    |> pog.execute(db)

  let name = process.new_name(prefix: "http_cache")

  let assert Ok(started) =
    actor.new(State(db:))
    |> actor.named(name)
    |> actor.on_message(handle_message)
    |> actor.start

  put_subject(started.data)

  Nil
}

fn handle_message(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Fetch(url:, reply:) -> {
      io.println("[cache] processing: " <> url)
      let db = state.db
      case check_cache(db, url) {
        Ok(body) -> {
          io.println("[cache] HIT (actor): " <> url)
          process.send(reply, Ok(body))
        }
        Error(_) -> {
          io.println("[cache] MISS (actor), spawning fetch: " <> url)
          // Spawn network fetch so the actor stays responsive
          process.spawn(fn() {
            let result = fetch_and_store(db, url)
            case result {
              Ok(_) -> io.println("[cache] ok: " <> url)
              Error(_) -> io.println("[cache] error: " <> url)
            }
            process.send(reply, result)
          })
          Nil
        }
      }
      actor.continue(state)
    }
  }
}

// --- Public API ---

/// Fetch a URL as a UTF-8 string, using the Postgres cache.
pub fn fetch(url: String) -> Result(String, Nil) {
  fetch_bytes(url)
  |> result.try(bit_array.to_string)
  |> result.replace_error(Nil)
}

/// Fetch a URL as raw bytes, using the Postgres cache.
pub fn fetch_bytes(url: String) -> Result(BitArray, Nil) {
  let subject = get_subject()
  actor.call(subject, fn(reply) { Fetch(url:, reply:) }, waiting: 30_000)
}

// --- Persistent term storage for the actor subject ---

@external(erlang, "persistent_term", "put")
fn pt_put(key: String, value: process.Subject(Msg)) -> Nil

@external(erlang, "persistent_term", "get")
fn pt_get(key: String) -> process.Subject(Msg)

const pt_key = "http_cache_subject"

fn put_subject(subject: process.Subject(Msg)) -> Nil {
  pt_put(pt_key, subject)
}

fn get_subject() -> process.Subject(Msg) {
  pt_get(pt_key)
}

/// Check if a URL returns a 2xx response (HEAD request, no body downloaded, not cached).
pub fn exists(url: String) -> Bool {
  case request.to(url) {
    Ok(req) -> {
      let req = req |> request.set_method(http.Head) |> request.set_body(<<>>)
      case safe_dispatch(req) {
        Ok(resp) -> resp.status >= 200 && resp.status < 300
        _ -> False
      }
    }
    Error(_) -> False
  }
}

// --- Internal ---

/// Dispatch an HTTP request, catching Erlang exceptions (e.g. shutdown).
fn safe_dispatch(req) {
  case
    exception.rescue(fn() {
      httpc.configure()
      |> httpc.follow_redirects(True)
      |> httpc.dispatch_bits(req)
    })
  {
    Ok(Ok(resp)) -> Ok(resp)
    _ -> Error(Nil)
  }
}

fn check_cache(db: pog.Connection, url: String) -> Result(BitArray, Nil) {
  let decoder = {
    use body <- decode.field(0, decode.bit_array)
    decode.success(body)
  }

  let cached =
    "SELECT body FROM http_cache WHERE url = $1"
    |> pog.query
    |> pog.parameter(pog.text(url))
    |> pog.returning(decoder)
    |> pog.execute(db)

  case cached {
    Ok(pog.Returned(_, [body])) -> Ok(body)
    _ -> Error(Nil)
  }
}

fn fetch_and_store(
  db: pog.Connection,
  url: String,
) -> Result(BitArray, Nil) {
  use req <- result.try(
    request.to(url) |> result.replace_error(Nil),
  )
  let req = request.set_body(req, <<>>)

  io.println("[cache] fetching from network: " <> url)
  use resp <- result.try(safe_dispatch(req))
  io.println("[cache] network responded: " <> url)

  use resp <- result.try(case resp.status >= 200 && resp.status < 300 {
    True -> Ok(resp)
    False -> Error(Nil)
  })

  let content_type =
    resp.headers
    |> find_header("content-type")

  let _ =
    "INSERT INTO http_cache (url, body, content_type)
     VALUES ($1, $2, $3)
     ON CONFLICT (url) DO UPDATE SET body = $2, content_type = $3, fetched_at = now()"
    |> pog.query
    |> pog.parameter(pog.text(url))
    |> pog.parameter(pog.bytea(resp.body))
    |> pog.parameter(pog.text(content_type))
    |> pog.execute(db)

  Ok(resp.body)
}

fn find_header(headers: List(#(String, String)), name: String) -> String {
  case headers {
    [] -> ""
    [#(k, v), ..] if k == name -> v
    [_, ..rest] -> find_header(rest, name)
  }
}
