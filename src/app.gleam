// IMPORTS --------------------------------------------------------------------

import app/effect as e
import app/form.{type Form} as f
import app/message
import app/model
import app/route
import app/shared.{
  Authenticated, Metadata, Unauthenticated, UnauthenticatedForms,
}
import app/update
import formal/form
import gleam/option
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event

// MAIN -----------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

// MODEL ----------------------------------------------------------------------

pub fn init(_args: Nil) -> #(model.Model, effect.Effect(message.Msg)) {
  let access_token = get_access_token()
  let model = model.model_with_route(route.Loading)

  case access_token {
    Ok(access_token) -> #(
      model,
      e.get_user_info(access_token, message.ApiUserFetched),
    )
    Error(Nil) -> #(model, e.init_route())
  }
}

// UPDATE ---------------------------------------------------------------------

pub fn update(
  model: model.Model,
  msg: message.Msg,
) -> #(model.Model, effect.Effect(message.Msg)) {
  update.handle_update(model, msg)
}

// VIEW -----------------------------------------------------------------------

fn view(model: model.Model) -> element.Element(message.Msg) {
  html.div([], [
    html.a([attribute.href("/"), attribute.class("text-blue-500 mr-2")], [
      html.text("Dashboard"),
    ]),
    html.a(
      [attribute.href("/auth/login"), attribute.class("text-blue-500 mr-2")],
      [html.text("Login")],
    ),
    html.a(
      [attribute.href("/auth/register"), attribute.class("text-blue-500 mr-2")],
      [html.text("Register")],
    ),
    html.a([attribute.href("/home"), attribute.class("text-blue-500 mr-2")], [
      html.text("Landing"),
    ]),
    case model.route {
      route.Landing -> html.div([], [html.text("Landing")])
      route.Login -> {
        let assert Unauthenticated(UnauthenticatedForms(
          login: form,
          register: _,
        )) = model.auth

        view_login(form)
      }
      route.Register -> {
        let assert Unauthenticated(UnauthenticatedForms(
          login: _,
          register: form,
        )) = model.auth

        view_register(form)
      }
      route.Dashboard -> {
        let assert Authenticated(Metadata(user, _)) = model.auth
        html.div([], [
          html.p([], [html.text("Dashboard: "), html.text(user.username)]),
          html.button([event.on_click(message.UserLoggedOut)], [
            html.text("Logout"),
          ]),
        ])
      }
      route.Loading -> html.div([], [html.text("Loading...")])
      route.NotFound(uri) ->
        html.div([], [html.text("Not Found: "), html.text(uri.path)])
    },
  ])
}

fn view_login(form: f.Form) -> element.Element(message.Msg) {
  html.div([], [
    html.h1([], [html.text("Login")]),
    view_form_error(form),
    html.form([event.on_submit(message.UserSubmittedLogin)], [
      view_input(form, "email", "email", "Email"),
      view_input(form, "password", "password", "Password"),
      html.button([attribute.disabled(form.loading)], [
        case form.loading {
          True -> html.text("Logging in...")
          False -> html.text("Login")
        },
      ]),
    ]),
  ])
}

fn view_register(form: Form) -> element.Element(message.Msg) {
  html.div([], [
    html.h1([], [html.text("Register")]),
    view_form_error(form),
    html.form([event.on_submit(message.UserSubmittedRegister)], [
      view_input(form, "text", "username", "Username"),
      view_input(form, "email", "email", "Email"),
      view_input(form, "password", "password", "Password"),
      html.button([attribute.disabled(form.loading)], [
        case form.loading {
          True -> html.text("Registering...")
          False -> html.text("Register")
        },
      ]),
    ]),
  ])
}

fn view_form_error(form: Form) -> element.Element(message.Msg) {
  case form.error {
    option.Some(error) -> html.p([], [html.text(error)])
    option.None -> element.none()
  }
}

fn view_input(
  form: Form,
  is type_: String,
  name name: String,
  placeholder placeholder: String,
) -> element.Element(message.Msg) {
  html.div([], [
    html.label([attribute.for(name)], [html.text(name), html.text(":")]),
    html.input([
      attribute.type_(type_),
      attribute.id(name),
      attribute.name(name),
      attribute.placeholder(placeholder),
    ]),
    view_input_error(form, name),
  ])
}

fn view_input_error(form: Form, name: String) -> element.Element(message.Msg) {
  let state = form.field_state(form.form, name)
  case state, form.loading, form.error {
    Ok(Nil), _, _ | Error(_), True, _ | Error(_), False, option.Some(_) ->
      element.none()
    Error(message), _, _ -> html.p([], [html.text(message)])
  }
}

@external(javascript, "./ffi.mjs", "get_access_token")
fn get_access_token() -> Result(String, Nil)
