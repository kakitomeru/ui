import gleam/int
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/event

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model =
  Int

fn init(_) -> Model {
  0
}

type Msg {
  Increment
  Decrement
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Increment -> model + 1
    Decrement -> model - 1
  }
}

fn view(model: Model) -> element.Element(Msg) {
  let count = int.to_string(model)

  html.div([], [
    html.h1([attribute.class("text-3xl font-bold")], [html.text("Counter")]),
    html.p([attribute.class("font-bold")], [html.text(count)]),
    html.button(
      [
        event.on_click(Increment),
        attribute.class("bg-blue-500 text-white p-2 rounded-md"),
      ],
      [html.text("Increment")],
    ),
    html.button(
      [
        event.on_click(Decrement),
        attribute.class("bg-red-500 text-white p-2 rounded-md ml-2"),
      ],
      [html.text("Decrement")],
    ),
  ])
}
