import components/homepage/hero
import components/homepage/model.{
  type Flags, type Model, type Msg, ApiResponded, Errored, Loaded, Loading,
  ToggleMute, VideoEnded, VideoPlaying,
}
import gleam/io
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub fn component() -> lustre.App(Flags, Model, Msg) {
  lustre.component(init, update, view, [])
}

fn init(flags: Flags) -> #(Model, Effect(Msg)) {
  io.println("[homepage] init for: " <> flags.name)
  #(Loading(flags:), model.fetch_home(flags.db))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let flags = model.flags
  case msg {
    ApiResponded(Ok(detail)) -> {
      io.println("[homepage] loaded: " <> detail.hero.name)
      #(
        Loaded(flags:, detail:, video_playing: False, muted: True),
        effect.none(),
      )
    }
    ApiResponded(Error(error)) -> {
      io.println("[homepage] error fetching hero")
      #(Errored(flags:, error:), effect.none())
    }
    VideoPlaying -> {
      case model {
        Loaded(..) as m -> #(Loaded(..m, video_playing: True), effect.none())
        _ -> #(model, effect.none())
      }
    }
    VideoEnded -> {
      case model {
        Loaded(..) as m -> #(Loaded(..m, video_playing: False), effect.none())
        _ -> #(model, effect.none())
      }
    }
    ToggleMute -> {
      case model {
        Loaded(muted:, ..) as m -> #(Loaded(..m, muted: !muted), effect.none())
        _ -> #(model, effect.none())
      }
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  case model {
    Loading(..) -> html.p([], [html.text("Loading...")])
    Loaded(detail:, video_playing:, muted:, ..) ->
      html.div([], [
        hero.view(detail.hero, video_playing, muted),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
        html.br([]),
      ])
    Errored(..) -> html.p([], [html.text("Something went wrong, try again.")])
  }
}
