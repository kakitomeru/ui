import app/api/types
import app/data/auth
import app/route/login/decoders
import app/route/login/effects
import app/ui/form
import gleam/option.{None, Some}
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import rsvp

pub type Model {
  Model(login_form: form.Form)
}

pub fn init() -> #(Model, effect.Effect(Msg)) {
  let model = Model(login_form: form.new_form_state())

  #(model, effect.none())
}

pub type Msg {
  UserSubmittedLogin(List(#(String, String)))
  ApiUserLoggedIn(Result(auth.Metadata, rsvp.Error))
}

pub type OutMsg {
  LoginSucceeded(metadata: auth.Metadata)
}

pub fn update(
  model: Model,
  msg: Msg,
  api_url: String,
) -> #(Model, effect.Effect(Msg), option.Option(OutMsg)) {
  case msg {
    UserSubmittedLogin(inputs) -> {
      case decoders.decode_login_data(inputs) {
        Ok(decoders.LoginData(email, password)) -> {
          let new_login_form =
            form.Form(..model.login_form, loading: True, error: option.None)

          let new_model = Model(login_form: new_login_form)
          let effect =
            effects.login_user_effect(api_url, email, password, ApiUserLoggedIn)

          #(new_model, effect, None)
        }
        Error(form_with_errors) -> {
          let new_login_form =
            form.Form(
              ..model.login_form,
              form_: form_with_errors,
              loading: False,
              error: option.None,
            )

          let new_model = Model(login_form: new_login_form)

          #(new_model, effect.none(), None)
        }
      }
    }
    ApiUserLoggedIn(Ok(metadata)) -> {
      let new_login_form =
        form.Form(..model.login_form, loading: False, success: True)
      let new_model = Model(login_form: new_login_form)

      #(new_model, effect.none(), Some(LoginSucceeded(metadata)))
    }
    ApiUserLoggedIn(Error(error)) -> {
      let new_login_form =
        form.Form(
          ..model.login_form,
          loading: False,
          error: option.Some(types.message_from_api_error(error)),
        )

      let new_model = Model(login_form: new_login_form)

      #(new_model, effect.none(), None)
    }
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  let form = model.login_form

  html.div([], [
    html.h1([], [html.text("Login")]),
    form.view_form_error(form),
    html.form([event.on_submit(UserSubmittedLogin)], [
      form.view_input(form, "email", "email", "Email", "Your email"),
      form.view_input(form, "password", "password", "Password", "Your password"),
      html.button([attribute.disabled(form.loading)], [
        case form.loading {
          True -> html.text("Logging in...")
          False -> html.text("Login")
        },
      ]),
    ]),
  ])
}
