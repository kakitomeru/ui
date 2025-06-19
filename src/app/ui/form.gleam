import formal/form
import gleam/option
import lustre/attribute
import lustre/element
import lustre/element/html

pub type Form {
  Form(
    form_: form.Form,
    loading: Bool,
    success: Bool,
    error: option.Option(String),
  )
}

pub fn new_form_state() -> Form {
  Form(form_: form.new(), loading: False, success: False, error: option.None)
}

pub fn view_form_error(form: Form) -> element.Element(msg) {
  case form.error {
    option.Some(error) -> html.p([], [html.text(error)])
    option.None -> element.none()
  }
}

pub fn view_input(
  form: Form,
  is type_: String,
  name name: String,
  label label: String,
  placeholder placeholder: String,
) -> element.Element(msg) {
  let state = form.field_state(form.form_, name)

  html.div([], [
    html.label([attribute.for(name)], [html.text(label), html.text(":")]),
    html.input([
      attribute.type_(type_),
      attribute.id(name),
      attribute.name(name),
      attribute.placeholder(placeholder),
    ]),
    case state, form.loading, form.error {
      // No error message if:
      // 1. There is no error related to this input
      Ok(Nil), _, _ -> element.none()
      // 2. Form submitted and still loading
      Error(_), True, _ -> element.none()
      // 3. Form got an error from response, meaning the input was valid
      Error(_), False, option.Some(_) -> element.none()

      // Else, show the error message
      Error(message), _, _ -> html.p([], [html.text(message)])
    },
  ])
}
