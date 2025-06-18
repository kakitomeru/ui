// IMPORTS --------------------------------------------------------------------

import formal/form
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request
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

const api_url = "http://localhost:8080/api/v1"

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

// MODEL ----------------------------------------------------------------------

pub type Model {
  App(
    route: Route,
    auth: Auth,
    retry_thunk_after_refresh: option.Option(fn(String) -> effect.Effect(Msg)),
  )
}

pub fn model_with_route(route: Route) -> Model {
  App(
    route: route,
    auth: Unauthenticated(UnauthenticatedForms(
      login: new_form(),
      register: new_form(),
    )),
    retry_thunk_after_refresh: option.None,
  )
}

pub type Auth {
  Unauthenticated(UnauthenticatedForms)
  Authenticated(Metadata)
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

pub type Metadata {
  Metadata(user: User, tokens: Tokens)
}

pub type User {
  User(username: String, email: String)
}

pub type Tokens {
  Tokens(access_token: String, refresh_token: String)
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

  decode.success(User(username:, email:))
}

pub fn user_register_decoder() -> Decoder(String) {
  use id <- decode.field("userId", decode.string)
  decode.success(id)
}

pub fn metadata_decoder() -> Decoder(Metadata) {
  use user <- decode.field("user", user_decoder())
  use access_token <- decode.field("accessToken", decode.string)
  use refresh_token <- decode.field("refreshToken", decode.string)
  decode.success(Metadata(user:, tokens: Tokens(access_token:, refresh_token:)))
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
  let access_token = get_access_token()
  let model = model_with_route(Loading)

  case access_token {
    Ok(access_token) -> #(model, get_user_info(access_token, ApiUserFetched))
    Error(Nil) -> #(model, init_route())
  }
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
  AppRouteInitialized(Route)
  UserNavigatedTo(Route)

  UserSubmittedLogin(List(#(String, String)))
  ApiUserLoggedIn(Result(Metadata, rsvp.Error))

  UserSubmittedRegister(List(#(String, String)))
  ApiUserRegistered(Result(String, rsvp.Error))

  UserLoggedOut

  ApiUserFetched(Result(User, rsvp.Error))
  TokenRefreshedForRetry(Result(String, rsvp.Error))
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ApiUserFetched(Ok(user)) -> {
      let assert Ok(access_token) = get_access_token()
      let assert Ok(refresh_token) = get_refresh_token()

      #(
        App(
          ..model,
          auth: Authenticated(Metadata(
            user,
            Tokens(access_token, refresh_token),
          )),
          retry_thunk_after_refresh: option.None,
        ),
        init_route(),
      )
    }
    ApiUserFetched(Error(err)) -> {
      case extract_status_code(err) {
        401 -> {
          let retry_thunk = fn(new_access_token: String) {
            get_user_info(new_access_token, ApiUserFetched)
          }

          attempt_token_refresh(model, retry_thunk)
        }
        _ -> {
          remove_tokens()
          #(model_with_route(model.route), init_route())
        }
      }
    }
    UserNavigatedTo(route) -> {
      let model = validate_navigation(model, route)

      #(App(..model, retry_thunk_after_refresh: option.None), effect.none())
    }
    AppRouteInitialized(route) -> {
      let model = validate_navigation(model, route)

      #(model, modem.init(fn(uri) { uri |> parse_route() |> UserNavigatedTo }))
    }
    ApiUserRegistered(Ok(_)) -> {
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
          retry_thunk_after_refresh: option.None,
        ),
        effect.none(),
      )
    }
    ApiUserRegistered(Error(err)) -> {
      let assert Unauthenticated(forms) = model.auth
      #(
        App(
          ..model,
          auth: Unauthenticated(
            UnauthenticatedForms(
              ..forms,
              register: Form(
                ..forms.register,
                loading: False,
                error: option.Some(extract_api_error_message(err)),
              ),
            ),
          ),
        ),
        effect.none(),
      )
    }
    ApiUserLoggedIn(Ok(metadata)) -> {
      set_tokens(metadata.tokens.access_token, metadata.tokens.refresh_token)
      #(
        App(
          route: Dashboard,
          auth: Authenticated(metadata),
          retry_thunk_after_refresh: option.None,
        ),
        effect.none(),
      )
    }
    ApiUserLoggedIn(Error(err)) -> {
      let assert Unauthenticated(forms) = model.auth
      #(
        App(
          ..model,
          auth: Unauthenticated(
            UnauthenticatedForms(
              ..forms,
              login: Form(
                ..forms.login,
                loading: False,
                error: option.Some(extract_api_error_message(err)),
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
              retry_thunk_after_refresh: option.None,
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
              retry_thunk_after_refresh: option.None,
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
              retry_thunk_after_refresh: option.None,
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
              retry_thunk_after_refresh: option.None,
            ),
            effect.none(),
          )
        }
      }
    }
    UserLoggedOut -> {
      remove_tokens()
      #(model_with_route(Login), effect.none())
    }
    TokenRefreshedForRetry(Ok(new_access_token)) -> {
      set_access_token(new_access_token)

      case model.retry_thunk_after_refresh {
        option.Some(thunk_to_run) -> {
          let retry_effect = thunk_to_run(new_access_token)

          #(App(..model, retry_thunk_after_refresh: option.None), retry_effect)
        }
        option.None -> #(model, get_user_info(new_access_token, ApiUserFetched))
      }
    }
    TokenRefreshedForRetry(Error(_)) -> {
      remove_tokens()
      #(model_with_route(Login), effect.none())
    }
  }
}

fn attempt_token_refresh(
  model: Model,
  retry_thunk: fn(String) -> effect.Effect(Msg),
) -> #(Model, effect.Effect(Msg)) {
  case get_refresh_token() {
    Ok(refresh_token) -> #(
      App(..model, retry_thunk_after_refresh: option.Some(retry_thunk)),
      refresh_access_token(refresh_token, TokenRefreshedForRetry),
    )
    Error(_) -> {
      remove_tokens()
      #(model_with_route(Login), effect.none())
    }
  }
}

fn extract_api_error_message(err: rsvp.Error) -> String {
  case err {
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
}

fn extract_status_code(err: rsvp.Error) -> Int {
  case err {
    rsvp.HttpError(response) -> response.status
    _ -> 500
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

  rsvp.post(api_url <> "/auth/register", body, handler)
}

fn login_user(
  email: String,
  password: String,
  on_response handle_response: fn(Result(Metadata, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler = rsvp.expect_json(metadata_decoder(), handle_response)
  let body =
    json.object([
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post(api_url <> "/auth/login", body, handler)
}

fn get_user_info(
  access_token: String,
  on_response handle_response: fn(Result(User, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler =
    rsvp.expect_json(
      {
        use user <- decode.field("user", user_decoder())
        decode.success(user)
      },
      handle_response,
    )

  let assert Ok(request) = request.to(api_url <> "/me")

  request
  |> request.set_method(http.Get)
  |> request.set_header("Authorization", "Bearer " <> access_token)
  |> rsvp.send(handler)
}

fn refresh_access_token(
  refresh_token: String,
  on_response handle_response: fn(Result(String, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler =
    rsvp.expect_json(
      {
        use access_token <- decode.field("accessToken", decode.string)
        decode.success(access_token)
      },
      handle_response,
    )
  let body = json.object([#("refreshToken", json.string(refresh_token))])

  rsvp.post(api_url <> "/auth/refresh", body, handler)
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
        let assert Authenticated(Metadata(user, _)) = model.auth
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
    view_form_error(form),
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
    view_form_error(form),
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

fn view_form_error(form: Form) -> element.Element(Msg) {
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
) -> element.Element(Msg) {
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

fn view_input_error(form: Form, name: String) -> element.Element(Msg) {
  let state = form.field_state(form.form, name)
  case state, form.loading, form.error {
    Ok(Nil), _, _ | Error(_), True, _ | Error(_), False, option.Some(_) ->
      element.none()
    Error(message), _, _ -> html.p([], [html.text(message)])
  }
}

// EXTERNAL -------------------------------------------------------------------

@external(javascript, "./ffi.mjs", "get_access_token")
fn get_access_token() -> Result(String, Nil)

@external(javascript, "./ffi.mjs", "get_refresh_token")
fn get_refresh_token() -> Result(String, Nil)

@external(javascript, "./ffi.mjs", "set_tokens")
fn set_tokens(access_token: String, refresh_token: String) -> Nil

@external(javascript, "./ffi.mjs", "set_access_token")
fn set_access_token(access_token: String) -> Nil

@external(javascript, "./ffi.mjs", "remove_tokens")
fn remove_tokens() -> Nil
