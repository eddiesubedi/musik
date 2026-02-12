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

pub fn main() {
  echo document.query_selector("#model") |> result.map(plinth_element.inner_text)|> result.try(fn(text) {
    json.parse(text, shared.anime_list_decorder())
    |> result.replace_error(Nil)
  })
  let hydrate_anime =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(text) {
      json.parse(text, shared.anime_list_decorder())
      |> result.replace_error(Nil)
    })
    |> result.unwrap([])

  echo hydrate_anime
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", hydrate_anime)
  Nil
}

type Model {
  Model(anime: List(Anime), loading: Bool)
}

type Msg {
  ApiReturnedAnime(Result(List(Anime), rsvp.Error))
  UserClickedRefresh
}

fn init(flags: List(Anime)) -> #(Model, Effect(Msg)) {
  case flags {
    [_, ..] -> #(Model(anime: flags, loading: False), effect.none())
    [] -> #(Model(anime: [], loading: True), fetch_anime())
  }
}

fn fetch_anime() -> Effect(Msg) {
  rsvp.get(
    "/api/anime",
    rsvp.expect_json(shared.anime_list_decorder(), ApiReturnedAnime),
  )
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
    UserClickedRefresh -> #(Model(..model, loading: True), fetch_anime())
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Anime Tracking")]),
    html.button(
      [event.on_click(UserClickedRefresh), attribute.disabled(model.loading)],
      [
        html.text(case model.loading {
          True -> "Loading..."
          False -> "Refresh"
        }),
      ],
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
    [
      attribute.styles([
        #("padding", "0.75rem"),
        #("margin", "0.5rem 0"),
        #("background", "#f5f5f5"),
        #("border-radius", "0.25rem"),
      ]),
    ],
    [
      html.strong([], [html.text(anime.title)]),
      html.text(" - " <> int.to_string(anime.episodes) <> " episodes"),
    ],
  )
}
