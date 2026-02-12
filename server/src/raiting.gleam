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

pub type Model {
  Model(score: Int)
}

pub opaque type Msg {
  ParentChangedValue(Int)
  UserClickedUp
  UserClickedDown
  UserClickedSubmit
}

pub fn value(val: Int) -> Attribute(msg) {
  attribute.value(int.to_string(val))
}

pub fn component() -> lustre.App(_, Model, Msg) {
  lustre.component(init, update, view, [
    component.on_attribute_change("value", fn(value) {
      int.parse(value) |> result.map(ParentChangedValue)
    }),
  ])
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(score: 5), effect.none())
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

fn view(model: Model) -> Element(Msg) {
  let score = int.to_string(model.score)

  html.div(
    [
      attribute.styles([
        #("display", "flex"),
        #("align-items", "center"),
        #("gap", "0.5rem"),
        #("padding", "1rem"),
        #("border", "1px solid #ccc"),
        #("border-radius", "0.5rem"),
      ]),
    ],
    [
      html.span([], [html.text("Rating: ")]),
      html.button([event.on_click(UserClickedDown)], [html.text("-")]),
      html.span(
        [
          attribute.styles([
            #("font-size", "1.5rem"),
            #("min-width", "2ch"),
            #("text-align", "center"),
          ]),
        ],
        [html.text(score)],
      ),
      html.button([event.on_click(UserClickedUp)], [html.text("+")]),
      html.span([], [html.text(" / 10  ")]),
      html.button([event.on_click(UserClickedSubmit)], [html.text("Save")]),
    ],
  )
}
