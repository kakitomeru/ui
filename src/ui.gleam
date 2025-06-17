// IMPORTS --------------------------------------------------------------------

import formal/form
import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/option
import gleam/uri.{type Uri}
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import modem
import rsvp

// MAIN -----------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

// MODEL ----------------------------------------------------------------------

pub type Model {
  App(route: Route, auth: Auth)
}

pub type Auth {
  Unauthenticated(UnauthenticatedForms)
  Authenticated(User)
}

pub type UnauthenticatedForms {
  UnauthenticatedForms(login: Form, register: Form)
}

pub type Form {
  Form(
    form: form.Form,
    loading: Bool,
    success: Bool,
    error: option.Option(String),
  )
}

fn new_form() -> Form {
  Form(form: form.new(), loading: False, success: False, error: option.None)
}

pub type User {
  User(
    username: String,
    email: String,
    access_token: String,
    refresh_token: String,
  )
}

pub type RegisterData {
  RegisterData(username: String, email: String, password: String)
}

pub type LoginData {
  LoginData(email: String, password: String)
}

pub fn decode_login_data(
  data: List(#(String, String)),
) -> Result(LoginData, form.Form) {
  form.decoding({
    use email <- form.parameter
    use password <- form.parameter
    LoginData(email:, password:)
  })
  |> form.with_values(data)
  |> form.field(
    "email",
    form.string
      |> form.and(form.must_not_be_empty)
      |> form.and(form.must_be_an_email),
  )
  |> form.field(
    "password",
    form.string
      |> form.and(form.must_not_be_empty)
      |> form.and(form.must_be_string_longer_than(7))
      |> form.and(form.must_be_string_shorter_than(21)),
  )
  |> form.finish()
}

pub fn decode_register_data(
  data: List(#(String, String)),
) -> Result(RegisterData, form.Form) {
  form.decoding({
    use username <- form.parameter
    use email <- form.parameter
    use password <- form.parameter
    RegisterData(username:, email:, password:)
  })
  |> form.with_values(data)
  |> form.field(
    "username",
    form.string
      |> form.and(form.must_not_be_empty)
      |> form.and(form.must_be_string_longer_than(2))
      |> form.and(form.must_be_string_shorter_than(21)),
  )
  |> form.field(
    "email",
    form.string
      |> form.and(form.must_not_be_empty)
      |> form.and(form.must_be_an_email),
  )
  |> form.field(
    "password",
    form.string
      |> form.and(form.must_not_be_empty)
      |> form.and(form.must_be_string_longer_than(7))
      |> form.and(form.must_be_string_shorter_than(21)),
  )
  |> form.finish()
}

pub fn user_decoder() -> Decoder(User) {
  use username <- decode.field("username", decode.string)
  use email <- decode.field("email", decode.string)
  decode.success(User(username:, email:, access_token: "", refresh_token: ""))
}

pub fn user_register_decoder() -> Decoder(String) {
  use id <- decode.field("userId", decode.string)
  decode.success(id)
}

pub fn user_login_decoder() -> Decoder(User) {
  use user <- decode.field("user", user_decoder())
  use access_token <- decode.field("accessToken", decode.string)
  use refresh_token <- decode.field("refreshToken", decode.string)
  decode.success(User(..user, access_token:, refresh_token:))
}

pub type Route {
  Landing

  Login
  Register

  Dashboard

  Loading
  NotFound(uri: uri.Uri)
}

pub fn init(_args: Nil) -> #(Model, effect.Effect(Msg)) {
  #(
    App(
      route: Loading,
      auth: Unauthenticated(UnauthenticatedForms(
        login: new_form(),
        register: new_form(),
      )),
    ),
    get_user(),
  )
}

pub type ApiError {
  ApiError(String)
}

pub fn api_error_decoder() -> Decoder(ApiError) {
  use message <- decode.field("error", decode.string)
  decode.success(ApiError(message))
}

// UPDATE ---------------------------------------------------------------------

pub type Msg {
  LocalStorageReturnedUser(Result(User, Nil))
  UserNavigatedTo(Route)
  AppRouteInitialized(Route)
  ApiUserRegistered(Result(String, rsvp.Error))
  ApiUserLoggedIn(Result(User, rsvp.Error))
  UserSubmittedLogin(List(#(String, String)))
  UserSubmittedRegister(List(#(String, String)))
  UserLoggedOut
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    LocalStorageReturnedUser(Ok(user)) -> {
      #(App(..model, auth: Authenticated(user)), init_route())
    }
    LocalStorageReturnedUser(Error(_)) -> {
      #(model, init_route())
    }
    UserNavigatedTo(route) -> {
      let model = validate_navigation(model, route)

      #(model, effect.none())
    }
    AppRouteInitialized(route) -> {
      let model = validate_navigation(model, route)

      #(model, modem.init(fn(uri) { uri |> parse_route() |> UserNavigatedTo }))
    }
    ApiUserRegistered(Ok(id)) -> {
      echo "User registered: " <> id

      let assert Unauthenticated(forms) = model.auth
      #(
        App(
          route: Login,
          auth: Unauthenticated(
            UnauthenticatedForms(
              ..forms,
              register: Form(..forms.register, loading: False, success: True),
            ),
          ),
        ),
        effect.none(),
      )
    }
    ApiUserRegistered(Error(err)) -> {
      let assert Unauthenticated(forms) = model.auth
      let error = case err {
        rsvp.HttpError(response) -> {
          case response.body |> json.parse(api_error_decoder()) {
            Ok(ApiError(message)) -> {
              message
            }
            Error(_) -> {
              "something went wrong, try again later"
            }
          }
        }
        _ -> {
          "something went wrong, try again later"
        }
      }
      #(
        App(
          ..model,
          auth: Unauthenticated(
            UnauthenticatedForms(
              ..forms,
              register: Form(
                ..forms.register,
                loading: False,
                error: option.Some(error),
              ),
            ),
          ),
        ),
        effect.none(),
      )
    }
    ApiUserLoggedIn(Ok(user)) -> {
      echo "User logged in: " <> user.username
      set_localstorage_user(user.access_token, user.refresh_token)

      #(App(route: Dashboard, auth: Authenticated(user)), effect.none())
    }
    ApiUserLoggedIn(Error(err)) -> {
      echo err

      let assert Unauthenticated(forms) = model.auth
      let error = case err {
        rsvp.HttpError(response) -> {
          case response.body |> json.parse(api_error_decoder()) {
            Ok(ApiError(message)) -> {
              message
            }
            Error(_) -> {
              "something went wrong, try again later"
            }
          }
        }
        _ -> {
          "something went wrong, try again later"
        }
      }

      #(
        App(
          ..model,
          auth: Unauthenticated(
            UnauthenticatedForms(
              ..forms,
              login: Form(
                ..forms.login,
                loading: False,
                error: option.Some(error),
              ),
            ),
          ),
        ),
        effect.none(),
      )
    }
    UserSubmittedLogin(data) -> {
      let assert Unauthenticated(forms) = model.auth

      case decode_login_data(data) {
        Ok(LoginData(email, password)) -> {
          #(
            App(
              ..model,
              auth: Unauthenticated(
                UnauthenticatedForms(
                  ..forms,
                  login: Form(..forms.login, loading: True, error: option.None),
                ),
              ),
            ),
            login_user(email, password, ApiUserLoggedIn),
          )
        }
        Error(form) -> {
          #(
            App(
              ..model,
              auth: Unauthenticated(
                UnauthenticatedForms(..forms, login: Form(..forms.login, form:)),
              ),
            ),
            effect.none(),
          )
        }
      }
    }
    UserSubmittedRegister(data) -> {
      let assert Unauthenticated(forms) = model.auth

      case decode_register_data(data) {
        Ok(RegisterData(username, email, password)) -> {
          #(
            App(
              ..model,
              auth: Unauthenticated(
                UnauthenticatedForms(
                  ..forms,
                  register: Form(
                    ..forms.register,
                    loading: True,
                    error: option.None,
                  ),
                ),
              ),
            ),
            register_user(
              username,
              email,
              password,
              on_response: ApiUserRegistered,
            ),
          )
        }
        Error(form) -> {
          #(
            App(
              ..model,
              auth: Unauthenticated(
                UnauthenticatedForms(
                  ..forms,
                  register: Form(
                    ..forms.register,
                    form: form,
                    error: option.None,
                  ),
                ),
              ),
            ),
            effect.none(),
          )
        }
      }
    }
    UserLoggedOut -> {
      remove_localstorage_user()
      #(
        App(
          route: Login,
          auth: Unauthenticated(UnauthenticatedForms(
            login: new_form(),
            register: new_form(),
          )),
        ),
        effect.none(),
      )
    }
  }
}

pub fn parse_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    ["home"] -> Landing

    ["auth", "login"] -> Login
    ["auth", "register"] -> Register

    [] -> Dashboard

    _ -> NotFound(uri:)
  }
}

fn validate_navigation(model: Model, route: Route) -> Model {
  case route, model.auth {
    Login, Authenticated(_) | Register, Authenticated(_) ->
      App(..model, route: Dashboard)

    Dashboard, Unauthenticated(_) -> App(..model, route: Login)

    _, _ -> App(..model, route: route)
  }
}

fn init_route() -> effect.Effect(Msg) {
  use dispatch <- effect.from()

  let route = case modem.initial_uri() {
    Ok(uri) -> parse_route(uri)
    Error(_) -> Landing
  }

  dispatch(AppRouteInitialized(route))
}

fn get_user() -> effect.Effect(Msg) {
  effect.from(do_get_user)
}

fn do_get_user(dispatch: fn(Msg) -> Nil) -> Nil {
  get_localstorage_user()
  |> promise.map(fn(response) {
    case response {
      Ok(dyn) -> {
        case decode.run(dyn, user_login_decoder()) {
          Ok(user) -> LocalStorageReturnedUser(Ok(user))
          Error(err) -> {
            echo err
            LocalStorageReturnedUser(Error(Nil))
          }
        }
      }
      Error(Nil) -> LocalStorageReturnedUser(Error(Nil))
    }
  })
  |> promise.tap(dispatch)

  Nil
}

fn register_user(
  username: String,
  email: String,
  password: String,
  on_response handle_response: fn(Result(String, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler = rsvp.expect_json(user_register_decoder(), handle_response)
  let body =
    json.object([
      #("username", json.string(username)),
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post("http://localhost:8080/api/v1/auth/register", body, handler)
}

fn login_user(
  email: String,
  password: String,
  on_response handle_response: fn(Result(User, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler = rsvp.expect_json(user_login_decoder(), handle_response)
  let body =
    json.object([
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post("http://localhost:8080/api/v1/auth/login", body, handler)
}

// VIEW -----------------------------------------------------------------------

fn view(model: Model) -> element.Element(Msg) {
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
      Landing -> html.div([], [html.text("Landing")])
      Login -> {
        let assert Unauthenticated(UnauthenticatedForms(
          login: form,
          register: _,
        )) = model.auth

        view_login(form)
      }
      Register -> {
        let assert Unauthenticated(UnauthenticatedForms(
          login: _,
          register: form,
        )) = model.auth

        view_register(form)
      }
      Dashboard -> {
        let assert Authenticated(user) = model.auth
        html.div([], [
          html.p([], [html.text("Dashboard: "), html.text(user.username)]),
          html.button([event.on_click(UserLoggedOut)], [html.text("Logout")]),
        ])
      }
      Loading -> html.div([], [html.text("Loading...")])
      NotFound(uri) ->
        html.div([], [html.text("Not Found: "), html.text(uri.path)])
    },
  ])
}

fn view_login(form: Form) -> element.Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Login")]),
    html.form([event.on_submit(UserSubmittedLogin)], [
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

fn view_register(form: Form) -> element.Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Register")]),
    case form.error {
      option.Some(error) -> html.p([], [html.text(error)])
      option.None -> element.none()
    },
    html.form([event.on_submit(UserSubmittedRegister)], [
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

fn view_input(
  form: Form,
  is type_: String,
  name name: String,
  placeholder placeholder: String,
) -> element.Element(Msg) {
  let state = form.field_state(form.form, name)
  html.div([], [
    html.label([attribute.for(name)], [html.text(name), html.text(":")]),
    html.input([
      attribute.type_(type_),
      attribute.id(name),
      attribute.name(name),
      attribute.placeholder(placeholder),
    ]),
    case state, form.loading, form.error {
      Ok(Nil), _, _ | Error(_), True, _ | Error(_), False, option.Some(_) ->
        element.none()
      Error(message), _, _ -> html.p([], [html.text(message)])
    },
  ])
}

// EXTERNAL -------------------------------------------------------------------

@external(javascript, "./ffi.mjs", "get_localstorage_user")
fn get_localstorage_user() -> Promise(Result(Dynamic, Nil))

@external(javascript, "./ffi.mjs", "set_localstorage_user")
fn set_localstorage_user(access_token: String, refresh_token: String) -> Nil

@external(javascript, "./ffi.mjs", "remove_localstorage_user")
fn remove_localstorage_user() -> Nil
