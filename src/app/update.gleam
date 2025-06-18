import app/decode.{ApiError} as d
import app/effect as e
import app/form.{Form}
import app/message.{
  type Msg, ApiUserFetched, ApiUserLoggedIn, ApiUserRegistered,
  AppRouteInitialized, TokenRefreshedForRetry, UserLoggedOut, UserNavigatedTo,
  UserSubmittedLogin, UserSubmittedRegister,
} as m
import app/model.{type Model, App, model_with_route}
import app/route as r
import app/shared.{
  type Metadata, type User, Authenticated, Metadata, Tokens, Unauthenticated,
  UnauthenticatedForms,
}
import gleam/json
import gleam/option
import lustre/effect
import modem
import rsvp

type Update =
  #(Model, effect.Effect(Msg))

pub fn handle_update(model: Model, msg: Msg) -> Update {
  case msg {
    AppRouteInitialized(route) -> app_route_initialized(model, route)
    UserNavigatedTo(route) -> user_navigated_to(model, route)

    UserSubmittedLogin(data) -> user_submitted_login(model, data)
    ApiUserLoggedIn(Ok(metadata)) -> api_user_logged_in(model, metadata)
    ApiUserLoggedIn(Error(err)) -> api_user_logged_in_error(model, err)

    UserSubmittedRegister(data) -> user_submitted_register(model, data)
    ApiUserRegistered(Ok(_)) -> api_user_registered_success(model)
    ApiUserRegistered(Error(err)) -> api_user_registered_error(model, err)

    UserLoggedOut -> user_logged_out(model)

    ApiUserFetched(Ok(user)) -> api_user_fetched_success(model, user)
    ApiUserFetched(Error(err)) -> api_user_fetched_error(model, err)
    TokenRefreshedForRetry(Ok(new_access_token)) ->
      token_refreshed_for_retry(model, new_access_token)
    TokenRefreshedForRetry(Error(_)) -> token_refreshed_for_retry_error(model)
  }
}

fn app_route_initialized(model: Model, route: r.Route) -> Update {
  let model = model.validate_navigation(model, route)

  #(model, modem.init(fn(uri) { uri |> r.parse_route() |> m.UserNavigatedTo }))
}

fn user_navigated_to(model: Model, route: r.Route) -> Update {
  let model = model.validate_navigation(model, route)

  #(App(..model, retry_thunk_after_refresh: option.None), effect.none())
}

fn user_submitted_login(model: Model, data: List(#(String, String))) -> Update {
  let assert Unauthenticated(forms) = model.auth

  case d.decode_login_data(data) {
    Ok(d.LoginData(email, password)) -> {
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
        e.login_user(email, password, ApiUserLoggedIn),
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

fn api_user_logged_in(_: Model, metadata: Metadata) -> Update {
  set_tokens(metadata.tokens.access_token, metadata.tokens.refresh_token)
  #(
    App(
      route: r.Dashboard,
      auth: Authenticated(metadata),
      retry_thunk_after_refresh: option.None,
    ),
    effect.none(),
  )
}

fn api_user_logged_in_error(model: Model, err: rsvp.Error) -> Update {
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

fn user_submitted_register(
  model: Model,
  data: List(#(String, String)),
) -> Update {
  let assert Unauthenticated(forms) = model.auth

  case d.decode_register_data(data) {
    Ok(d.RegisterData(username, email, password)) -> {
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
        e.register_user(
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
              register: Form(..forms.register, form: form, error: option.None),
            ),
          ),
          retry_thunk_after_refresh: option.None,
        ),
        effect.none(),
      )
    }
  }
}

fn api_user_registered_success(model: Model) -> Update {
  let assert Unauthenticated(forms) = model.auth
  #(
    App(
      route: r.Login,
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

fn api_user_registered_error(model: Model, err: rsvp.Error) -> Update {
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

fn user_logged_out(_: Model) -> Update {
  remove_tokens()
  #(model_with_route(r.Login), effect.none())
}

fn api_user_fetched_success(model: Model, user: User) -> Update {
  let assert Ok(access_token) = get_access_token()
  let assert Ok(refresh_token) = get_refresh_token()

  #(
    App(
      ..model,
      auth: Authenticated(Metadata(user, Tokens(access_token, refresh_token))),
      retry_thunk_after_refresh: option.None,
    ),
    e.init_route(),
  )
}

fn api_user_fetched_error(model: Model, err: rsvp.Error) -> Update {
  {
    case extract_status_code(err) {
      401 -> {
        let retry_thunk = fn(new_access_token: String) {
          e.get_user_info(new_access_token, ApiUserFetched)
        }

        attempt_token_refresh(model, retry_thunk)
      }
      _ -> {
        remove_tokens()
        #(model_with_route(model.route), e.init_route())
      }
    }
  }
}

fn token_refreshed_for_retry(model: Model, new_access_token: String) -> Update {
  set_access_token(new_access_token)

  case model.retry_thunk_after_refresh {
    option.Some(thunk_to_run) -> {
      let retry_effect = thunk_to_run(new_access_token)

      #(App(..model, retry_thunk_after_refresh: option.None), retry_effect)
    }
    option.None -> #(model, e.get_user_info(new_access_token, ApiUserFetched))
  }
}

fn token_refreshed_for_retry_error(_: Model) -> Update {
  remove_tokens()
  #(model_with_route(r.Login), effect.none())
}

// Helpers

fn attempt_token_refresh(
  model: Model,
  retry_thunk: fn(String) -> effect.Effect(Msg),
) -> #(Model, effect.Effect(Msg)) {
  case get_refresh_token() {
    Ok(refresh_token) -> #(
      App(..model, retry_thunk_after_refresh: option.Some(retry_thunk)),
      e.refresh_access_token(refresh_token, TokenRefreshedForRetry),
    )
    Error(_) -> {
      remove_tokens()
      #(model_with_route(r.Login), effect.none())
    }
  }
}

fn extract_api_error_message(err: rsvp.Error) -> String {
  case err {
    rsvp.HttpError(response) -> {
      case response.body |> json.parse(d.api_error_decoder()) {
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

// FFI

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
