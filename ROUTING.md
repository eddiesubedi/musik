# Convention-Based Routing for Lustre

A step-by-step guide to breaking a monolithic `server.gleam` into a clean,
convention-based file structure. Each step introduces exactly **one** extraction.
By the end your server entry point is 12 lines and adding a new page is three
steps.

This guide assumes you already have a working Lustre full-stack app — a
`server.gleam` with routes, a server component with WebSocket plumbing, static
asset serving, and an HTML layout. If you followed the WALKTHROUGH or GUIDE, you
have exactly that.

---

## The problem

Open `server/src/server.gleam`. Count the lines.

A single page with one server component is already 223 lines. That file contains:

- The Mist entry point (`main`)
- The route dispatcher (case on path segments)
- The HTML layout (head, meta, scripts, body wrapper)
- Page-specific content (hydration data, app mount, server component element)
- Static asset serving (client.js, lustre runtime)
- An API endpoint
- All the WebSocket plumbing for the rating component (~60 lines of types,
  init, loop, close)
- Dev reload wiring

Now imagine adding a second page with its own server component. You'd copy the
entire WebSocket block, change the type names, change the component constructor.
A third page? Copy again. The file grows linearly with every feature.

Worse: every concern is tangled together. Changing the HTML shell means editing
the same file as the WebSocket handler. The router, the layout, and the
component plumbing are all mixed in one place.

---

## The target

Here's where we're headed:

```
server/src/
  server.gleam          12 lines   entry point
  router.gleam          25 lines   path dispatch
  layout.gleam          45 lines   common HTML shell
  static.gleam          30 lines   client.js + lustre runtime
  ws.gleam              55 lines   generic WebSocket helper (write once)
  dev_reload.gleam      unchanged
  server_ffi.erl        unchanged
  pages/
    home.gleam          50 lines   page + ws + api
  components/
    raiting.gleam       unchanged  (moved from server/src/)
```

Each file has one job. Adding a new page means: create one file in `pages/`,
add 1–3 lines in `router.gleam`. The WebSocket boilerplate is zero — `ws.serve`
handles all of it.

---

## Step 1: Extract the generic WebSocket handler — `ws.gleam`

### Why

Look at the WebSocket plumbing in `server.gleam` (lines 147–222). There are 76
lines of types, init, loop, and close functions. Now look at what's actually
specific to the rating component:

- The type names (`RatingSocket`, `RatingSocketMsg`)
- One line: `raiting.component()`

Everything else — starting the server component actor, creating the subject,
subscribing, forwarding events from the browser, pushing patches back — is
identical for **every** server component. The only thing that changes is which
`App` you pass in.

Gleam's parametric polymorphism solves this cleanly. A generic function
parameterized over the component's `msg` type can handle all the plumbing. The
caller just passes in the `App` — Gleam monomorphizes to concrete types at
compile time. No type erasure, no tricks.

### Code

Create `server/src/ws.gleam`:

```gleam
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
```

### What happened

Compare `ws.serve` to the old code:

| Old (`server.gleam`) | New (`ws.gleam`) |
|---|---|
| `RatingSocket` type with `raiting.Msg` | `ComponentSocket(msg)` — generic |
| `RatingSocketMsg` type alias | Gone — the generic covers it |
| `serve_rating_ws` | `ws.serve` — pass any `App` |
| `init_rating_socket` calls `raiting.component()` | `init_socket` receives the `App` as a parameter |
| `loop_rating_socket` | `loop_socket` — identical logic, generic types |
| `close_rating_socket` | `close_socket` — identical |

The old code was 76 lines of component-specific plumbing. The new code is 55
lines that work for **every** server component you'll ever write.

### Verify

This module compiles on its own — it has no dependency on `raiting` or any page.
You haven't changed `server.gleam` yet, so nothing is broken. Run:

```sh
cd server && gleam build
```

---

## Step 2: Extract static asset serving — `static.gleam`

### Why

`serve_client_js` and `serve_lustre_runtime` are pure utility functions. They
don't depend on any page, component, or route logic. They just map a path to a
file with the right content-type header. Keeping them in `server.gleam` clutters
the file with concerns unrelated to routing or page rendering.

### Code

Create `server/src/static.gleam`:

```gleam
import gleam/bytes_tree
import gleam/erlang/application
import gleam/http/response.{type Response}
import gleam/option.{None}
import mist.{type ResponseData}

pub fn serve_client_js() -> Response(ResponseData) {
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

pub fn serve_lustre_runtime() -> Response(ResponseData) {
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
```

### Verify

```sh
cd server && gleam build
```

No changes to `server.gleam` yet — these are additive.

---

## Step 3: Extract the HTML layout — `layout.gleam`

### Why

The `serve_html` function in `server.gleam` mixes two things:

1. The **shell** — `<html>`, `<head>` (charset, viewport, title, script tags),
   `<body>` wrapper with styles, dev reload script. This is identical for every
   page.
2. The **body content** — hydration data, app mount div, server component
   element. This is page-specific.

Splitting them means every page gets a consistent shell automatically, and you
only write what's different.

### Code

Create `server/src/layout.gleam`:

```gleam
import dev_reload
import gleam/bytes_tree
import gleam/http/response.{type Response}
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html.{html}
import mist.{type ResponseData}

/// Render a full HTML page with the common shell.
/// Each page only provides its title and body content.
pub fn render(
  title page_title: String,
  head head_extra: List(Element(Nil)),
  body body_children: List(Element(Nil)),
) -> Response(ResponseData) {
  let head_children = [
    html.meta([attribute.charset("utf-8")]),
    html.meta([
      attribute.content("width=device-width, initial-scale=1"),
      attribute.name("viewport"),
    ]),
    html.title([], page_title),
    html.script(
      [attribute.src("/client.js"), attribute.type_("module")],
      "",
    ),
    html.script(
      [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
      "",
    ),
    ..head_extra
  ]

  let page =
    html([], [
      html.head([], head_children),
      html.body(
        [
          attribute.styles([
            #("max-width", "40rem"),
            #("margin", "2rem auto"),
            #("font-family", "sans-serif"),
          ]),
        ],
        list.append(body_children, [
          html.script([], dev_reload.script()),
        ]),
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}
```

### Design notes

**`Element(Nil)` for the body**: Server-rendered HTML doesn't have event
handlers that fire on the server. The `Nil` message type enforces that — page
modules produce static content. Interactive elements like
`<lustre-server-component>` work through their WebSocket, not through the
rendered HTML.

**`head_extra`**: Most pages pass `[]` here. But if a page needs a custom
stylesheet or inline script, it can add elements without modifying the layout.

**`dev_reload.script()`**: Appended to every page. In production you'd gate
this behind an `is_dev()` check.

### Verify

```sh
cd server && gleam build
```

---

## Step 4: Create your first page module — `pages/home.gleam`

### Why

This is where the convention comes in. Each page module follows a pattern:

| Export | Purpose | Required? |
|---|---|---|
| `page(req)` | Serve the HTML page | Yes |
| `ws(req)` | Serve a WebSocket for a server component | Only if the page has one |
| `api(req)` | Serve a JSON API endpoint | Only if the page needs one |

This convention isn't enforced by a type or interface — Gleam doesn't have
traits. It's a naming convention that makes the router predictable and every
page module readable at a glance.

### Code

Create the directory, then the file.

```sh
mkdir -p server/src/pages
```

Create `server/src/pages/home.gleam`:

```gleam
import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import layout
import lustre/attribute
import lustre/element/html
import lustre/server_component
import mist.{type Connection, type ResponseData}
import raiting
import shared.{Anime}
import ws

/// GET / — the home page
pub fn page(_req: Request(Connection)) -> Response(ResponseData) {
  let anime_list = get_anime_from_db()

  layout.render(
    title: "Anime Tracker",
    head: [],
    body: [
      html.script(
        [attribute.id("model"), attribute.type_("application/json")],
        json.to_string(shared.anime_list_to_json(anime_list)),
      ),
      html.div([attribute.id("app")], []),
      html.hr([]),
      html.h2([], [html.text("Rate this anime")]),
      server_component.element([
        server_component.route("/ws/rate"),
        raiting.value(5),
      ], []),
    ],
  )
}

/// WS /ws/rate — the rating server component
pub fn ws(req: Request(Connection)) -> Response(ResponseData) {
  ws.serve(req, raiting.component())
}

/// GET /api/anime — JSON endpoint
pub fn api(_req: Request(Connection)) -> Response(ResponseData) {
  let body =
    get_anime_from_db()
    |> shared.anime_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
}

fn get_anime_from_db() {
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Cowboy Bebop", episodes: 69),
    Anime(id: 3, title: "Cowboy Bebop", episodes: 420),
  ]
}
```

### What changed from the old code

The page function went from building the entire HTML document (44 lines in
`serve_html`) to calling `layout.render` with just the body content (15 lines).

The WebSocket handler went from 76 lines (types + init + loop + close) to one
line: `ws.serve(req, raiting.component())`.

The `get_anime_from_db` function moved here because it's home page data. If
other pages need it too, you'd extract it to a `db.gleam` module.

### Verify

```sh
cd server && gleam build
```

---

## Step 5: Move components to `components/`

### Why

Pages and components are different things:

- **Pages** are request handlers. They compose layout + data + components into
  an HTTP response. They live in `pages/`.
- **Components** are reusable Lustre apps (init/update/view + a `component()`
  constructor). They can be used by any page. They live in `components/`.

Right now `raiting.gleam` sits at the top level of `server/src/`. As you add
more components (chat, carousel, clock), the top level gets cluttered. The
`components/` directory keeps them organized.

### Code

```sh
mkdir -p server/src/components
mv server/src/raiting.gleam server/src/components/raiting.gleam
```

Then update the import in `server/src/pages/home.gleam`:

```diff
- import raiting
+ import components/raiting
```

The component code itself doesn't change at all. Its `component()` function,
`Model`, and `Msg` type stay exactly the same.

### Verify

```sh
cd server && gleam build
```

---

## Step 6: Build the router — `router.gleam`

### Why

The case expression in `server.gleam` currently handles everything: pages, API,
WebSocket, static assets, dev reload. Extracting it to `router.gleam` means
`server.gleam` is just the Mist boot code, and all route logic is in one
readable file.

The router is deliberately a simple case match, not a dynamic registry. Gleam
has no runtime reflection — you can't auto-discover modules from the filesystem.
Two lines per page in the router is the practical minimum, and it's more
idiomatic than iterating a list of page records.

### Code

Create `server/src/router.gleam`:

```gleam
import dev_reload
import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist.{type Connection, type ResponseData}
import pages/home
import static

pub fn handle(req: Request(Connection)) -> Response(ResponseData) {
  case request.path_segments(req) {
    // -- Pages --
    [] -> home.page(req)

    // -- API --
    ["api", "anime"] -> home.api(req)

    // -- WebSocket --
    ["ws", "rate"] -> home.ws(req)

    // -- Dev --
    ["dev", "reload"] -> dev_reload.serve(req)

    // -- Static assets --
    ["client.js"] -> static.serve_client_js()
    ["lustre", "runtime.mjs"] -> static.serve_lustre_runtime()

    // -- 404 --
    _ -> response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}
```

### Reading the router

Notice how every page's routes cluster together. The home page owns three
routes: its page, its API, and its WebSocket. When you add a new page, you add
its routes in the same pattern. The comments create visual sections.

### Verify

```sh
cd server && gleam build
```

---

## Step 7: Slim down `server.gleam`

### Why

This is the payoff. `server.gleam` goes from 223 lines to 12. It becomes just
the entry point: start Mist, bind, listen.

### Code

Replace `server/src/server.gleam` entirely:

```gleam
import gleam/erlang/process
import mist
import router

pub fn main() {
  let assert Ok(_) =
    router.handle
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
```

That's it. Twelve lines. `router.handle` is a function reference — Mist calls
it for every incoming request.

### Verify

Run the server and check every route:

```sh
cd server && gleam run
```

In another terminal:

```sh
# Page loads
curl -s http://localhost:3000/ | head -5

# Static assets
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/client.js
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/lustre/runtime.mjs

# API
curl -s http://localhost:3000/api/anime | head -1

# 404
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/nope
```

Open `http://localhost:3000` in a browser. The rating component should still
work — events over WebSocket, patches coming back, the score updating live.

---

## The payoff: adding a new page

Say you want an `/about` page with a live clock server component.

**Step 1** — Create the component in `server/src/components/clock.gleam`:

```gleam
import gleam/erlang/process
import gleam/int
import lustre
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub type Model {
  Model(seconds: Int)
}

pub opaque type Msg {
  Tick
}

pub fn component() -> lustre.App(_, Model, Msg) {
  lustre.component(init, update, view, [])
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(seconds: 0), tick())
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Tick -> #(Model(seconds: model.seconds + 1), tick())
  }
}

fn tick() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    process.sleep(1000)
    dispatch(Tick)
  })
}

fn view(model: Model) -> Element(Msg) {
  let mins = model.seconds / 60
  let secs = model.seconds % 60
  let pad = fn(n) {
    case n < 10 {
      True -> "0"
      False -> ""
    }
  }
  html.p([], [
    html.text(
      pad(mins)
      <> int.to_string(mins)
      <> ":"
      <> pad(secs)
      <> int.to_string(secs),
    ),
  ])
}
```

**Step 2** — Create the page in `server/src/pages/about.gleam`:

```gleam
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import layout
import lustre/element/html
import lustre/server_component
import mist.{type Connection, type ResponseData}
import components/clock
import ws

pub fn page(_req: Request(Connection)) -> Response(ResponseData) {
  layout.render(
    title: "About",
    head: [],
    body: [
      html.h1([], [html.text("About")]),
      html.p([], [html.text("This page has been open for:")]),
      server_component.element([
        server_component.route("/ws/clock"),
      ], []),
    ],
  )
}

pub fn ws(req: Request(Connection)) -> Response(ResponseData) {
  ws.serve(req, clock.component())
}
```

**Step 3** — Add two lines to `router.gleam`:

```gleam
import pages/about
// ... in the case expression:
["about"] -> about.page(req)
["ws", "clock"] -> about.ws(req)
```

Done. Three files touched, zero WebSocket boilerplate written. The generic
`ws.serve` handled it all.

---

## Shared state variant

The default `ws.serve` starts a new actor per WebSocket connection. Each user
gets their own independent component state. This is correct for things like a
rating widget or a form.

But some components need **shared state** — a chat room where all users see the
same messages, a live dashboard, a collaborative editor. For these, you want
**one** actor that all connections subscribe to.

### How to modify `ws.gleam`

Add a second public function alongside `serve`:

```gleam
/// Serve a WebSocket that subscribes to an existing shared runtime.
/// The actor is NOT started here — it must be started once at app startup
/// and passed in.
pub fn serve_shared(
  req: Request(Connection),
  runtime: lustre.Runtime(msg),
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_connection) { init_shared(runtime) },
    handler: loop_socket,    // same loop as before
    on_close: fn(_) { Nil }, // don't shutdown — others are using it
  )
}

fn init_shared(
  runtime: lustre.Runtime(msg),
) -> #(
  ComponentSocket(msg),
  Option(Selector(server_component.ClientMessage(msg))),
) {
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  // Subscribe to the SHARED runtime — don't start a new one
  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  #(ComponentSocket(runtime:, self:), Some(selector))
}
```

### Key differences from `serve`

| | `serve` (per-user) | `serve_shared` (multi-user) |
|---|---|---|
| Actor lifetime | Created per connection, shut down on close | Created once at startup, lives forever |
| `on_init` | Starts a new actor via `start_server_component` | Subscribes to an existing actor |
| `on_close` | Calls `lustre.shutdown()` | Does nothing — other users are still connected |
| State isolation | Each user has independent state | All users see the same state |

### Using it in a page

Start the shared actor once in `server.gleam`:

```gleam
import gleam/erlang/process
import components/chat
import lustre
import mist
import router

pub fn main() {
  // Start shared chat actor — lives for the entire app lifetime
  let assert Ok(chat_runtime) =
    lustre.start_server_component(chat.component(), Nil)

  let assert Ok(_) =
    router.handle(_, chat_runtime)
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
```

Thread it through the router:

```gleam
// router.gleam
pub fn handle(
  req: Request(Connection),
  chat_runtime: lustre.Runtime(chat.Msg),
) -> Response(ResponseData) {
  case request.path_segments(req) {
    [] -> home.page(req)
    ["chat"] -> chat_page.page(req)
    ["ws", "chat"] -> ws.serve_shared(req, chat_runtime)
    ["ws", "rate"] -> home.ws(req)
    // ...
  }
}
```

Now 50 users on `/chat` all see the same state. One user types, the actor
updates, all 50 get the DOM patch.

---

## Final file tree

```
server/src/
  server.gleam              main(), starts Mist
  router.gleam              case match on path segments
  layout.gleam              common HTML shell
  static.gleam              client.js + lustre runtime serving
  ws.gleam                  generic WS: serve() + serve_shared()
  dev_reload.gleam          hot reload (unchanged)
  server_ffi.erl            Erlang FFI (unchanged)
  pages/
    home.gleam              page() + ws() + api()
    about.gleam             page() + ws()
  components/
    raiting.gleam           rating widget (unchanged, moved)
    clock.gleam             live clock
    chat.gleam              shared chat
```

### The convention at a glance

```
To add a page:
  1. Create server/src/pages/foo.gleam
     - Export page(req)            → serves HTML via layout.render(...)
     - Export ws(req)   [optional] → serves WebSocket via ws.serve(...)
     - Export api(req)  [optional] → serves JSON
  2. Add 1–3 lines in router.gleam

To add a reusable component:
  1. Create server/src/components/bar.gleam
     - Export component()          → returns lustre.App(...)
  2. Use it in any page's ws() function
```

No framework magic. No code generation. No runtime reflection. Just functions,
modules, and a naming convention.
