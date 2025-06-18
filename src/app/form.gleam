import formal/form
import gleam/option

pub type Form {
  Form(
    form: form.Form,
    loading: Bool,
    success: Bool,
    error: option.Option(String),
  )
}

pub fn new_form() -> Form {
  Form(form: form.new(), loading: False, success: False, error: option.None)
}
