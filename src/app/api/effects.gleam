import app/api/decoders
import app/data/auth
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import lustre/effect
import rsvp

pub fn with_access_token(
  request: request.Request(a),
  access_token: String,
) -> request.Request(a) {
  request.set_header(request, "Authorization", "Bearer " <> access_token)
}

pub fn fetch_user_info(
  api_url: String,
  access_token: String,
  on_response handle_response: fn(Result(auth.User, rsvp.Error)) -> msg,
) -> effect.Effect(msg) {
  let decoder = {
    use user <- decode.field("user", decoders.user_decoder())
    decode.success(user)
  }

  let handler = rsvp.expect_json(decoder, handle_response)
  let assert Ok(request) = request.to(api_url <> "/me")

  request
  |> request.set_method(http.Get)
  |> with_access_token(access_token)
  |> rsvp.send(handler)
}

pub fn refresh_access_token(
  api_url: String,
  refresh_token: String,
  on_response handle_response: fn(Result(String, rsvp.Error)) -> msg,
) -> effect.Effect(msg) {
  let decoder = {
    use access_token <- decode.field("accessToken", decode.string)
    decode.success(access_token)
  }

  let handler = rsvp.expect_json(decoder, handle_response)
  let body = json.object([#("refreshToken", json.string(refresh_token))])

  rsvp.post(api_url <> "/auth/refresh", body, handler)
}
