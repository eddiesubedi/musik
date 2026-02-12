# Lustre Starter Template

Copy this for every new project. Each step creates 1-2 files and ends with a
verification command. No explanations — see WALKTHROUGH.md and GUIDE.md if you
need to understand what's happening.

---

## Step 1: Create the monorepo

```sh
mkdir my-app && cd my-app
gleam new shared
gleam new client
gleam new server
```

**Verify:**

```sh
ls
```

You should see: `client/  server/  shared/`

---

## Step 2: Shared types

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

### `shared/src/shared.gleam`

```gleam
import gleam/dynamic/decode
import gleam/json

pub type Item {
  Item(id: Int, name: String)
}

pub fn item_decoder() -> decode.Decoder(Item) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(Item(id:, name:))
}

pub fn item_list_decoder() -> decode.Decoder(List(Item)) {
  decode.list(item_decoder())
}

pub fn item_to_json(item: Item) -> json.Json {
  json.object([
    #("id", json.int(item.id)),
    #("name", json.string(item.name)),
  ])
}

pub fn item_list_to_json(items: List(Item)) -> json.Json {
  json.array(items, item_to_json)
}
```

**Verify:**

```sh
cd shared && gleam build && cd ..
```

---

## Step 3: Server dependencies

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

**Verify:**

```sh
cd server && gleam deps download && cd ..
```

---

## Step 4: Server — GET / returning HTML

### `server/src/server.gleam`

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
        html.title([], "My App"),
      ]),
      html.body(
        [attribute.styles([
          #("max-width", "40rem"),
          #("margin", "2rem auto"),
          #("font-family", "sans-serif"),
        ])],
        [
          html.h1([], [html.text("My App")]),
          html.p([], [html.text("It works.")]),
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

**Verify:**

```sh
cd server && gleam run &
sleep 2
curl -s http://localhost:3000 | head -5
kill %1
cd ..
```

You should see HTML containing "My App".

---

## Step 5: Server — add GET /api/items

### `server/src/server.gleam`

Replace the entire file:

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
import shared.{Item}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["api", "items"] -> serve_items_api()
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
        html.title([], "My App"),
      ]),
      html.body(
        [attribute.styles([
          #("max-width", "40rem"),
          #("margin", "2rem auto"),
          #("font-family", "sans-serif"),
        ])],
        [
          html.h1([], [html.text("My App")]),
          html.p([], [html.text("It works.")]),
        ],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}

fn serve_items_api() -> Response(ResponseData) {
  let body =
    get_items()
    |> shared.item_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
}

fn get_items() -> List(Item) {
  [
    Item(id: 1, name: "First item"),
    Item(id: 2, name: "Second item"),
    Item(id: 3, name: "Third item"),
  ]
}
```

**Verify:**

```sh
cd server && gleam run &
sleep 2
curl -s http://localhost:3000/api/items
kill %1
cd ..
```

You should see: `[{"id":1,"name":"First item"},{"id":2,"name":"Second item"},{"id":3,"name":"Third item"}]`

---

## Step 6: Client dependencies

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

**Verify:**

```sh
cd client && gleam deps download && cd ..
```

---

## Step 7: Client — basic app with API fetch

### `client/src/client.gleam`

```gleam
import gleam/list
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared.{type Item}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(items: List(Item), loading: Bool)
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(Model(items: [], loading: True), fetch_items())
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ApiReturnedItems(Result(List(Item), rsvp.Error))
  UserClickedRefresh
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ApiReturnedItems(Ok(items)) -> #(
      Model(items:, loading: False),
      effect.none(),
    )
    ApiReturnedItems(Error(_)) -> #(
      Model(..model, loading: False),
      effect.none(),
    )
    UserClickedRefresh -> #(
      Model(..model, loading: True),
      fetch_items(),
    )
  }
}

// EFFECTS ---------------------------------------------------------------------

fn fetch_items() -> Effect(Msg) {
  rsvp.get(
    "/api/items",
    rsvp.expect_json(shared.item_list_decoder(), ApiReturnedItems),
  )
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("My App")]),
    html.button(
      [event.on_click(UserClickedRefresh), attribute.disabled(model.loading)],
      [html.text(case model.loading {
        True -> "Loading..."
        False -> "Refresh"
      })],
    ),
    case model.items {
      [] -> html.p([], [html.text("No items loaded.")])
      items ->
        html.ul([], list.map(items, fn(item) {
          html.li([], [html.text(item.name)])
        }))
    },
  ])
}
```

**Verify:**

```sh
cd client && gleam build && cd ..
```

---

## Step 8: Build client + serve from server

### Update `server/src/server.gleam`

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
import shared.{Item}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["client.js"] -> serve_client_js()
        ["api", "items"] -> serve_items_api()
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
        html.title([], "My App"),
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

fn serve_items_api() -> Response(ResponseData) {
  let body =
    get_items()
    |> shared.item_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
}

fn get_items() -> List(Item) {
  [
    Item(id: 1, name: "First item"),
    Item(id: 2, name: "Second item"),
    Item(id: 3, name: "Third item"),
  ]
}
```

### Bundle and run

```sh
cd client && gleam run -m lustre/dev build --outdir=../server/priv/static && cd ..
cd server && gleam run
```

**Verify:** Open `http://localhost:3000` — you should see the items list with a Refresh button.

---

## Step 9: Add hydration

### Update `server/src/server.gleam`

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
import shared.{Item}

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["client.js"] -> serve_client_js()
        ["api", "items"] -> serve_items_api()
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
  let items = get_items()

  let page =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "My App"),
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
          html.script(
            [attribute.type_("application/json"), attribute.id("model")],
            json.to_string(shared.item_list_to_json(items)),
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

fn serve_items_api() -> Response(ResponseData) {
  let body =
    get_items()
    |> shared.item_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
}

fn get_items() -> List(Item) {
  [
    Item(id: 1, name: "First item"),
    Item(id: 2, name: "Second item"),
    Item(id: 3, name: "Third item"),
  ]
}
```

### Update `client/src/client.gleam`

Replace the entire file:

```gleam
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
import shared.{type Item}

pub fn main() {
  let hydrated_items =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(text) {
      json.parse(text, shared.item_list_decoder())
      |> result.replace_error(Nil)
    })
    |> result.unwrap([])

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", hydrated_items)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(items: List(Item), loading: Bool)
}

fn init(flags: List(Item)) -> #(Model, Effect(Msg)) {
  case flags {
    [_, ..] -> #(Model(items: flags, loading: False), effect.none())
    [] -> #(Model(items: [], loading: True), fetch_items())
  }
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ApiReturnedItems(Result(List(Item), rsvp.Error))
  UserClickedRefresh
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ApiReturnedItems(Ok(items)) -> #(
      Model(items:, loading: False),
      effect.none(),
    )
    ApiReturnedItems(Error(_)) -> #(
      Model(..model, loading: False),
      effect.none(),
    )
    UserClickedRefresh -> #(
      Model(..model, loading: True),
      fetch_items(),
    )
  }
}

// EFFECTS ---------------------------------------------------------------------

fn fetch_items() -> Effect(Msg) {
  rsvp.get(
    "/api/items",
    rsvp.expect_json(shared.item_list_decoder(), ApiReturnedItems),
  )
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("My App")]),
    html.button(
      [event.on_click(UserClickedRefresh), attribute.disabled(model.loading)],
      [html.text(case model.loading {
        True -> "Loading..."
        False -> "Refresh"
      })],
    ),
    case model.items {
      [] -> html.p([], [html.text("No items loaded.")])
      items ->
        html.ul([], list.map(items, fn(item) {
          html.li([], [html.text(item.name)])
        }))
    },
  ])
}
```

### Rebuild and run

```sh
cd client && gleam run -m lustre/dev build --outdir=../server/priv/static && cd ..
cd server && gleam run
```

**Verify:** Open `http://localhost:3000` — items appear instantly with no "Loading..." flash.

---

## Step 10: Add routing

### Update `client/src/client.gleam`

Replace the entire file:

```gleam
import gleam/json
import gleam/list
import gleam/result
import gleam/uri
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/document
import plinth/browser/element as plinth_element
import rsvp
import shared.{type Item}

pub fn main() {
  let hydrated_items =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(text) {
      json.parse(text, shared.item_list_decoder())
      |> result.replace_error(Nil)
    })
    |> result.unwrap([])

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", hydrated_items)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Route {
  Home
  Items
  NotFound
}

type Model {
  Model(route: Route, items: List(Item), loading: Bool)
}

fn init(flags: List(Item)) -> #(Model, Effect(Msg)) {
  let route = case modem.initial_uri() {
    Ok(uri) -> parse_route(uri)
    Error(_) -> Home
  }

  let #(items, loading, fetch_effect) = case flags {
    [_, ..] -> #(flags, False, effect.none())
    [] -> #([], True, fetch_items())
  }

  #(
    Model(route:, items:, loading:),
    effect.batch([
      modem.init(fn(uri) { UserNavigatedTo(parse_route(uri)) }),
      fetch_effect,
    ]),
  )
}

fn parse_route(uri: uri.Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> Home
    ["items"] -> Items
    _ -> NotFound
  }
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ApiReturnedItems(Result(List(Item), rsvp.Error))
  UserClickedRefresh
  UserNavigatedTo(Route)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ApiReturnedItems(Ok(items)) -> #(
      Model(..model, items:, loading: False),
      effect.none(),
    )
    ApiReturnedItems(Error(_)) -> #(
      Model(..model, loading: False),
      effect.none(),
    )
    UserClickedRefresh -> #(
      Model(..model, loading: True),
      fetch_items(),
    )
    UserNavigatedTo(route) -> #(
      Model(..model, route:),
      effect.none(),
    )
  }
}

// EFFECTS ---------------------------------------------------------------------

fn fetch_items() -> Effect(Msg) {
  rsvp.get(
    "/api/items",
    rsvp.expect_json(shared.item_list_decoder(), ApiReturnedItems),
  )
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.nav([], [
      html.a([attribute.href("/")], [html.text("Home")]),
      html.text(" | "),
      html.a([attribute.href("/items")], [html.text("Items")]),
    ]),
    html.hr([]),
    case model.route {
      Home -> view_home()
      Items -> view_items(model)
      NotFound -> html.p([], [html.text("404 — Not found")])
    },
  ])
}

fn view_home() -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("My App")]),
    html.p([], [html.text("Welcome. Go to Items to see data.")]),
  ])
}

fn view_items(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Items")]),
    html.button(
      [event.on_click(UserClickedRefresh), attribute.disabled(model.loading)],
      [html.text(case model.loading {
        True -> "Loading..."
        False -> "Refresh"
      })],
    ),
    case model.items {
      [] -> html.p([], [html.text("No items loaded.")])
      items ->
        html.ul([], list.map(items, fn(item) {
          html.li([], [html.text(item.name)])
        }))
    },
  ])
}
```

### Rebuild and run

```sh
cd client && gleam run -m lustre/dev build --outdir=../server/priv/static && cd ..
cd server && gleam run
```

**Verify:** Open `http://localhost:3000`. Click "Items" — URL changes, view switches. Click "Home" — back to welcome page.

---

## Step 11: Server component + WebSocket

### Create `server/src/widget.gleam`

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
  Model(count: Int)
}

fn init(_) -> Model {
  Model(count: 0)
}

// UPDATE ----------------------------------------------------------------------

pub opaque type Msg {
  UserClickedUp
  UserClickedDown
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserClickedUp -> Model(count: model.count + 1)
    UserClickedDown -> Model(count: int.max(model.count - 1, 0))
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
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
      html.button([event.on_click(UserClickedDown)], [html.text("-")]),
      html.span(
        [attribute.styles([
          #("font-size", "1.5rem"),
          #("min-width", "2ch"),
          #("text-align", "center"),
        ])],
        [html.text(int.to_string(model.count))],
      ),
      html.button([event.on_click(UserClickedUp)], [html.text("+")]),
    ],
  )
}
```

### Update `server/src/server.gleam`

Replace the entire file:

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
import shared.{Item}
import widget

pub fn main() {
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["client.js"] -> serve_client_js()
        ["api", "items"] -> serve_items_api()
        ["lustre", "runtime.mjs"] -> serve_lustre_runtime()
        ["ws", "widget"] -> serve_widget_ws(req)
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
  let items = get_items()

  let page =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "My App"),
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
            json.to_string(shared.item_list_to_json(items)),
          ),
          html.div([attribute.id("app")], []),
          html.hr([]),
          html.h2([], [html.text("Server Widget")]),
          server_component.element(
            [server_component.route("/ws/widget")],
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

// ROUTE: GET /api/items -------------------------------------------------------

fn serve_items_api() -> Response(ResponseData) {
  let body =
    get_items()
    |> shared.item_list_to_json
    |> json.to_string
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "application/json")
}

// ROUTE: GET /lustre/runtime.mjs ----------------------------------------------

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

// ROUTE: WS /ws/widget --------------------------------------------------------

fn serve_widget_ws(req: Request(Connection)) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: init_widget_socket,
    handler: loop_widget_socket,
    on_close: close_widget_socket,
  )
}

type WidgetSocket {
  WidgetSocket(
    runtime: lustre.Runtime(widget.Msg),
    self: Subject(server_component.ClientMessage(widget.Msg)),
  )
}

type WidgetSocketMsg =
  server_component.ClientMessage(widget.Msg)

fn init_widget_socket(
  _connection,
) -> #(WidgetSocket, Option(Selector(WidgetSocketMsg))) {
  let app = widget.component()
  let assert Ok(runtime) = lustre.start_server_component(app, Nil)

  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  #(WidgetSocket(runtime:, self:), Some(selector))
}

fn loop_widget_socket(
  state: WidgetSocket,
  message: mist.WebsocketMessage(WidgetSocketMsg),
  connection: mist.WebsocketConnection,
) -> mist.Next(WidgetSocket, WidgetSocketMsg) {
  case message {
    mist.Text(raw_json) -> {
      case json.parse(raw_json, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.runtime, runtime_message)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

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

fn close_widget_socket(state: WidgetSocket) -> Nil {
  lustre.shutdown()
  |> lustre.send(to: state.runtime)
}

// DATA ------------------------------------------------------------------------

fn get_items() -> List(Item) {
  [
    Item(id: 1, name: "First item"),
    Item(id: 2, name: "Second item"),
    Item(id: 3, name: "Third item"),
  ]
}
```

### Rebuild and run

```sh
cd client && gleam run -m lustre/dev build --outdir=../server/priv/static && cd ..
cd server && gleam run
```

**Verify:** Open `http://localhost:3000`. The SPA works at the top. Below the line, the server component counter renders with `[-]` and `[+]` buttons — clicks round-trip through the WebSocket.

---

## Step 12: .gitignore + build script

### `my-app/.gitignore`

```
build/
erl_crash.dump
server/priv/static/client.js
```

### `my-app/Makefile`

```makefile
.PHONY: deps build dev clean

deps:
	cd shared && gleam deps download
	cd client && gleam deps download
	cd server && gleam deps download

build:
	cd shared && gleam build
	cd client && gleam run -m lustre/dev build --outdir=../server/priv/static

dev: build
	cd server && gleam run

clean:
	rm -rf shared/build client/build server/build
	rm -f server/priv/static/client.js
```

**Verify:**

```sh
make deps
make dev
```

Open `http://localhost:3000` — everything works.

---

## File recap

```
.gitignore
Makefile

shared/gleam.toml           gleam_json
shared/src/shared.gleam     Item type + decoder + encoder

client/gleam.toml           lustre, rsvp, plinth, modem, shared; target=javascript
client/src/client.gleam     SPA: hydration, routing, API fetch

server/gleam.toml           mist, lustre, gleam_otp, gleam_json, shared
server/src/server.gleam     6 routes: HTML, client.js, API, runtime.mjs, WS
server/src/widget.gleam     Server component (runs on BEAM)
```
