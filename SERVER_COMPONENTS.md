# Lustre Server Components Cheat Sheet

## Mental Model

```
What do I need?                        → Use this
─────────────────────────────────────────────────────
Static content, no interactivity       → Server-rendered HTML
Data available at page load + local UI → Hydration + client-side Lustre
Real-time data, shared state, or       → Server component (WebSocket)
  data that lives on the server
Local-only UI (dropdowns, modals)      → Client-side Lustre
```

No REST. Ever.

---

## Architecture

```
Browser                            Server (BEAM)
┌────────────────────┐             ┌────────────────────┐
│                    │  WebSocket  │   Lustre Runtime    │
│  Dumb DOM screen   │ ←─ patches ─│   (OTP actor)      │
│                    │ ── events ─→│   init/update/view  │
│                    │             │   has direct DB     │
└────────────────────┘             │   access            │
                                   └────────────────────┘
```

- App logic (init/update/view) runs on the server as a BEAM process
- Browser only applies DOM patches and forwards user events
- No network request thinking — you just use data in your `view` like normal

---

## Anatomy of a Server Component

### 1. The Component (same code as client-side)

```gleam
// rating.gleam — nothing server-specific here
import lustre
import lustre/component
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}
import lustre/event

pub type Model { Model(score: Int) }

pub type Msg { SetScore(Int) }

pub fn component() {
  lustre.component(init, update, view, [
    // Parent can pass data via attributes
    component.on_attribute_change("value", fn(v) {
      int.parse(v) |> result.map(SetScore)
    }),
  ])
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(score: 0), effect.none())
}

fn update(model, msg) -> #(Model, Effect(Msg)) {
  case msg {
    SetScore(n) -> #(Model(score: n), effect.none())
  }
}

fn view(model) -> Element(Msg) {
  html.div([], [
    html.text("Score: " <> int.to_string(model.score)),
    html.button([event.on_click(SetScore(model.score + 1))], [
      html.text("+"),
    ]),
  ])
}
```

### 2. The WebSocket Plumbing (generic, reuse for every component)

```gleam
// ws.gleam — write once, use for all server components
import gleam/erlang/process.{type Subject, type Selector}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, Some}
import lustre
import lustre/server_component
import mist.{type Connection, type ResponseData}

// --- Types ---

type Socket(msg) {
  Socket(
    runtime: lustre.Runtime(msg),
    self: Subject(server_component.ClientMessage(msg)),
  )
}

// --- Public API ---

/// Serve any Lustre app as a server component over WebSocket.
/// Just pass the app constructor and start args.
pub fn serve(
  req: Request(Connection),
  app: lustre.App(start_args, model, msg),
  start_args: start_args,
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) { init(app, start_args) },
    handler: loop,
    on_close: close,
  )
}

// --- Internals ---

fn init(app, start_args) -> #(Socket(msg), Option(Selector(server_component.ClientMessage(msg)))) {
  // Start the Lustre actor
  let assert Ok(runtime) = lustre.start_server_component(app, start_args)

  // Create mailbox for receiving DOM patches
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  // Tell runtime: "send patches here"
  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  #(Socket(runtime:, self:), Some(selector))
}

fn loop(state, message, connection) {
  case message {
    // Browser → Server: user event (click, input, etc)
    mist.Text(raw_json) -> {
      case json.parse(raw_json, server_component.runtime_message_decoder()) {
        Ok(msg) -> lustre.send(state.runtime, msg)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

    // Server → Browser: DOM patch
    mist.Custom(client_message) -> {
      let patch = server_component.client_message_to_json(client_message)
      let assert Ok(_) =
        mist.send_text_frame(connection, json.to_string(patch))
      mist.continue(state)
    }

    mist.Binary(_) -> mist.continue(state)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn close(state) {
  lustre.shutdown() |> lustre.send(to: state.runtime)
}
```

### 3. The Router (clean, one line per component)

```gleam
// server.gleam
case request.path_segments(req) {
  []              -> serve_html(req)
  ["client.js"]   -> serve_client_js()
  ["ws", "rate"]  -> ws.serve(req, rating.component(), Nil)
  ["ws", "chat"]  -> ws.serve(req, chat.component(), Nil)
  ["ws", "todo"]  -> ws.serve(req, todo.component(), Nil)
  _               -> not_found()
}
```

### 4. Rendering in HTML

```gleam
fn serve_html(req) {
  html([], [
    html.head([], [
      // Lustre's client-side JS that handles the WS connection
      html.script([attribute.type_("module")], "
        import { setup } from '/client.js';
        setup();
      "),
    ]),
    html.body([], [
      // Static server-rendered content
      html.h1([], [html.text("My App")]),

      // Server component — just an element with a route
      element.element("lustre-server-component", [
        server_component.route("/ws/rate"),
        rating.value(5),
      ], []),
    ]),
  ])
}
```

---

## Communication

### Parent → Component (attributes)

```gleam
// Parent renders:
element.element("lustre-server-component", [
  server_component.route("/ws/rate"),
  rating.value(5),               // ← sets attribute "value" = "5"
], [])

// Component receives via on_attribute_change:
component.on_attribute_change("value", fn(v) {
  int.parse(v) |> result.map(SetScore)
})
```

### Component → Parent (DOM events)

```gleam
// Component emits:
event.emit("change", json.int(model.score))

// Parent listens:
event.on("change", {
  decode.at(["detail"], decode.int) |> decode.map(ScoreChanged)
})
```

---

## Shared State (Multi-User)

By default each WebSocket connection spawns its own actor.
For shared state, start ONE actor and have everyone subscribe to it.

```gleam
// At app startup — one shared actor
let assert Ok(shared_runtime) =
  lustre.start_server_component(chat.component(), Nil)

// In the WebSocket handler — don't start a new actor, just subscribe
pub fn serve_shared(
  req: Request(Connection),
  runtime: lustre.Runtime(msg),
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) { init_shared(runtime) },
    handler: loop,    // same loop as before
    on_close: fn(_) { Nil },  // don't shutdown — others are using it
  )
}

fn init_shared(runtime) {
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  // Subscribe to the SHARED runtime
  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  #(Socket(runtime:, self:), Some(selector))
}
```

Router:

```gleam
// Start shared actor once in main()
let assert Ok(chat_runtime) =
  lustre.start_server_component(chat.component(), Nil)

// Every connection shares the same actor
["ws", "chat"] -> ws.serve_shared(req, chat_runtime)
```

Now 50 users see the same state. One user types → actor updates → all 50 get the patch.

**Important**: Don't call `lustre.shutdown()` in `on_close` for shared actors — other users are still connected.

---

## Scaling

### Why it scales

- Each actor is ~2KB memory
- BEAM handles millions of concurrent processes
- WebSocket is one persistent TCP connection (no HTTP overhead per request)
- DOM patches are tiny (just the diff, not full HTML)

### Numbers

```
1 user   × 3 components = 3 actors      → nothing
1,000    × 3 components = 3,000 actors   → nothing
100,000  × 3 components = 300,000 actors → still fine
```

You'll hit bandwidth limits before actor limits.

### Shared actors scale even better

```
1 shared chat room = 1 actor, regardless of user count
50 chat rooms × 1 actor each = 50 actors for unlimited users
```

### Tips

1. **Only use server components where needed** — static HTML is free, client-side Lustre is free (for the server). Server components cost one actor + one WebSocket per connection per component.

2. **Share actors when state is shared** — don't spin up 1000 identical actors for the same chat room.

3. **Keep patches small** — smaller views = smaller diffs = less data over the wire. Break big pages into targeted server components rather than one giant one.

4. **Use client-side Lustre for local UI** — a dropdown doesn't need a WebSocket round trip.

---

## Decision Flowchart

```
Do I need this data/feature?
│
├─ It's static content
│  → Server-render HTML. Done.
│
├─ Data is available at page load + UI is local
│  → Bake data into HTML, hydrate with client-side Lustre.
│
├─ Data lives on server OR shared between users OR real-time
│  → Server component.
│  │
│  ├─ Each user has their own state? → One actor per connection (default)
│  └─ Users share state?             → One shared actor, many subscribers
│
└─ Pure local interaction (dropdown, modal, tabs)
   → Client-side Lustre. No server needed.
```
