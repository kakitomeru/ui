import app/constants.{api_url}
import app/decode as d
import app/message.{type Msg, AppRouteInitialized}
import app/route.{Landing}
import app/shared.{type Metadata, type User}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import lustre/effect
import modem
import rsvp

pub fn init_route() -> effect.Effect(Msg) {
  use dispatch <- effect.from()
  let route = case modem.initial_uri() {
    Ok(uri) -> route.parse_route(uri)
    Error(_) -> Landing
  }

  dispatch(AppRouteInitialized(route))
}

pub fn register_user(
  username: String,
  email: String,
  password: String,
  on_response handle_response: fn(Result(String, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler =
    rsvp.expect_json(
      {
        use id <- decode.field("userId", decode.string)
        decode.success(id)
      },
      handle_response,
    )
  let body =
    json.object([
      #("username", json.string(username)),
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post(api_url <> "/auth/register", body, handler)
}

pub fn login_user(
  email: String,
  password: String,
  on_response handle_response: fn(Result(Metadata, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler = rsvp.expect_json(d.metadata_decoder(), handle_response)
  let body =
    json.object([
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post(api_url <> "/auth/login", body, handler)
}

pub fn get_user_info(
  access_token: String,
  on_response handle_response: fn(Result(User, rsvp.Error)) -> Msg,
) -> effect.Effect(Msg) {
  let handler =
    rsvp.expect_json(
      {
        use user <- decode.field("user", d.user_decoder())
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

pub fn refresh_access_token(
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
