# Learn Lustre Step by Step

A hands-on walkthrough that teaches Lustre from zero, one concept at a time.
Each step introduces exactly **one** new idea. By the end you'll have a full-stack
app with SSR, hydration, REST, and server components — and you'll understand every
line.

If you're coming from SvelteKit, each step includes an analogy to what you already
know.

---

## How to use this guide

- Do the steps in order. Each one builds on the last.
- Type the code yourself. Don't copy-paste.
- Every step ends with something you can see in the browser or terminal.
- Code diffs show only what changed from the previous step.

---

## Phase 1: Learn MVU in the browser

We start with just the `client/` package. No server, no shared types. Pure
browser-side Lustre.

---

### Step 1: Static rendering with `lustre.element`

**What you'll learn:** How Lustre renders HTML. No state, no events, no logic.

**SvelteKit equivalent:** A `.svelte` file with only HTML in the template, no
`<script>` block.

#### Set up the client package

Edit `client/gleam.toml` — replace the entire file:

```toml
name = "client"
version = "1.0.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
lustre = ">= 5.5.0 and < 6.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
lustre_dev_tools = ">= 2.0.0 and < 3.0.0"
```

Two things to notice:
- `target = "javascript"` — this compiles to JS that runs in the browser.
- `lustre_dev_tools` in dev-dependencies — gives us a dev server with hot reload.

#### Write the code

Edit `client/src/client.gleam` — replace the entire file:

```gleam
import lustre
import lustre/element/html

pub fn main() {
  let app = lustre.element(
    html.div([], [
      html.h1([], [html.text("Anime Tracker")]),
      html.p([], [html.text("Welcome. Nothing interactive yet.")]),
    ])
  )
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
```

#### Run it

```sh
cd client
gleam deps download
gleam run -m lustre/dev start
```

Open `http://localhost:1234`. You should see:

```
Anime Tracker
Welcome. Nothing interactive yet.
```

#### What just happened

`lustre.element` is the simplest kind of Lustre app. Its signature:

```gleam
fn element(view: Element(msg)) -> App(start_args, Nil, msg)
```

You give it a chunk of HTML, it renders it into the DOM node matching `"#app"`.
No state. No events. Just HTML.

The HTML functions follow a consistent pattern:

```gleam
html.tag(attributes, children)
```

- `html.div([], [...])` — a `<div>` with no attributes and some children.
- `html.text("...")` — a text node. This is how you put text on the page.

`lustre/dev start` gives you a dev server with a page that already has
`<div id="app"></div>` in it, so `lustre.start(app, "#app", Nil)` finds that
element and mounts the app there.

---

### Step 2: Add state with `lustre.simple`

**What you'll learn:** The Model-View-Update pattern. State, messages, and the
update loop.

**SvelteKit equivalent:** A `.svelte` file with `let count = $state(0)` and an
`on:click` handler.

#### Change the code

Replace `client/src/client.gleam` entirely:

```gleam
import gleam/int
import lustre
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------
// All your state lives here. One type, one value. No scattered variables.

type Model {
  Model(count: Int)
}

fn init(_flags) -> Model {
  Model(count: 0)
}

// UPDATE ----------------------------------------------------------------------
// Every event that can happen is a variant of Msg.
// update receives the current model and the message, returns the new model.

type Msg {
  UserClickedIncrement
  UserClickedDecrement
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserClickedIncrement -> Model(count: model.count + 1)
    UserClickedDecrement -> Model(count: model.count - 1)
  }
}

// VIEW ------------------------------------------------------------------------
// A pure function from Model to HTML. Runs every time the model changes.

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Counter")]),
    html.button([event.on_click(UserClickedDecrement)], [html.text("-")]),
    html.span([], [html.text(" " <> int.to_string(model.count) <> " ")]),
    html.button([event.on_click(UserClickedIncrement)], [html.text("+")]),
  ])
}
```

#### Run it

If the dev server is still running, it should auto-reload. Otherwise:

```sh
cd client
gleam run -m lustre/dev start
```

Open `http://localhost:1234`. Click the `+` and `-` buttons. The count changes.

#### What just happened

`lustre.simple` is the second tier of Lustre app:

```gleam
fn simple(
  init: fn(start_args) -> Model,
  update: fn(Model, Msg) -> Model,
  view: fn(Model) -> Element(Msg),
) -> App(start_args, Model, Msg)
```

The three pieces:

| Piece | What it does | Svelte equivalent |
|---|---|---|
| `init` | Creates the initial model | `let count = $state(0)` |
| `update` | Handles events, returns new model | `on:click={() => count += 1}` |
| `view` | Renders the model to HTML | The HTML template |

The flow is a loop:

```
init() → Model
           ↓
         view(Model) → HTML on screen
           ↓
         user clicks → Msg
           ↓
         update(Model, Msg) → new Model
           ↓
         view(new Model) → updated HTML
           ↓
         (repeat)
```

In SvelteKit, events mutate state directly: `count += 1`. In Lustre, events
become **messages** (data, not functions), and `update` decides what to do with
them. This seems like extra work now, but it's what makes effects, testing, and
server components possible.

The naming convention for messages is **Subject-Verb-Object**: `UserClickedIncrement`
describes what happened, not what to do. This matters when your app grows.

---

### Step 3: Upgrade to `lustre.application` (with effects)

**What you'll learn:** The `Effect` type — how Lustre handles side effects.
This is the big conceptual difference from SvelteKit.

**SvelteKit equivalent:** The difference between clicking a button that changes
local state vs. clicking a button that calls `fetch()`. In SvelteKit you just
`await fetch(...)` inside the handler. In Lustre you **describe** the side effect
and the runtime executes it.

#### Change the code

Replace `client/src/client.gleam` entirely:

```gleam
import gleam/int
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(count: Int)
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserClickedIncrement
  UserClickedDecrement
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedIncrement -> #(Model(count: model.count + 1), effect.none())
    UserClickedDecrement -> #(Model(count: model.count - 1), effect.none())
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Counter")]),
    html.button([event.on_click(UserClickedDecrement)], [html.text("-")]),
    html.span([], [html.text(" " <> int.to_string(model.count) <> " ")]),
    html.button([event.on_click(UserClickedIncrement)], [html.text("+")]),
  ])
}
```

#### Run it

Same as before — the counter works identically. The difference is invisible
to the user but fundamental to how the app is structured.

#### What just happened

`lustre.application` is the full-power Lustre app:

```gleam
fn application(
  init: fn(start_args) -> #(Model, Effect(Msg)),
  update: fn(Model, Msg) -> #(Model, Effect(Msg)),
  view: fn(Model) -> Element(Msg),
) -> App(start_args, Model, Msg)
```

Compare the signatures:

| | `lustre.simple` | `lustre.application` |
|---|---|---|
| `init` returns | `Model` | `#(Model, Effect(Msg))` |
| `update` returns | `Model` | `#(Model, Effect(Msg))` |

The second element of the tuple is an `Effect(Msg)`. An effect is a description
of a side effect — an HTTP request, a timer, a localStorage read. You don't
execute it. You return it. The Lustre runtime executes it for you.

Right now we return `effect.none()` everywhere, which means "do nothing." That's
fine. The important thing is the **slot** exists. When we need to make HTTP
requests later, we won't restructure anything. We'll just replace `effect.none()`
with a real effect.

This is the key difference from SvelteKit:

| SvelteKit | Lustre |
|---|---|
| `await fetch(...)` in a handler | Return `Effect` from `update`, runtime handles it |
| Side effects are mixed into your code | Side effects are **separated** from your logic |
| Hard to test (mocking fetch) | Easy to test (check what effect was returned) |

Think of it like this: in SvelteKit, your event handler is a chef who cooks the
meal AND serves it. In Lustre, your `update` function writes the order on a
ticket and hands it to the kitchen (the runtime). The food still gets made, but
the responsibilities are separated.

---

## Phase 2: Create shared types

Now we start building toward the full-stack app. The first thing we need is a
shared language between client and server.

---

### Step 4: Define the Anime type in `shared/`

**What you'll learn:** How to share types across client and server with compile-time
safety.

**SvelteKit equivalent:** Putting types in `$lib/types.ts`. But in SvelteKit,
there's nothing stopping the server from returning `{ name: "Bebop" }` while the
client expects `{ title: "Bebop" }`. You'd need Zod or similar. In Gleam, if they
disagree, it won't compile.

#### Set up the shared package

Edit `shared/gleam.toml` — replace the entire file:

```toml
name = "shared"
version = "1.0.0"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

No target specified — this package works on both Erlang and JavaScript.

#### Write the code

Edit `shared/src/shared.gleam` — replace the entire file:

```gleam
import gleam/dynamic/decode
import gleam/json

// -- Anime type used by both client and server --------------------------------

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

#### Run it

```sh
cd shared
gleam deps download
gleam build
```

No errors? Good. There's nothing to see in the browser yet — this is a library
package, not an application.

#### What just happened

You created four things:

1. **`Anime` type** — a record with three fields. Both client and server will use
   this exact type. If the server adds a field and the client doesn't update,
   the compiler catches it.

2. **`anime_decoder()`** — reads JSON and produces an `Anime`. The `use` syntax
   is Gleam's way of chaining operations. Each `decode.field` says "look for this
   key, decode it as this type." If any field is missing or the wrong type,
   decoding fails — no runtime type errors, no `undefined is not a function`.

3. **`anime_list_decoder()`** — wraps the single decoder in `decode.list` so it
   can decode `[{...}, {...}, ...]`.

4. **`anime_to_json()` / `anime_list_to_json()`** — the reverse direction. Takes
   an `Anime` and produces JSON.

The SvelteKit comparison:

| SvelteKit | Lustre/Gleam |
|---|---|
| `$lib/types.ts` with TypeScript interfaces | `shared/src/shared.gleam` with Gleam types |
| Types erased at runtime | Types enforced at compile time across packages |
| Zod schema for validation | `decode.Decoder` built into the type system |
| Hope that API matches types | Compiler guarantees it |

---

## Phase 3: Build the server

Now we leave the browser and write Gleam that runs on the Erlang VM.

---

### Step 5: Minimal Mist server — serve one HTML page

**What you'll learn:** How to build an HTTP server in Gleam. In SvelteKit the
server is invisible — `npm run dev` just works. In Gleam you build it yourself.
That means you understand it.

**SvelteKit equivalent:** What SvelteKit does behind the scenes with Vite + its
Node adapter. You're doing it explicitly.

#### Set up the server package

Edit `server/gleam.toml` — replace the entire file:

```toml
name = "server"
version = "1.0.0"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_http = ">= 3.7.2 and < 5.0.0"
lustre = ">= 5.5.0 and < 6.0.0"
mist = ">= 5.0.0 and < 6.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

We need `lustre` on the server because we use its HTML functions to build the
page. Same functions as the client, different runtime.

#### Write the code

Edit `server/src/server.gleam` — replace the entire file:

```gleam
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import mist.{type Connection, type ResponseData}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
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
  let page =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Anime Tracker"),
      ]),
      html.body(
        [attribute.styles([
          #("max-width", "40rem"),
          #("margin", "2rem auto"),
          #("font-family", "sans-serif"),
        ])],
        [
          html.h1([], [html.text("Anime Tracker")]),
          html.p([], [html.text("Served from the BEAM.")]),
        ],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}
```

#### Run it

```sh
cd server
gleam deps download
gleam run
```

Open `http://localhost:3000`. You should see:

```
Anime Tracker
Served from the BEAM.
```

#### What just happened

Let's break down the server piece by piece.

**The request handler** is a function that takes a `Request` and returns a
`Response`. Mist calls it for every incoming HTTP request.

```gleam
fn(req: Request(Connection)) -> Response(ResponseData) {
  case request.path_segments(req) {
    [] -> serve_html()       // GET /
    _ -> response.new(404)   // everything else
  }
}
```

`request.path_segments` splits the URL path into a list: `/` becomes `[]`,
`/api/anime` becomes `["api", "anime"]`. You pattern match on it. That's your
router.

**Building HTML** uses the same Lustre functions as the client. `html.h1`,
`html.p`, `html.text` — identical. But instead of mounting it in the browser
with `lustre.start`, we convert it to a string with `element.to_document_string_tree`
and send it as the response body.

**`process.sleep_forever()`** keeps the Erlang VM alive. Without it, `main` would
return and the server would stop.

In SvelteKit, all of this is hidden. You write `+page.svelte` and the framework
handles the server, routing, and HTML rendering. Here you see every piece, which
means you can control every piece.

---

### Step 6: Add a JSON API route

**What you'll learn:** How to add API endpoints. The server now returns real
data using the shared `Anime` type.

**SvelteKit equivalent:** Creating `src/routes/api/anime/+server.ts` with a
`GET` handler.

#### Update dependencies

Edit `server/gleam.toml` — add `gleam_json` and `shared`:

```toml
name = "server"
version = "1.0.0"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_http = ">= 3.7.2 and < 5.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
lustre = ">= 5.5.0 and < 6.0.0"
mist = ">= 5.0.0 and < 6.0.0"
shared = { path = "../shared" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

Two new things:
- `gleam_json` — for encoding data to JSON strings.
- `shared = { path = "../shared" }` — local path dependency. The server now uses
  the same `Anime` type as the client will.

#### Update the code

Edit `server/src/server.gleam` — replace the entire file:

```gleam
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
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
  let page =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Anime Tracker"),
      ]),
      html.body(
        [attribute.styles([
          #("max-width", "40rem"),
          #("margin", "2rem auto"),
          #("font-family", "sans-serif"),
        ])],
        [
          html.h1([], [html.text("Anime Tracker")]),
          html.p([], [html.text("Served from the BEAM.")]),
        ],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
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

// "DATABASE" ------------------------------------------------------------------

fn get_anime_from_db() -> List(Anime) {
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Steins;Gate", episodes: 24),
    Anime(id: 3, title: "Mob Psycho 100", episodes: 37),
  ]
}
```

#### Run it

```sh
cd server
gleam deps download
gleam run
```

Open `http://localhost:3000/api/anime`. You should see:

```json
[{"id":1,"title":"Cowboy Bebop","episodes":26},{"id":2,"title":"Steins;Gate","episodes":24},{"id":3,"title":"Mob Psycho 100","episodes":37}]
```

#### What just happened

We added one new route and one new function.

**The route** is just another pattern in the `case` expression:

```gleam
["api", "anime"] -> serve_anime_api()
```

When the browser requests `/api/anime`, the path splits into `["api", "anime"]`
and this branch matches.

**`serve_anime_api`** does four things in a pipeline:

```gleam
get_anime_from_db()          // 1. Get the data (List(Anime))
|> shared.anime_list_to_json // 2. Convert to JSON value
|> json.to_string            // 3. Serialize to string
|> bytes_tree.from_string    // 4. Convert to bytes for the response
```

Notice that `shared.anime_list_to_json` is the function we wrote in Step 4. The
server and client share the same encoding logic. If you change the Anime type
in `shared/`, both sides must update or the compiler stops you.

**`get_anime_from_db`** is a hardcoded list. In a real app this would query a
database. The important thing is that this code runs on the BEAM and the client
never sees it — just like code in SvelteKit's `+page.server.ts`.

---

## Phase 4: Connect client to server

Now we connect the client SPA to the server's API. This is where effects become
real.

---

### Step 7: Client fetches from `/api/anime`

**What you'll learn:** Your first real `Effect`. The full MVU cycle with an HTTP
request: init fires an effect, the runtime executes it, a message arrives,
update handles it, view re-renders.

**SvelteKit equivalent:** Using `fetch('/api/anime')` in a `load` function or
`onMount`.

#### Update client dependencies

Edit `client/gleam.toml` — replace the entire file:

```toml
name = "client"
version = "1.0.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
gleam_http = ">= 3.7.2 and < 5.0.0"
lustre = ">= 5.5.0 and < 6.0.0"
rsvp = ">= 1.0.0 and < 2.0.0"
shared = { path = "../shared" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
lustre_dev_tools = ">= 2.0.0 and < 3.0.0"
```

New dependencies:
- `rsvp` — HTTP client for Lustre. Makes HTTP requests as effects.
- `gleam_json` / `gleam_http` — needed by rsvp.
- `shared = { path = "../shared" }` — same types as the server.

#### Write the code

Replace `client/src/client.gleam` entirely:

```gleam
import gleam/int
import gleam/list
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared.{type Anime}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(anime: List(Anime), loading: Bool)
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(Model(anime: [], loading: True), fetch_anime())
}

// UPDATE ----------------------------------------------------------------------

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

#### Run it

You can't test this with just the dev server yet because it needs the `/api/anime`
endpoint. For now, confirm it compiles:

```sh
cd client
gleam deps download
gleam build
```

No errors? Good. We'll connect it to the server in the next step.

#### What just happened

This is the first step where an effect actually does something. Let's walk
through the full cycle:

```
1. lustre.start() calls init()
2. init returns #(Model(anime: [], loading: True), fetch_anime())
                  ↑ initial state                    ↑ effect to run
3. Lustre runtime:
   a. Calls view(Model(anime: [], loading: True)) → renders "Loading..."
   b. Executes fetch_anime() → HTTP GET /api/anime
4. Server responds with JSON
5. rsvp decodes the JSON using shared.anime_list_decoder()
6. rsvp wraps the result: ApiReturnedAnime(Ok([Anime(...), ...]))
7. Lustre runtime calls update(model, ApiReturnedAnime(Ok(anime)))
8. update returns #(Model(anime:, loading: False), effect.none())
9. Lustre runtime calls view(new_model) → renders the anime list
10. effect.none() means nothing more to do. App is idle.
```

The key line is `fetch_anime()`:

```gleam
fn fetch_anime() -> Effect(Msg) {
  rsvp.get(
    "/api/anime",
    rsvp.expect_json(shared.anime_list_decoder(), ApiReturnedAnime),
  )
}
```

This says: "Make a GET request to `/api/anime`. When the response arrives, decode
it as JSON using `anime_list_decoder`. Wrap the result (success or failure) in
`ApiReturnedAnime` and send it back as a message."

You never call `fetch` directly. You **describe** the HTTP request and hand it to
the runtime. The runtime does the fetching and delivers the result through the
normal MVU cycle.

Compare to SvelteKit:

| SvelteKit | Lustre |
|---|---|
| `const res = await fetch('/api/anime')` | `rsvp.get("/api/anime", ...)` |
| `const data = await res.json()` | `rsvp.expect_json(decoder, ...)` |
| Set state directly: `anime = data` | Runtime dispatches `ApiReturnedAnime(Ok(data))` |
| Error handling: `try/catch` | Pattern match: `ApiReturnedAnime(Error(_))` |

---

### Step 8: Serve the client JS from the server

**What you'll learn:** How to bundle the client and serve it from the Gleam
server. This turns two separate apps into one full-stack app.

**SvelteKit equivalent:** What Vite does automatically when you run `npm run build`
and deploy with an adapter. Here you do it explicitly.

#### Build the client

```sh
cd client
gleam run -m lustre/dev build --outdir=../server/priv/static
cd ..
```

This compiles the Gleam client to JavaScript, bundles it, and writes the output
to `server/priv/static/client.js`.

#### Update the server code

Edit `server/src/server.gleam`. We need to add two things:

1. A route to serve `/client.js`
2. A `<script>` tag in the HTML to load it

Replace the entire file:

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
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Steins;Gate", episodes: 24),
    Anime(id: 3, title: "Mob Psycho 100", episodes: 37),
  ]
}
```

#### Run it

```sh
cd server
gleam run
```

Open `http://localhost:3000`. You should see:

```
Anime Tracker
[Refresh]

Cowboy Bebop - 26 episodes
Steins;Gate - 24 episodes
Mob Psycho 100 - 37 episodes
```

Click "Refresh" — you'll see the button briefly say "Loading..." then the list
reappears (same data, since the server always returns the same list).

#### What just happened

Two changes made this work:

1. **A `<script>` tag** in the HTML loads `/client.js`:

```gleam
html.script(
  [attribute.type_("module"), attribute.src("/client.js")],
  "",
)
```

2. **A route** that serves the bundled file:

```gleam
["client.js"] -> serve_client_js()
```

`mist.send_file` reads a file from disk and streams it as the response body.
The path `"priv/static/client.js"` is relative to the server package root.

The HTML also changed: the body now just has `<div id="app">` — the empty mount
point. The client JS mounts there and takes over rendering.

The full sequence is now:

```
1. Browser requests GET /
2. Server responds with HTML (includes <script src="/client.js">)
3. Browser requests GET /client.js
4. Server responds with the bundled JS
5. Client JS runs, calls lustre.start() → init() → fetch_anime()
6. Browser requests GET /api/anime
7. Server responds with JSON
8. Client renders the anime list
```

This is a real full-stack app. Server renders the HTML shell, serves the client
bundle, and provides a JSON API. The client runs in the browser and communicates
with the server through HTTP.

---

### Step 9: Add hydration

**What you'll learn:** How to embed data in the server-rendered HTML so the
client doesn't need a loading state on first render.

**SvelteKit equivalent:** This is what SvelteKit does automatically with `load`
functions. The server fetches data, renders the page with it, and serializes
the data so the client can pick up where the server left off. Here we do it
manually.

#### Add `plinth` to the client

Edit `client/gleam.toml` — add `plinth` to dependencies:

```toml
name = "client"
version = "1.0.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
gleam_http = ">= 3.7.2 and < 5.0.0"
lustre = ">= 5.5.0 and < 6.0.0"
plinth = ">= 0.5.0 and < 1.0.0"
rsvp = ">= 1.0.0 and < 2.0.0"
shared = { path = "../shared" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
lustre_dev_tools = ">= 2.0.0 and < 3.0.0"
```

`plinth` gives us access to browser APIs like `document.querySelector`. We need
it to read the hydration JSON from the DOM.

#### Update the client

Replace `client/src/client.gleam` entirely:

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
  // Read hydration data from the <script id="model"> tag the server embedded.
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

type Model {
  Model(anime: List(Anime), loading: Bool)
}

fn init(flags: List(Anime)) -> #(Model, Effect(Msg)) {
  case flags {
    // Server gave us data via hydration - use it immediately.
    [_, ..] -> #(Model(anime: flags, loading: False), effect.none())

    // No hydration data. Fetch from the API.
    [] -> #(Model(anime: [], loading: True), fetch_anime())
  }
}

// UPDATE ----------------------------------------------------------------------

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

#### Update the server

Edit `server/src/server.gleam` — the only change is in `serve_html`. We embed
the anime data as JSON in a `<script>` tag:

Replace the entire file:

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
          // Hydration data: embed the anime list as JSON.
          // The client reads this before mounting and uses it as initial state.
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
  [
    Anime(id: 1, title: "Cowboy Bebop", episodes: 26),
    Anime(id: 2, title: "Steins;Gate", episodes: 24),
    Anime(id: 3, title: "Mob Psycho 100", episodes: 37),
  ]
}
```

#### Build and run

```sh
cd client
gleam deps download
gleam run -m lustre/dev build --outdir=../server/priv/static
cd ../server
gleam run
```

Open `http://localhost:3000`. The anime list appears **instantly** — no "Loading..."
flash.

#### What just happened

Two changes work together:

**Server side** — embed JSON in the HTML:

```gleam
html.script(
  [attribute.type_("application/json"), attribute.id("model")],
  json.to_string(shared.anime_list_to_json(anime_list)),
)
```

This renders as:
```html
<script type="application/json" id="model">
[{"id":1,"title":"Cowboy Bebop","episodes":26},...]
</script>
```

The browser ignores it (it's `type="application/json"`, not executable JS). It
just sits in the DOM as data.

**Client side** — read it before mounting:

```gleam
let hydrated_anime =
  document.query_selector("#model")
  |> result.map(plinth_element.inner_text)
  |> result.try(fn(text) {
    json.parse(text, shared.anime_list_decoder())
    |> result.replace_error(Nil)
  })
  |> result.unwrap([])
```

This finds the `<script id="model">` element, reads its text content, decodes
the JSON into `List(Anime)`, and falls back to `[]` if anything fails.

The decoded data is passed as flags to `lustre.start`:

```gleam
let assert Ok(_) = lustre.start(app, "#app", hydrated_anime)
```

And `init` checks whether we got data:

```gleam
fn init(flags: List(Anime)) -> #(Model, Effect(Msg)) {
  case flags {
    [_, ..] -> #(Model(anime: flags, loading: False), effect.none())
    [] -> #(Model(anime: [], loading: True), fetch_anime())
  }
}
```

If flags are non-empty (hydration worked), we use them directly and return
`effect.none()` — no HTTP request needed. If empty (maybe the script tag was
missing), fall back to fetching from the API.

This is SvelteKit's `load` → SSR → hydrate cycle, done manually:

| SvelteKit | Lustre |
|---|---|
| `load` function runs on server | `get_anime_from_db()` runs on server |
| Kit serializes data automatically | You call `json.to_string` and embed in `<script>` |
| Kit hydrates automatically | You read the `<script>`, decode, pass as flags |
| Page renders without loading state | `init` skips loading when flags are present |

---

## Phase 5: Server components

Server components are the most distinctive feature of Lustre. There's no SvelteKit
equivalent — it's a fundamentally different model for interactive UI.

---

### Step 10: What are server components?

**What you'll learn:** The mental model for server components. No code in this
step — just understanding.

**SvelteKit equivalent:** None. This is new territory.

#### The idea

Everything so far follows a familiar pattern: the server sends data, the client
renders it. The business logic (what to show, how to respond to clicks) runs in
the browser.

Server components flip this. The **business logic runs on the server** and the
**browser only renders the output**.

Here's the normal client-side model:

```
Browser                          Server
  |                                |
  | init/update/view run HERE      |
  |                                |
  | click → update → new view      |
  | (all in the browser)           |
  |                                |
  | fetch -----------------------> |
  | <---- JSON ------------------- |
  |                                |
  | update(model, ApiReturned(...)) |
  | view(new_model)                |
```

Here's the server component model:

```
Browser                          Server
  |                                |
  |                                | init/update/view run HERE
  |                                |
  | <-- full VDOM (on connect) --- |
  | render it                      |
  |                                |
  | click -----------------------> |
  |                                | update(model, UserClicked)
  |                                | new_view = view(new_model)
  |                                | patch = diff(old_view, new_view)
  | <-- patch -------------------- |
  | apply patch to DOM             |
```

The browser sends events (clicks, input) to the server over WebSocket. The server
runs `update`, computes the new `view`, diffs it against the old view, and sends
only the **patch** (what changed) back to the browser. The browser applies the
patch to the real DOM.

The client runtime that handles all this is about 10kB of JavaScript. You don't
write it — Lustre ships it. It registers a custom element called
`<lustre-server-component>` that manages the WebSocket connection.

#### Why would you want this?

| Reason | Explanation |
|---|---|
| No API to build | Your `update` function can directly query a database, read files, talk to other processes. No REST endpoints, no serialization, no error handling for network failures. |
| Secure by default | The browser never receives your business logic. You can't leak secrets because the code doesn't leave the server. |
| Tiny client | 10kB runtime instead of your entire app bundle. Good for widgets on content-heavy pages. |
| Real-time for free | The component is an OTP actor. When the model changes, the browser updates. No polling, no manual WebSocket management. |
| Same code | A server component is written identically to a client component. Same `init`, `update`, `view`. You could run it on either side. |

#### The tradeoff

Server components require a persistent WebSocket connection. Every connected user
has a process on the server. This is fine for dashboards, admin panels, and
interactive widgets — not ideal for a static blog.

#### What we'll build

A rating widget. The user clicks `[+]` or `[-]` to change a score. The score
lives on the server. The browser just shows the current value and sends clicks.

---

### Step 11: Build the rating component

**What you'll learn:** How to write a component that can run on the server. It's
written exactly like a client component — there's nothing special about the code
itself.

**SvelteKit equivalent:** Writing a normal `.svelte` component. The difference
is where it runs, which we'll set up in the next step.

#### Write the component

Create a new file `server/src/rating.gleam`:

```gleam
import gleam/int
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn component() -> lustre.App(_, Model, Msg) {
  lustre.simple(init, update, view)
}

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model(score: Int)
}

fn init(_) -> Model {
  Model(score: 5)
}

// UPDATE ----------------------------------------------------------------------

pub opaque type Msg {
  UserClickedUp
  UserClickedDown
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserClickedUp -> Model(score: int.min(model.score + 1, 10))
    UserClickedDown -> Model(score: int.max(model.score - 1, 1))
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
      #("font-family", "sans-serif"),
    ])],
    [
      html.span([], [html.text("Your rating: ")]),
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
      html.span([], [html.text(" / 10")]),
    ],
  )
}
```

#### Verify it compiles

```sh
cd server
gleam build
```

No errors? Good. We can't run it yet — it needs the WebSocket plumbing.

#### What just happened

Look at this code. It's a normal `lustre.simple` component:

- `init` returns a `Model`
- `update` takes `Model` and `Msg`, returns a new `Model`
- `view` takes `Model`, returns `Element(Msg)`

There's nothing server-specific about it. You could register this as a client-side
Web Component with `lustre.register`. The code is identical either way.

The `component()` function returns `lustre.App(_, Model, Msg)` — a component
definition that hasn't been started yet. Think of it as a class before you call
`new`. In the next step, we'll start it as a server component using
`lustre.start_server_component`.

Two details worth noting:

- **`pub opaque type Msg`** — `opaque` means other modules can reference the type
  `Msg` but can't construct its variants. Only this module creates messages. This
  is important for server components: the client can't forge messages.

- **`lustre.simple` not `lustre.application`** — This component has no effects.
  It could, but it doesn't need them. Server components can use effects too (for
  things like timers, database queries, or talking to other processes on the BEAM).

---

### Step 12: Wire the WebSocket

**What you'll learn:** The plumbing that connects a browser to a server component.
This is the most complex step, but the pattern is the same for every server
component you'll ever write.

**SvelteKit equivalent:** Building a custom WebSocket endpoint from scratch,
plus state management, DOM serialization, and event forwarding — all things
SvelteKit doesn't provide.

#### Update server dependencies

Edit `server/gleam.toml` — add `gleam_otp` and `gleam_json`:

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

`gleam_otp` is needed for `process.Subject` and `process.Selector`, which the
server component runtime uses to communicate.

#### Update the server

Replace `server/src/server.gleam` entirely:

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

// MAIN ------------------------------------------------------------------------

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
          server_component.element(
            [server_component.route("/ws/rate")],
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
// Serves Lustre's ~10kB client runtime that registers <lustre-server-component>
// as a custom element.

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
  // 1. Create the component
  let app = rating.component()

  // 2. Start it as a server component — this creates an OTP actor
  let assert Ok(runtime) = lustre.start_server_component(app, Nil)

  // 3. Create a Subject so the runtime can send us DOM patches
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  // 4. Register our subject with the runtime
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
    // Browser sent us an event (click, input, etc.) encoded as JSON
    mist.Text(raw_json) -> {
      case json.parse(raw_json, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.runtime, runtime_message)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

    // The Lustre runtime computed a DOM patch — send it to the browser
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

#### Don't run it yet

The server compiles, but the HTML now references `<lustre-server-component>` and
`/lustre/runtime.mjs`. We'll put it all together in the next step.

```sh
cd server
gleam deps download
gleam build
```

#### What just happened

This is the most code in a single step, but it breaks down into understandable
pieces. Let's go through each one.

**Two new routes:**

```gleam
["lustre", "runtime.mjs"] -> serve_lustre_runtime()
["ws", "rate"] -> serve_rating_ws(req)
```

The first serves the 10kB client runtime JS that Lustre ships. The second handles
WebSocket connections for the rating component.

**`serve_lustre_runtime`** reads the runtime file from Lustre's `priv` directory.
Lustre is an Erlang package — it has a `priv/` directory where it stores the
compiled JS runtime. `application.priv_directory("lustre")` finds it.

**`serve_rating_ws`** creates a WebSocket handler with three callbacks:

```gleam
mist.websocket(
  request: req,
  on_init: init_rating_socket,    // called when a client connects
  handler: loop_rating_socket,    // called for every message
  on_close: close_rating_socket,  // called when the connection closes
)
```

**`init_rating_socket`** — runs once per connection:

1. Creates the rating component: `rating.component()`
2. Starts it as a server component: `lustre.start_server_component(app, Nil)`.
   This creates an OTP actor (a lightweight process on the BEAM) that holds
   the component's state and runs `update`/`view`.
3. Creates a `Subject` — a typed mailbox. The runtime will send DOM patches here.
4. Registers the subject with the runtime so it knows where to send patches.

**`loop_rating_socket`** — handles two kinds of messages:

- `mist.Text(raw_json)` — the browser sent an event (e.g., a button click).
  We decode it with `server_component.runtime_message_decoder()` and forward
  it to the Lustre runtime. The runtime calls `update` and `view`, diffs the
  VDOM, and sends a patch to our Subject.

- `mist.Custom(client_message)` — the Lustre runtime sent us a patch (via our
  Subject). We encode it as JSON with `server_component.client_message_to_json`
  and send it over the WebSocket to the browser.

**`close_rating_socket`** — sends `lustre.shutdown()` to the runtime, which
stops the OTP actor. Without this, you'd leak processes.

The whole thing is a bridge: Mist manages the WebSocket, Lustre manages the
component state and VDOM diffing, and this code connects them.

---

### Step 13: Put it all together

**What you'll learn:** How all the pieces work together. The SPA and server
component coexist on the same page.

**SvelteKit equivalent:** Having a normal page with interactive components AND
a live widget that runs entirely on the server. SvelteKit can't do this without
significant custom infrastructure.

#### Build and run

```sh
# Build the client
cd client
gleam run -m lustre/dev build --outdir=../server/priv/static
cd ..

# Start the server
cd server
gleam run
```

#### See it

Open `http://localhost:3000`. You should see:

```
Anime Tracker
[Refresh]

Cowboy Bebop - 26 episodes
Steins;Gate - 24 episodes
Mob Psycho 100 - 37 episodes

────────────────────────────────

Rate this anime
┌─────────────────────────────────┐
│ Your rating:  [-]  5  [+] / 10 │
└─────────────────────────────────┘
```

- Click **Refresh** — the anime list reloads via REST API (client-side HTTP).
- Click **[+]** or **[-]** — the score changes via server component (WebSocket).

#### What just happened

The page has two independent interactive systems:

**Top half: Lustre SPA (client-side)**
- Hydrated from server-embedded JSON (no loading spinner)
- Refresh button fetches from `/api/anime` via HTTP
- All logic runs in the browser

**Bottom half: Server component (server-side)**
- `<lustre-server-component route="/ws/rate">` custom element
- Loads `/lustre/runtime.mjs` which registers the custom element
- Opens a WebSocket to `/ws/rate`
- Receives the full VDOM on connect
- Sends click events to the server
- Receives DOM patches back
- Rating logic runs on the BEAM — the browser just renders

They don't know about each other. They coexist on the same page.

Here's the full page load sequence:

```
Browser                                 Server (BEAM)
   |                                        |
   |-- GET / ------------------------------>|
   |                                        |  get_anime_from_db()
   |                                        |  render HTML with:
   |                                        |    <script id="model"> (JSON)
   |                                        |    <div id="app">
   |                                        |    <lustre-server-component>
   |                                        |    <script src="/client.js">
   |                                        |    <script src="/lustre/runtime.mjs">
   |<-- 200 HTML ---------------------------|
   |                                        |
   |-- GET /client.js --------------------->|
   |<-- 200 JS bundle ---------------------|
   |                                        |
   |  Client JS runs:                       |
   |    reads #model JSON                   |
   |    lustre.start(app, "#app", anime)    |
   |    renders anime list immediately      |
   |                                        |
   |-- GET /lustre/runtime.mjs ------------>|
   |<-- 200 (~10kB) -----------------------|
   |                                        |
   |  runtime.mjs registers                |
   |  <lustre-server-component>             |
   |                                        |
   |-- WS CONNECT /ws/rate ---------------->|
   |                                        |  start_server_component(rating, Nil)
   |                                        |  creates OTP actor
   |                                        |  renders initial VDOM
   |<-- WS Mount { full VDOM } ------------|
   |                                        |
   |  browser renders rating widget         |
   |                                        |
   |  --- page is fully interactive ---     |
   |                                        |
   |  User clicks [+]                       |
   |-- WS EventFired { click } ----------->|
   |                                        |  update(Model(5), UserClickedUp)
   |                                        |  -> Model(6)
   |                                        |  view(Model(6))
   |                                        |  diff(old_vdom, new_vdom)
   |<-- WS Reconcile { patch: "5"->"6" } --|
   |                                        |
   |  browser patches "5" to "6"            |
```

---

## You're done

You've built a full-stack Lustre app with:

- **Static rendering** (`lustre.element`)
- **Interactive client** (`lustre.simple` → `lustre.application`)
- **Shared types** across client and server
- **Server-rendered HTML** with a JSON API
- **Hydration** from server-embedded data
- **Server components** running on the BEAM over WebSocket

Every concept was introduced one at a time. You can now:

- Add more fields to the `Anime` type — both sides update or the compiler stops you.
- Add new API routes — more `case` branches in the request handler.
- Add new pages — use the `modem` package for client-side routing.
- Add more server components — the WebSocket plumbing is the same pattern every time.
- Add database access — the server runs on the BEAM, so you have access to Erlang
  libraries and OTP.

---

## File recap

```
shared/gleam.toml          Dependencies: gleam_json
shared/src/shared.gleam    Anime type + decoder + to_json

client/gleam.toml          Dependencies: lustre, rsvp, plinth, shared; target=javascript
client/src/client.gleam    SPA with hydration + REST fetch

server/gleam.toml          Dependencies: mist, lustre, gleam_otp, shared
server/src/server.gleam    5 routes: HTML, client.js, API, runtime, WebSocket
server/src/rating.gleam    Server component: init/update/view (runs on BEAM)
```

---

## Quick reference: The three communication patterns

| Pattern | Data flow | When to use |
|---|---|---|
| **SSR + Hydration** | Server embeds JSON → client reads on boot | Every page load. Fast first paint. |
| **REST API** | Client sends HTTP → server returns JSON → client updates | CRUD. Refreshing data. User-triggered actions. |
| **Server Components** | Server runs component → pushes DOM patches over WS | Real-time UI. Server-only logic. Zero API boilerplate. |
