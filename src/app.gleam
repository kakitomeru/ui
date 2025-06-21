// IMPORTS -------------------------------------------------------------------

import app/api/effects
import app/api/types
import app/data/auth
import app/data/env
import app/data/ffi
import app/route
import app/route/dashboard/dashboard
import app/route/login/login
import app/route/register/register
import gleam/option
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import modem
import rsvp

// MAIN ----------------------------------------------------------------------

pub fn main() -> Nil {
  let env = env.dev_env("http://localhost:8080/api/v1")

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", env)

  Nil
}

// MODEL ---------------------------------------------------------------------

pub type PageModel {
  LoginPage(login.Model)
  RegisterPage(register.Model)
  DashboardPage(dashboard.Model)

  GenericPlaceholderPage
  LoadingAppPage
}

pub type Model {
  Model(
    route: route.Route,
    auth_status: auth.Status,
    page_model: PageModel,
    retry_thunk_after_refresh: option.Option(fn(String) -> effect.Effect(Msg)),
    intended_route_after_auth: option.Option(route.Route),
    env: env.Env,
  )
}

pub fn with_retry_thunk(
  model: Model,
  retry_thunk: fn(String) -> effect.Effect(Msg),
) -> Model {
  Model(..model, retry_thunk_after_refresh: option.Some(retry_thunk))
}

pub fn clear_retry_thunk(model: Model) -> Model {
  Model(..model, retry_thunk_after_refresh: option.None)
}

pub fn init(env: env.Env) -> #(Model, effect.Effect(Msg)) {
  let inital_auth_status = case ffi.get_access_token() {
    Ok(access_token) -> auth.Pending(access_token)
    Error(_) -> auth.Unauthenticated
  }

  let model =
    Model(
      route: route.Loading,
      auth_status: inital_auth_status,
      page_model: LoadingAppPage,
      retry_thunk_after_refresh: option.None,
      intended_route_after_auth: option.None,
      env:,
    )

  let auth_effect = case inital_auth_status {
    auth.Pending(access_token) ->
      effects.fetch_user_info(model.env.api_url, access_token, ApiUserFetched)
    _ -> effect.none()
  }
  let initial_effect =
    effect.batch([auth_effect, route.init_route_effect(AppRouteInitialized)])

  #(model, initial_effect)
}

// UPDATE --------------------------------------------------------------------

pub type Msg {
  AppRouteInitialized(route.Route)
  UserNavigatedTo(route.Route)

  ApiUserFetched(Result(auth.User, rsvp.Error))
  TokenRefreshedForRetry(Result(String, rsvp.Error))

  UserLoggedOut

  LoginMsg(login.Msg)
  LoginAction(login.OutMsg)

  RegisterMsg(register.Msg)
  RegisterAction(register.OutMsg)

  DashboardMsg(dashboard.Msg)
  DashboardAction(dashboard.OutMsg)
}

/// Handles the route change by initializing the page model for the new route.
/// Also clears the retry thunk after refresh.
fn handle_route_change(
  model: Model,
  new_route: route.Route,
) -> #(Model, effect.Effect(Msg)) {
  let validated_route =
    route.determine_allowed_route(model.auth_status, new_route)

  let #(page_model, page_init_effect) =
    initialize_page_model_for_route(model.auth_status, validated_route)

  let new_model =
    Model(..model, route: validated_route, page_model:)
    |> clear_retry_thunk()

  #(new_model, page_init_effect)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    AppRouteInitialized(route) -> {
      let modem_effect =
        modem.init(fn(uri) { uri |> route.parse_uri() |> UserNavigatedTo })

      case model.auth_status {
        auth.Pending(_) -> {
          let new_model =
            Model(..model, intended_route_after_auth: option.Some(route))

          #(new_model, modem_effect)
        }
        _ -> {
          let #(updated_model, page_init_effect) =
            handle_route_change(model, route)

          let effect = effect.batch([page_init_effect, modem_effect])

          #(updated_model, effect)
        }
      }
    }
    UserNavigatedTo(route) -> {
      case model.auth_status {
        // If user is not authenticated, we need to wait for the auth status to
        // be updated before we can handle the route change.
        auth.Pending(_) -> {
          let new_model =
            Model(..model, intended_route_after_auth: option.Some(route))

          #(new_model, effect.none())
        }
        _ -> handle_route_change(model, route)
      }
    }

    ApiUserFetched(Ok(user)) -> {
      let assert Ok(access_token) = ffi.get_access_token()
      let assert Ok(refresh_token) = ffi.get_refresh_token()

      let metadata =
        auth.Metadata(user:, tokens: auth.Tokens(access_token:, refresh_token:))
      let new_auth_status = auth.Authenticated(metadata)

      let new_model =
        Model(..model, auth_status: new_auth_status) |> clear_retry_thunk()

      let new_route =
        model.intended_route_after_auth |> option.unwrap(model.route)
      let #(new_model, page_effect) = handle_route_change(new_model, new_route)

      let new_model = Model(..new_model, intended_route_after_auth: option.None)

      #(new_model, page_effect)
    }
    ApiUserFetched(Error(error)) -> {
      case types.status_code_from_api_error(error) {
        401 -> {
          let retry_thunk = fn(new_access_token) {
            effects.fetch_user_info(
              model.env.api_url,
              new_access_token,
              ApiUserFetched,
            )
          }

          attempt_token_refresh(model, retry_thunk)
        }
        _ -> {
          ffi.remove_tokens()

          let intended_route =
            model.intended_route_after_auth |> option.unwrap(model.route)

          let new_model =
            Model(
              ..model,
              auth_status: auth.Unauthenticated,
              intended_route_after_auth: option.None,
              retry_thunk_after_refresh: option.None,
            )

          let #(new_model, page_effect) =
            handle_route_change(new_model, intended_route)

          #(new_model, page_effect)
        }
      }
    }

    TokenRefreshedForRetry(Ok(new_access_token)) -> {
      ffi.set_access_token(new_access_token)

      case model.retry_thunk_after_refresh {
        option.Some(thunk) -> {
          let retry_effect = thunk(new_access_token)

          let new_model = model |> clear_retry_thunk()

          #(new_model, retry_effect)
        }
        option.None -> {
          let effect =
            effects.fetch_user_info(
              model.env.api_url,
              new_access_token,
              ApiUserFetched,
            )

          #(model, effect)
        }
      }
    }

    TokenRefreshedForRetry(Error(_)) -> {
      ffi.remove_tokens()

      let intended_route =
        model.intended_route_after_auth |> option.unwrap(model.route)

      let new_model =
        Model(
          ..model,
          auth_status: auth.Unauthenticated,
          intended_route_after_auth: option.None,
          retry_thunk_after_refresh: option.None,
        )

      let #(new_model, page_effect) =
        handle_route_change(new_model, intended_route)

      #(new_model, page_effect)
    }

    UserLoggedOut -> {
      ffi.remove_tokens()

      let new_model = Model(..model, auth_status: auth.Unauthenticated)

      handle_route_change(new_model, route.Login)
    }

    LoginMsg(login_msg) -> {
      use login_model <- unwrap_login_page_model(model)

      let #(new_login_model, login_effect, login_out_msg) =
        login.update(login_model, login_msg, model.env.api_url)

      let new_model = Model(..model, page_model: LoginPage(new_login_model))
      let out_msg_effect = case login_out_msg {
        option.Some(out_msg) ->
          effect.from(fn(dispatch) { dispatch(LoginAction(out_msg)) })
        option.None -> effect.none()
      }
      let effect =
        effect.batch([effect.map(login_effect, LoginMsg), out_msg_effect])

      #(new_model, effect)
    }
    LoginAction(login.LoginSucceeded(metadata)) -> {
      ffi.set_tokens(
        metadata.tokens.access_token,
        metadata.tokens.refresh_token,
      )

      let new_model =
        Model(
          ..model,
          auth_status: auth.Authenticated(metadata),
          intended_route_after_auth: option.None,
        )

      handle_route_change(new_model, route.Dashboard)
    }

    RegisterMsg(register_msg) -> {
      use register_model <- unwrap_register_page_model(model)

      let #(new_register_model, register_effect, register_out_msg) =
        register.update(register_model, register_msg, model.env.api_url)

      let new_model =
        Model(..model, page_model: RegisterPage(new_register_model))
      let out_msg_effect = case register_out_msg {
        option.Some(out_msg) ->
          effect.from(fn(dispatch) { dispatch(RegisterAction(out_msg)) })
        option.None -> effect.none()
      }
      let effect =
        effect.batch([effect.map(register_effect, RegisterMsg), out_msg_effect])

      #(new_model, effect)
    }
    RegisterAction(register_out_msg) -> {
      let register.UserRegistered(_user_id) = register_out_msg

      handle_route_change(model, route.Login)
    }

    DashboardMsg(dashboard_msg) -> {
      use dashboard_model <- unwrap_dashboard_page_model(model)
      let current_token = ffi.get_access_token()
      case current_token {
        Ok(access_token) -> {
          let #(new_dashboard_model, dashboard_effect, dashboard_out_msg) =
            dashboard.update(
              dashboard_model,
              dashboard_msg,
              access_token,
              model.env.api_url,
            )

          let new_model =
            Model(..model, page_model: DashboardPage(new_dashboard_model))
          let out_msg_effect = case dashboard_out_msg {
            option.Some(out_msg) ->
              effect.from(fn(dispatch) { dispatch(DashboardAction(out_msg)) })
            option.None -> effect.none()
          }
          let effect =
            effect.batch([
              effect.map(dashboard_effect, DashboardMsg),
              out_msg_effect,
            ])

          #(new_model, effect)
        }
        _ -> {
          ffi.remove_tokens()

          let new_model = Model(..model, auth_status: auth.Unauthenticated)

          handle_route_change(new_model, route.Login)
        }
      }
    }
    DashboardAction(dashboard_out_msg) -> {
      case dashboard_out_msg {
        dashboard.AuthenticationRequiredFor(retry_thunk) -> {
          let retry_thunk = fn(access_token) {
            retry_thunk(access_token) |> effect.map(DashboardMsg)
          }

          attempt_token_refresh(model, retry_thunk)
        }
      }
    }
  }
}

fn attempt_token_refresh(
  model: Model,
  retry_thunk: fn(String) -> effect.Effect(Msg),
) {
  case ffi.get_refresh_token() {
    Ok(refresh_token) -> {
      let new_auth_status =
        auth.Pending({
          case ffi.get_access_token() {
            Ok(t) -> t
            Error(_) -> ""
          }
        })

      let new_model =
        Model(..model, auth_status: new_auth_status)
        |> with_retry_thunk(retry_thunk)

      let effect =
        effects.refresh_access_token(
          model.env.api_url,
          refresh_token,
          TokenRefreshedForRetry,
        )

      #(new_model, effect)
    }
    Error(_) -> {
      ffi.remove_tokens()

      let new_model =
        Model(..model, auth_status: auth.Unauthenticated)
        |> clear_retry_thunk()

      let new_route =
        new_model.intended_route_after_auth |> option.unwrap(model.route)
      let #(new_model, page_effect) = handle_route_change(new_model, new_route)

      let new_model = Model(..new_model, intended_route_after_auth: option.None)

      #(new_model, page_effect)
    }
  }
}

type UnwrapPageModel(page_model) =
  fn(page_model) -> #(Model, effect.Effect(Msg))

fn unwrap_login_page_model(
  model: Model,
  handle_next: UnwrapPageModel(login.Model),
) -> #(Model, effect.Effect(Msg)) {
  case model.page_model {
    LoginPage(login_model) -> handle_next(login_model)
    _ -> #(model, effect.none())
  }
}

fn unwrap_register_page_model(
  model: Model,
  handle_next: UnwrapPageModel(register.Model),
) -> #(Model, effect.Effect(Msg)) {
  case model.page_model {
    RegisterPage(register_model) -> handle_next(register_model)
    _ -> #(model, effect.none())
  }
}

fn unwrap_dashboard_page_model(
  model: Model,
  handle_next: UnwrapPageModel(dashboard.Model),
) -> #(Model, effect.Effect(Msg)) {
  case model.page_model {
    DashboardPage(dashboard_model) -> handle_next(dashboard_model)
    _ -> #(model, effect.none())
  }
}

fn initialize_page_model_for_route(
  _auth_status: auth.Status,
  route: route.Route,
) -> #(PageModel, effect.Effect(Msg)) {
  case route {
    route.Login -> {
      let #(page_model, page_effect) = login.init()
      #(LoginPage(page_model), effect.map(page_effect, LoginMsg))
    }
    route.Register -> {
      let #(page_model, page_effect) = register.init()
      #(RegisterPage(page_model), effect.map(page_effect, RegisterMsg))
    }
    route.Dashboard -> {
      let #(page_model, page_effect) = dashboard.init()
      #(DashboardPage(page_model), effect.map(page_effect, DashboardMsg))
    }
    // Fallback for routes not yet componentized
    _ -> {
      #(GenericPlaceholderPage, effect.none())
    }
  }
}

// VIEW ----------------------------------------------------------------------
pub fn view(model: Model) -> element.Element(Msg) {
  let nav_links =
    html.header([], [
      html.nav([attribute.class("flex gap-2 text-cyan-500")], [
        html.a([attribute.href(route.route_to_path(route.Dashboard))], [
          html.text("Dashboard"),
        ]),
        html.a([attribute.href(route.route_to_path(route.Login))], [
          html.text("Login"),
        ]),
        html.a([attribute.href(route.route_to_path(route.Register))], [
          html.text("Register"),
        ]),
        html.a([attribute.href(route.route_to_path(route.Landing))], [
          html.text("Landing"),
        ]),
      ]),
    ])

  let page_content = case model.page_model {
    LoginPage(login_model) -> login.view(login_model) |> element.map(LoginMsg)
    RegisterPage(register_model) ->
      register.view(register_model) |> element.map(RegisterMsg)
    DashboardPage(dashboard_model) ->
      dashboard.view(dashboard_model) |> element.map(DashboardMsg)
    // TODO: Add other page models here
    GenericPlaceholderPage ->
      case model.route {
        route.Register -> html.h1([], [html.text("Register Page Placeholder")])
        route.Dashboard ->
          html.h1([], [html.text("Dashboard Page Placeholder")])
        route.Landing -> html.h1([], [html.text("Landing Page Placeholder")])
        route.NotFound(uri) ->
          html.h1([], [html.text("Not Found Placeholder: " <> uri.path)])
        _ -> html.h1([], [html.text("Unknown Page Placeholder")])
      }
    LoadingAppPage -> html.div([], [html.text("App Loading...")])
  }

  html.div([], [nav_links, page_content])
}
