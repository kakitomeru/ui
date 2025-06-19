import app/api/types
import app/route/register/decoders
import app/route/register/effects
import app/ui/form
import gleam/option.{None, Some}
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import rsvp

pub type Model {
  Model(register_form: form.Form)
}

pub fn init() -> #(Model, effect.Effect(Msg)) {
  let model = Model(register_form: form.new_form_state())

  #(model, effect.none())
}

pub type Msg {
  UserSubmittedRegister(List(#(String, String)))
  ApiUserRegistered(Result(String, rsvp.Error))
}

pub type OutMsg {
  UserRegistered(user_id: String)
}

pub fn update(
  model: Model,
  msg: Msg,
) -> #(Model, effect.Effect(Msg), option.Option(OutMsg)) {
  case msg {
    UserSubmittedRegister(inputs) -> {
      case decoders.decode_register_data(inputs) {
        Ok(decoders.RegisterData(username, email, password)) -> {
          let new_register_form =
            form.Form(..model.register_form, loading: True, error: option.None)

          let new_model = Model(register_form: new_register_form)
          let effect =
            effects.register_user_effect(
              username,
              email,
              password,
              ApiUserRegistered,
            )

          #(new_model, effect, None)
        }
        Error(form_with_errors) -> {
          let new_register_form =
            form.Form(
              ..model.register_form,
              form_: form_with_errors,
              loading: False,
              error: option.None,
            )

          let new_model = Model(register_form: new_register_form)

          #(new_model, effect.none(), None)
        }
      }
    }
    ApiUserRegistered(Ok(user_id)) -> {
      let new_register_form =
        form.Form(..model.register_form, loading: False, success: True)

      let new_model = Model(register_form: new_register_form)

      #(new_model, effect.none(), Some(UserRegistered(user_id)))
    }
    ApiUserRegistered(Error(error)) -> {
      let new_register_form =
        form.Form(
          ..model.register_form,
          loading: False,
          error: option.Some(types.message_from_api_error(error)),
        )

      let new_model = Model(register_form: new_register_form)

      #(new_model, effect.none(), None)
    }
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  let form = model.register_form

  html.div([], [
    html.h1([], [html.text("Register")]),
    form.view_form_error(form),
    html.form([event.on_submit(UserSubmittedRegister)], [
      form.view_input(form, "username", "username", "Username", "Your username"),
      form.view_input(form, "email", "email", "Email", "Your email"),
      form.view_input(form, "password", "password", "Password", "Your password"),
      html.button([attribute.disabled(form.loading)], [
        case form.loading {
          True -> html.text("Registering...")
          False -> html.text("Register")
        },
      ]),
    ]),
  ])
}
