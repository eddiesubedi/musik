# Build a Full-Stack Lustre App

A step-by-step guide to building a full-stack Gleam app with Lustre. Covers
SSR, hydration, REST, real Web Components, server components, routing, custom
effects, and production builds.

No toy examples. We jump straight into `lustre.application` and build the real
thing.

---

## The problem this solves

Every web framework is trying to solve the same problem: **moving data between
client and server**.

**GraphQL** lets front-end developers write database queries. Downside: you've
let front-end developers write database queries.

**React Server Components** run statically on the server with database access.
Downside: confusing rules, no feature parity with client components, you can
lock yourself out of the feature.

**Phoenix LiveView** runs the entire application over WebSocket. Downside: if
your internet cuts out, your app breaks.

**Lustre's answer: universal components.** Write a component once. Run it on the
client as a Web Component, or on the server as an OTP actor. Same `init`,
`update`, `view`. The runtime handles the rest.

The key insight: **a BEAM process IS an MVU update loop.** Both are encapsulated
state that receives messages, updates itself, and produces output. Lustre just
makes this explicit.

---

## The architecture

```
+--------------------------------------------------------------+
|  Browser                                                     |
|                                                              |
|  +--------------------+   +-------------------------------+  |
|  | Lustre SPA         |   | <lustre-server-component>     |  |
|  | (JavaScript)       |   | (~10kB client runtime)        |  |
|  |                    |   |                               |  |
|  | Hydrated from      |   | DOM patches arrive            |  |
|  | server JSON        |   | over WebSocket                |  |
|  |                    |   |                               |  |
|  | Fetches /api/*     |   | Events sent back              |  |
|  | for fresh data     |   | over WebSocket                |  |
|  |                    |   |                               |  |
|  | Can embed client   |   | Can embed client              |  |
|  | Web Components     |   | Web Components inside         |  |
|  +---------+----------+   +---------------+---------------+  |
+------------|-------------------------------|------------------+
             | HTTP                          | WebSocket
             v                              v
+--------------------------------------------------------------+
|  Server (Erlang/BEAM)                                        |
|                                                              |
|  GET /              -> SSR HTML + hydration JSON             |
|  GET /client.js     -> bundled SPA                           |
|  GET /api/anime     -> JSON from database                    |
|  GET /lustre/runtime.mjs -> server component runtime         |
|  WS  /ws/rate       -> rating component (OTP actor)          |
+--------------------------------------------------------------+
```

The vision: your client SPA handles most of the app. Server component **islands**
handle things that need the backend (database, real-time, secure logic). Inside
those islands, you can embed client Web Components for rich interactions that
shouldn't round-trip to the server (search, autocomplete, drag-and-drop).

---

## SvelteKit comparison

| What | SvelteKit | Lustre |
|---|---|---|
| SSR | Automatic. Kit renders `+page.svelte` on server. | Call `element.to_document_string` on server. |
| Pass data to page | `+page.server.ts` `load` function. | Embed JSON in `<script type="application/json">`. Client reads with `query_selector`. |
| Hydrate | Automatic. Kit's JS picks up where SSR left off. | Pass decoded JSON as flags to `lustre.start`. |
| API endpoint | `+server.ts` exports `GET`/`POST`. | `case` branch in Mist request handler. |
| Routing | File-based: `src/routes/`. | `modem` package + pattern matching on URI. |
| Components | `.svelte` files with props and events. | Real Web Components. Attributes + `event.emit`. |
| Server-only code | `+page.server.ts`. Client never sees it. | **Server components.** `update`/`view` run on BEAM. Browser gets DOM patches over WebSocket. |
| Real-time | Build WebSocket endpoint + Svelte store. | Server components do this automatically. Component is an OTP actor. |
| Shared types | `$lib` folder. Hope both sides agree, or use Zod. | `shared/` Gleam package. Compiler enforces it. |
| State | `$state` runes, stores. | Single `Model` type. Immutable. |
| Events | `on:click={() => count++}` | `event.on_click(UserClickedIncrement)` + `update` function. |
| Side effects | `await fetch(...)` in handlers. | Return `Effect` from `update`. Runtime executes it. |

---

## Step 1: Project setup

### Create the monorepo

```sh
mkdir anime && cd anime
gleam new shared
gleam new client
gleam new server
```

### `shared/gleam.toml`

```toml
name = "shared"
version = "1.0.0"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

### `client/gleam.toml`

```toml
name = "client"
version = "1.0.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
gleam_http = ">= 3.7.2 and < 5.0.0"
lustre = ">= 5.5.0 and < 6.0.0"
modem = ">= 2.0.0 and < 3.0.0"
plinth = ">= 0.5.0 and < 1.0.0"
rsvp = ">= 1.0.0 and < 2.0.0"
shared = { path = "../shared" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
lustre_dev_tools = ">= 2.0.0 and < 3.0.0"
```

### `server/gleam.toml`

```toml
name = "server"
version = "1.0.0"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_http = ">= 3.7.2 and < 5.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
gleam_otp = ">= 1.0.0 and < 2.0.0"
lustre = ">= 5.5.0 and < 6.0.0"
mist = ">= 5.0.0 and < 6.0.0"
shared = { path = "../shared" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

### Install dependencies

```sh
cd shared && gleam deps download && cd ..
cd client && gleam deps download && cd ..
cd server && gleam deps download && cd ..
```

---

## Step 2: Shared types

Both client and server import this package. If either side gets the type wrong,
it doesn't compile. No Zod, no runtime validation, no "hope."

### `shared/src/shared.gleam`

```gleam
import gleam/dynamic/decode
import gleam/json

pub type Anime {
  Anime(id: Int, title: String, episodes: Int)
}

pub fn anime_decoder() -> decode.Decoder(Anime) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use episodes <- decode.field("episodes", decode.int)
  decode.success(Anime(id:, title:, episodes:))
}

pub fn anime_list_decoder() -> decode.Decoder(List(Anime)) {
  decode.list(anime_decoder())
}

pub fn anime_to_json(anime: Anime) -> json.Json {
  json.object([
    #("id", json.int(anime.id)),
    #("title", json.string(anime.title)),
    #("episodes", json.int(anime.episodes)),
  ])
}

pub fn anime_list_to_json(items: List(Anime)) -> json.Json {
  json.array(items, anime_to_json)
}
```

### Verify

```sh
cd shared && gleam build && cd ..
```

---

## Step 3: Server — HTML + JSON API

In SvelteKit, the server is invisible. In Gleam you build it yourself. Every
route is a pattern match. Every response is data you construct.

### `server/src/server.gleam`

```gleam
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{None}
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import mist.{type Connection, type ResponseData}
import shared.{Anime}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["client.js"] -> serve_client_js()
        ["api", "anime"] -> serve_anime_api()
        _ ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.new()))
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
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Anime Tracker"),
        html.script(
          [attribute.type_("module"), attribute.src("/client.js")],
          "",
        ),
      ]),
      html.body(
        [attribute.styles([
          #("max-width", "40rem"),
          #("margin", "2rem auto"),
          #("font-family", "sans-serif"),
        ])],
        [
          // Hydration data: the client reads this before mounting.
          // SvelteKit does this automatically with `load`. Here it's explicit.
          html.script(
            [attribute.type_("application/json"), attribute.id("model")],
            json.to_string(shared.anime_list_to_json(anime_list)),
          ),
          html.div([attribute.id("app")], []),
        ],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
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
        mist.Bytes(
          bytes_tree.from_string(
            "client.js not found. Run: cd client && gleam run -m lustre/dev build --outdir=../server/priv/static",
          ),
        ),
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

fn get_anime_from_db() -> List(Anime) {
  // In a real app this queries a database. This code runs on the BEAM.
  // The client never sees it — like code in +page.server.ts.
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Steins;Gate", episodes: 24),
    Anime(id: 3, title: "Mob Psycho 100", episodes: 37),
  ]
}
```

### Run it

```sh
cd server && gleam run
```

- `http://localhost:3000` — HTML page (no client JS yet, so you see an empty div)
- `http://localhost:3000/api/anime` — JSON response

---

## Step 4: Client SPA

This is a `lustre.application` — the full-power version with managed side
effects. Every Lustre app is built on three functions:

```
init(flags) → #(Model, Effect(Msg))     -- initial state + startup effects
update(Model, Msg) → #(Model, Effect(Msg))  -- handle events
view(Model) → Element(Msg)              -- render HTML
```

The `Model` is all your state. `Msg` is every event that can happen. `Effect` is
a description of a side effect (HTTP request, timer, storage) that the runtime
executes for you. You never call `fetch` directly — you return an effect and the
runtime handles it.

### `client/src/client.gleam`

```gleam
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import plinth/browser/document
import plinth/browser/element as plinth_element
import rsvp
import shared.{type Anime}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  // Read hydration data embedded by the server.
  // SvelteKit does this automatically. Here we do it explicitly.
  let hydrated_anime =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(text) {
      json.parse(text, shared.anime_list_decoder())
      |> result.replace_error(Nil)
    })
    |> result.unwrap([])

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", hydrated_anime)
  Nil
}

// MODEL -----------------------------------------------------------------------
// All state in one place. No scattered variables, no stores.

type Model {
  Model(anime: List(Anime), loading: Bool)
}

fn init(flags: List(Anime)) -> #(Model, Effect(Msg)) {
  case flags {
    // Hydration data exists — use it immediately. No loading spinner.
    [_, ..] -> #(Model(anime: flags, loading: False), effect.none())
    // No hydration data — fetch from the API.
    [] -> #(Model(anime: [], loading: True), fetch_anime())
  }
}

// UPDATE ----------------------------------------------------------------------
// Every event is a variant of Msg. Name them Subject-Verb-Object:
// who sent it + what happened.

type Msg {
  ApiReturnedAnime(Result(List(Anime), rsvp.Error))
  UserClickedRefresh
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ApiReturnedAnime(Ok(anime)) -> #(
      Model(anime:, loading: False),
      effect.none(),
    )
    ApiReturnedAnime(Error(_)) -> #(
      Model(..model, loading: False),
      effect.none(),
    )
    UserClickedRefresh -> #(
      Model(..model, loading: True),
      fetch_anime(),
    )
  }
}

// EFFECTS ---------------------------------------------------------------------
// You describe what to fetch. The runtime does the fetching.
// The result comes back as a Msg through the normal update cycle.

fn fetch_anime() -> Effect(Msg) {
  rsvp.get(
    "/api/anime",
    rsvp.expect_json(shared.anime_list_decoder(), ApiReturnedAnime),
  )
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Anime Tracker")]),
    html.button(
      [event.on_click(UserClickedRefresh), attribute.disabled(model.loading)],
      [html.text(case model.loading {
        True -> "Loading..."
        False -> "Refresh"
      })],
    ),
    case model.anime {
      [] -> html.p([], [html.text("No anime loaded.")])
      items ->
        html.ul(
          [attribute.styles([#("list-style", "none"), #("padding", "0")])],
          list.map(items, view_anime),
        )
    },
  ])
}

fn view_anime(anime: Anime) -> Element(Msg) {
  html.li(
    [attribute.styles([
      #("padding", "0.75rem"),
      #("margin", "0.5rem 0"),
      #("background", "#f5f5f5"),
      #("border-radius", "0.25rem"),
    ])],
    [
      html.strong([], [html.text(anime.title)]),
      html.text(" - " <> int.to_string(anime.episodes) <> " episodes"),
    ],
  )
}
```

### Build and run

```sh
# Bundle client JS into server's static directory
cd client
gleam run -m lustre/dev build --outdir=../server/priv/static

# Start the server
cd ../server
gleam run
```

Open `http://localhost:3000`. The anime list appears instantly — hydrated from
server-embedded JSON. Click Refresh to see the effect cycle in action.

### The full cycle

```
1. Browser requests GET /
2. Server renders HTML with <script id="model"> containing JSON
3. Browser loads client.js
4. Client reads #model JSON, decodes it, passes as flags
5. init receives flags → Model with anime, loading: False, effect.none()
6. view renders immediately — no loading spinner
7. User clicks Refresh
8. update returns #(Model(loading: True), fetch_anime())
9. Runtime executes fetch_anime() → GET /api/anime
10. Server responds with JSON
11. rsvp decodes, wraps: ApiReturnedAnime(Ok([...]))
12. update receives it → #(Model(anime:, loading: False), effect.none())
13. view re-renders with new data
```

---

## Step 5: Custom effects

The `rsvp.get` call in Step 4 is a convenience wrapper. Under the hood, all
effects use `effect.from`. There are three patterns.

### Pattern 1: Effect with dispatch (get data back)

Read from localStorage and send the result as a message:

```gleam
fn read_storage(key: String, to_msg: fn(Result(String, Nil)) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    do_read(key)
    |> to_msg
    |> dispatch
  })
}

@external(javascript, "./ffi.mjs", "read")
fn do_read(key: String) -> Result(String, Nil) {
  Error(Nil)
}
```

`effect.from` takes a callback that receives a `dispatch` function. Call
`dispatch(msg)` to send a message back into the update loop.

### Pattern 2: Fire-and-forget (no data back)

Write to localStorage. No message needed:

```gleam
fn write_storage(key: String, value: String) -> Effect(msg) {
  effect.from(fn(_dispatch) {
    do_write(key, value)
  })
}

@external(javascript, "./ffi.mjs", "write")
fn do_write(key: String, value: String) -> Nil {
  Nil
}
```

The `_dispatch` is ignored. The effect runs, nothing comes back.

### Pattern 3: Batching multiple effects

Run several effects at once with `effect.batch`:

```gleam
fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedRefresh -> #(
      Model(..model, loading: True),
      effect.batch([
        fetch_anime(),
        write_storage("last_refresh", "now"),
      ]),
    )
    // ...
  }
}
```

Both effects execute. One dispatches a message, one doesn't. Both run.

### The FFI file

Create `client/src/ffi.mjs`:

```javascript
export function read(key) {
  const value = localStorage.getItem(key);
  if (value !== null) return { 0: value };  // Ok(value)
  return { isOk: false };                   // Error(Nil)
}

export function write(key, value) {
  localStorage.setItem(key, value);
}
```

---

## Step 6: Client-side routing

In SvelteKit, routing is file-based. In Lustre, you use the `modem` package to
intercept link clicks and push browser history. You pattern match on the URL.

### Add routing to the client

This shows the pattern. Integrate it into your existing `client.gleam`:

```gleam
import gleam/int
import gleam/uri
import modem

// Add to your Model:
type Route {
  Home
  AnimeList
  AnimeDetail(id: Int)
  NotFound
}

// Add route to Model:
type Model {
  Model(route: Route, anime: List(Anime), loading: Bool)
}

// Wire modem into init. It returns an effect that listens for URL changes:
fn init(flags: List(Anime)) -> #(Model, Effect(Msg)) {
  let initial_model = case flags {
    [_, ..] -> Model(route: Home, anime: flags, loading: False)
    [] -> Model(route: Home, anime: [], loading: True)
  }
  let effects = case flags {
    [_, ..] -> modem.init(on_url_change)
    [] -> effect.batch([fetch_anime(), modem.init(on_url_change)])
  }
  #(initial_model, effects)
}

fn on_url_change(uri: uri.Uri) -> Msg {
  UserNavigatedTo(parse_route(uri))
}

fn parse_route(uri: uri.Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> Home
    ["anime"] -> AnimeList
    ["anime", id] ->
      case int.parse(id) {
        Ok(id) -> AnimeDetail(id)
        Error(_) -> NotFound
      }
    _ -> NotFound
  }
}

// Add to Msg:
type Msg {
  // ... existing messages
  UserNavigatedTo(Route)
}

// Handle in update:
fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserNavigatedTo(route) -> #(Model(..model, route:), effect.none())
    // ... existing handlers
  }
}

// Route in view:
fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.nav([], [
      html.a([attribute.href("/")], [html.text("Home")]),
      html.text(" | "),
      html.a([attribute.href("/anime")], [html.text("Anime")]),
    ]),
    case model.route {
      Home -> view_home(model)
      AnimeList -> view_anime_list(model)
      AnimeDetail(id) -> view_anime_detail(model, id)
      NotFound -> html.text("404")
    },
  ])
}
```

`modem` intercepts `<a>` tag clicks and pushes browser history. No special link
component needed — just use `html.a` with `attribute.href`.

---

## Step 7: Components — real Web Components

This is the key concept from Lustre. In Elm, components are considered bad
(encapsulated state = objects = bad). But on the BEAM, programs are organized
entirely around actors — encapsulated state that receives messages. Lustre
embraces this.

A Lustre component is a **real Web Component** (Custom Element). It has:
- **Attributes** — parent sets strings on the element (parent → child)
- **Properties** — parent sets rich JS values (parent → child)
- **Events** — component emits DOM events (child → parent)

### Build a rating component

Create `client/src/rating.gleam`:

```gleam
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// PUBLIC API ------------------------------------------------------------------
// These are what consumers of your component use.

/// Register the component as a custom element called <anime-rating>.
pub fn register() -> Result(Nil, lustre.Error) {
  let comp =
    lustre.component(init, update, view, [
      // Listen for changes to the "value" attribute.
      // When the parent sets <anime-rating value="7">, this decoder runs.
      // If it succeeds, the message is sent to update.
      component.on_attribute_change("value", fn(value) {
        int.parse(value) |> result.map(ParentChangedValue)
      }),
    ])

  lustre.register(comp, "anime-rating")
}

/// Render the component element. Used by the parent app.
pub fn element(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("anime-rating", attributes, [])
}

/// Set the rating value from the parent.
pub fn value(val: Int) -> Attribute(msg) {
  attribute.value(int.to_string(val))
}

/// Listen for rating changes emitted by the component.
pub fn on_change(handler: fn(Int) -> msg) -> Attribute(msg) {
  event.on("change", {
    decode.at(["detail"], decode.int) |> decode.map(handler)
  })
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(score: Int)
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(score: 5), effect.none())
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ParentChangedValue(Int)
  UserClickedUp
  UserClickedDown
  UserClickedSubmit
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentChangedValue(value) -> #(Model(score: value), effect.none())
    UserClickedUp -> #(
      Model(score: int.min(model.score + 1, 10)),
      effect.none(),
    )
    UserClickedDown -> #(
      Model(score: int.max(model.score - 1, 1)),
      effect.none(),
    )
    UserClickedSubmit -> #(
      model,
      // Emit a real DOM event. The parent can listen with on_change.
      // The data goes in event.detail — just like a native HTML element.
      event.emit("change", json.int(model.score)),
    )
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let score = int.to_string(model.score)

  html.div(
    [attribute.styles([
      #("display", "flex"),
      #("align-items", "center"),
      #("gap", "0.5rem"),
      #("padding", "1rem"),
      #("border", "1px solid #ccc"),
      #("border-radius", "0.5rem"),
    ])],
    [
      html.span([], [html.text("Rating: ")]),
      html.button([event.on_click(UserClickedDown)], [html.text("-")]),
      html.span(
        [attribute.styles([
          #("font-size", "1.5rem"),
          #("min-width", "2ch"),
          #("text-align", "center"),
        ])],
        [html.text(score)],
      ),
      html.button([event.on_click(UserClickedUp)], [html.text("+")]),
      html.span([], [html.text(" / 10  ")]),
      html.button([event.on_click(UserClickedSubmit)], [html.text("Save")]),
    ],
  )
}
```

### Use it from the parent app

In `client/src/client.gleam`, add to `main`:

```gleam
pub fn main() {
  // Register the Web Component before starting the app
  let assert Ok(_) = rating.register()

  // ... rest of main
}
```

And in your view, use it like any HTML element:

```gleam
import rating

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    // ... anime list ...
    html.hr([]),
    html.h2([], [html.text("Rate this anime")]),
    rating.element([
      rating.value(model.current_rating),
      rating.on_change(UserSavedRating),
    ]),
  ])
}
```

The component is a real Custom Element. In the browser DOM you'll see
`<anime-rating value="5">`. You can set attributes from JavaScript. You can
attach event listeners. It behaves exactly like a native HTML element.

### How communication works

```
Parent App                          <anime-rating> Component
    |                                      |
    |-- attribute.value("7") ------------->|
    |                                      | on_attribute_change decodes "7"
    |                                      | update(model, ParentChangedValue(7))
    |                                      | view re-renders with score = 7
    |                                      |
    |                                      | User clicks [Save]
    |                                      | update returns event.emit("change", 7)
    |<-- "change" event (detail: 7) -------|
    | on_change handler fires              |
    | update(model, UserSavedRating(7))    |
```

This is the same model as native HTML. An `<input>` has attributes (`type`,
`value`) and emits events (`input`, `change`). Your component has attributes
(`value`) and emits events (`change`). Same pattern, custom behavior.

---

## Step 8: Server component — same code, different runtime

Here's the punchline. Take the **same component** from Step 7. Don't change the
application code. Just change how you start it.

On the client: `lustre.register(component, "anime-rating")` — runs in JavaScript.
On the server: `lustre.start_server_component(component, Nil)` — runs as an OTP
actor on the BEAM.

### Create the server-side rating component

Create `server/src/rating.gleam`:

```gleam
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// The SAME component constructor as the client version.
// The only difference: this one will be started with start_server_component
// instead of register.
pub fn component() -> lustre.App(_, Model, Msg) {
  lustre.component(init, update, view, [
    component.on_attribute_change("value", fn(value) {
      int.parse(value) |> result.map(ParentChangedValue)
    }),
  ])
}

pub fn value(val: Int) -> Attribute(msg) {
  attribute.value(int.to_string(val))
}

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model(score: Int)
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(score: 5), effect.none())
}

// UPDATE ----------------------------------------------------------------------
// This runs on the BEAM. It could query a database, talk to other OTP
// processes, read files. The browser never sees this code.

pub opaque type Msg {
  ParentChangedValue(Int)
  UserClickedUp
  UserClickedDown
  UserClickedSubmit
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentChangedValue(value) -> #(Model(score: value), effect.none())
    UserClickedUp -> #(
      Model(score: int.min(model.score + 1, 10)),
      effect.none(),
    )
    UserClickedDown -> #(
      Model(score: int.max(model.score - 1, 1)),
      effect.none(),
    )
    UserClickedSubmit -> #(
      model,
      // event.emit works for server components too.
      // The event is forwarded to the client over WebSocket.
      event.emit("change", json.int(model.score)),
    )
  }
}

// VIEW ------------------------------------------------------------------------
// This runs on the BEAM. The browser receives DOM patches, not this code.

fn view(model: Model) -> Element(Msg) {
  let score = int.to_string(model.score)

  html.div(
    [attribute.styles([
      #("display", "flex"),
      #("align-items", "center"),
      #("gap", "0.5rem"),
      #("padding", "1rem"),
      #("border", "1px solid #ccc"),
      #("border-radius", "0.5rem"),
    ])],
    [
      html.span([], [html.text("Rating: ")]),
      html.button([event.on_click(UserClickedDown)], [html.text("-")]),
      html.span(
        [attribute.styles([
          #("font-size", "1.5rem"),
          #("min-width", "2ch"),
          #("text-align", "center"),
        ])],
        [html.text(score)],
      ),
      html.button([event.on_click(UserClickedUp)], [html.text("+")]),
      html.span([], [html.text(" / 10  ")]),
      html.button([event.on_click(UserClickedSubmit)], [html.text("Save")]),
    ],
  )
}
```

### Wire the WebSocket

Update `server/src/server.gleam` — add the server component routes and plumbing:

```gleam
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
import rating
import shared.{Anime}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["client.js"] -> serve_client_js()
        ["api", "anime"] -> serve_anime_api()
        ["lustre", "runtime.mjs"] -> serve_lustre_runtime()
        ["ws", "rate"] -> serve_rating_ws(req)
        _ ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

// ROUTE: GET / ----------------------------------------------------------------

fn serve_html() -> Response(ResponseData) {
  let anime_list = get_anime_from_db()

  let page =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Anime Tracker"),
        html.script(
          [attribute.type_("module"), attribute.src("/client.js")],
          "",
        ),
        // Load the server component client runtime (~10kB).
        // This registers <lustre-server-component> as a custom element.
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
      ]),
      html.body(
        [attribute.styles([
          #("max-width", "40rem"),
          #("margin", "2rem auto"),
          #("font-family", "sans-serif"),
        ])],
        [
          html.script(
            [attribute.type_("application/json"), attribute.id("model")],
            json.to_string(shared.anime_list_to_json(anime_list)),
          ),
          html.div([attribute.id("app")], []),
          html.hr([]),
          html.h2([], [html.text("Rate this anime")]),
          // This custom element opens a WebSocket to /ws/rate.
          // The rating UI runs on the BEAM. The browser just renders patches.
          server_component.element(
            [
              server_component.route("/ws/rate"),
              // Set initial value via attribute — the component's
              // on_attribute_change handler will pick this up.
              rating.value(5),
            ],
            [],
          ),
        ],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}

// ROUTE: GET /client.js -------------------------------------------------------

fn serve_client_js() -> Response(ResponseData) {
  case mist.send_file("priv/static/client.js", offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(_) ->
      response.new(404)
      |> response.set_body(
        mist.Bytes(
          bytes_tree.from_string(
            "client.js not found. Run: cd client && gleam run -m lustre/dev build --outdir=../server/priv/static",
          ),
        ),
      )
  }
}

// ROUTE: GET /api/anime -------------------------------------------------------

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

// ROUTE: GET /lustre/runtime.mjs ----------------------------------------------
// Serves the ~10kB client runtime that Lustre ships. It registers
// <lustre-server-component> as a custom element and handles WebSocket
// communication + DOM patching.

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

// ROUTE: WS /ws/rate ----------------------------------------------------------

fn serve_rating_ws(req: Request(Connection)) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: init_rating_socket,
    handler: loop_rating_socket,
    on_close: close_rating_socket,
  )
}

// -- WebSocket plumbing -------------------------------------------------------
// This is the same pattern for EVERY server component. Copy it.

type RatingSocket {
  RatingSocket(
    runtime: lustre.Runtime(rating.Msg),
    self: Subject(server_component.ClientMessage(rating.Msg)),
  )
}

type RatingSocketMsg =
  server_component.ClientMessage(rating.Msg)

fn init_rating_socket(
  _connection,
) -> #(RatingSocket, Option(Selector(RatingSocketMsg))) {
  // 1. Create the component (same constructor as client version)
  let app = rating.component()

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

// "DATABASE" ------------------------------------------------------------------

fn get_anime_from_db() -> List(Anime) {
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Steins;Gate", episodes: 24),
    Anime(id: 3, title: "Mob Psycho 100", episodes: 37),
  ]
}
```

### What goes over the wire

On first connect, the server sends the full VDOM as JSON:

```json
["element", "div", {"style": "display:flex;..."}, [
  ["element", "span", {}, [["text", "Rating: "]]],
  ["element", "button", {"data-lustre-on-click": "0-0-1"}, [["text", "-"]]],
  ...
]]
```

When the user clicks `[+]`, the browser sends:

```json
{"type": "event", "path": "0-0-3", "event": "click", "data": null}
```

The server runs `update`, diffs the views, sends back only what changed:

```json
{"type": "reconcile", "patches": [{"path": "0-0-2-0", "action": "replace_text", "value": "6"}]}
```

These payloads are tiny. The browser applies the patch to the real DOM.

### Multi-user: share one actor

To let multiple browser tabs (or users) see the same component state, create the
actor once and pass it to every WebSocket connection:

```gleam
pub fn main() {
  // Create ONE component at app startup
  let app = rating.component()
  let assert Ok(shared_runtime) = lustre.start_server_component(app, Nil)

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        // ...
        ["ws", "rate"] -> serve_rating_ws(req, shared_runtime)
        // ...
      }
    }
    |> mist.new
    // ...
}
```

Now every connected client sees the same score. When one user clicks `[+]`,
everyone sees the update. Real-time collaboration for free.

### Build and run

```sh
cd client
gleam run -m lustre/dev build --outdir=../server/priv/static
cd ../server
gleam run
```

Open `http://localhost:3000`. The anime list (SPA, client-side) and the rating
widget (server component, BEAM-side) both work on the same page.

---

## Step 9: The architecture vision

From Hayleigh's talk: imagine an admin dashboard with a table of thousands of
users.

**Traditional approach:**

```
Create REST endpoint → serialize JSON request → send over network →
deserialize → interpret pagination/filtering → database query → serialize
JSON response → send back → deserialize → render HTML
```

**With a server component:**

```
Database query → render HTML
```

That's it. No API, no serialization, no transport. You write the database query
and the view function. The runtime handles everything in between.

### When to use which pattern

| Pattern | When | Why |
|---|---|---|
| **Client SPA** | Most of your app | Interactive, offline-capable, no server round-trips for UI |
| **Server component** | Database access, real-time, secure logic | No API boilerplate, tiny client footprint (~10kB), direct BEAM access |
| **Client component inside server component** | Rich interactions (search, autocomplete, drag-and-drop) | These shouldn't round-trip to the server for every keystroke |

The vision for large apps:

```
┌─────────────────────────────────────────────┐
│  Client SPA (JavaScript)                    │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │  Server Component island (BEAM)      │   │
│  │                                      │   │
│  │  ┌─────────────────────────────┐     │   │
│  │  │ Client Component (JS)       │     │   │
│  │  │ (rich search, autocomplete) │     │   │
│  │  └─────────────────────────────┘     │   │
│  │                                      │   │
│  │  Database table, real-time feed...   │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  Regular SPA content...                     │
└─────────────────────────────────────────────┘
```

Your client SPA handles navigation, layout, and most interactions. Server
component islands handle things that benefit from being close to the backend.
Client components inside those islands handle things that need instant feedback.

---

## Step 10: Patterns and conventions

### Message naming

Use **Subject-Verb-Object** to describe what happened:

```gleam
type Msg {
  ApiReturnedAnime(Result(List(Anime), rsvp.Error))
  UserClickedRefresh
  UserTypedSearchQuery(String)
  UserSubmittedForm
  UserNavigatedTo(Route)
  UserSavedRating(Int)
  StorageReturnedFavorites(Result(List(Int), Nil))
}
```

### View functions over components

Most of the time, use plain functions that return `Element(msg)`:

```gleam
fn view_anime_card(anime: Anime) -> Element(msg) {
  html.div([attribute.class("card")], [
    html.h2([], [html.text(anime.title)]),
    html.p([], [html.text(int.to_string(anime.episodes) <> " episodes")]),
  ])
}

// Use it:
html.div([], list.map(model.anime, view_anime_card))
```

Only reach for `lustre.component` / `lustre.register` when you need:
- Encapsulated state (the component manages its own model)
- Web Component interop (use from JavaScript, other frameworks)
- Server component capability (run on the BEAM)
- Attribute/event communication boundary

### Conditional rendering

```gleam
// Show or hide
case model.error {
  option.Some(err) -> html.div([attribute.class("error")], [html.text(err)])
  option.None -> element.none()
}

// Branch on state
case model.loading {
  True -> html.p([], [html.text("Loading...")])
  False -> html.ul([], list.map(model.items, view_item))
}
```

`element.none()` renders nothing — use it instead of hiding with CSS.

### Keyed lists

When rendering lists that can reorder, use keyed elements for performance:

```gleam
import lustre/element/keyed

keyed.ul([], list.map(model.anime, fn(item) {
  #(int.to_string(item.id), view_anime_card(item))
}))
```

The key (first element of tuple) tells Lustre which items moved vs which were
added/removed. Without keys, the entire list re-renders on change.

### Component communication summary

| Direction | Mechanism | API |
|---|---|---|
| Parent → child (string) | Attributes | `component.on_attribute_change("name", decoder)` |
| Parent → child (rich data) | Properties | `component.on_property_change("name", decoder)` |
| Child → parent | Events | `event.emit("name", json_data)` |
| Ancestor → descendant | Context | `effect.provide("key", json)` + `component.on_context_change("key", decoder)` |

---

## Step 11: Production

### Bundle the client (minified)

```sh
cd client
gleam run -m lustre/dev build --minify --outdir=../server/priv/static
```

### Export the server as an Erlang release

```sh
cd server
gleam export erlang-shipment
```

This creates `build/erlang-shipment/` with everything needed to run the server
without Gleam installed.

### Docker

```dockerfile
ARG GLEAM_VERSION=v1.13.0

FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine AS builder
COPY ./shared /build/shared
COPY ./client /build/client
COPY ./server /build/server
RUN cd /build/shared && gleam deps download
RUN cd /build/client && gleam deps download && \
    gleam add --dev lustre_dev_tools && \
    gleam run -m lustre/dev build --minify --outdir=../server/priv/static
RUN cd /build/server && gleam deps download && gleam export erlang-shipment

FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine
COPY --from=builder /build/server/build/erlang-shipment /app
WORKDIR /app
ENV HOST=0.0.0.0
ENV PORT=8080
EXPOSE 8080
CMD ["./entrypoint.sh", "run"]
```

Deploy to Fly.io, Railway, Render, or any Docker host.

---

## File recap

```
shared/gleam.toml           Dependencies: gleam_json
shared/src/shared.gleam      Anime type + decoder + encoder

client/gleam.toml            Dependencies: lustre, rsvp, plinth, modem, shared; target=javascript
client/src/client.gleam      SPA: hydration + REST fetch + routing
client/src/rating.gleam      Client Web Component: <anime-rating> (optional)
client/src/ffi.mjs           localStorage FFI for custom effects

server/gleam.toml            Dependencies: mist, lustre, gleam_otp, shared
server/src/server.gleam      5 routes: HTML, client.js, API, runtime, WebSocket
server/src/rating.gleam      Server component: same code as client, runs on BEAM
```

---

## Useful packages

| Package | Purpose |
|---|---|
| [lustre](https://hexdocs.pm/lustre/) | Framework core |
| [lustre_dev_tools](https://hexdocs.pm/lustre_dev_tools/) | Dev server, bundler |
| [rsvp](https://hexdocs.pm/rsvp/) | HTTP requests (effects) |
| [modem](https://hexdocs.pm/modem/) | Client-side routing |
| [plinth](https://hexdocs.pm/plinth/) | Browser/Node.js platform APIs |
| [mist](https://hexdocs.pm/mist/) | HTTP/WebSocket server |
| [wisp](https://hexdocs.pm/wisp/) | Server-side web framework (alternative to raw Mist) |
| [gleam_json](https://hexdocs.pm/gleam_json/) | JSON encoding/decoding |
| [storail](https://hexdocs.pm/storail/) | Simple file-based database |
| [group_registry](https://hexdocs.pm/group_registry/) | Pub/sub for server components |
