import app/api/decoders
import app/data/auth
import gleam/json
import lustre/effect
import rsvp

pub fn login_user_effect(
  api_url: String,
  email: String,
  password: String,
  on_response handle_response: fn(Result(auth.Metadata, rsvp.Error)) -> msg,
) -> effect.Effect(msg) {
  let handler =
    rsvp.expect_json(decoders.login_response_decoder(), handle_response)
  let body =
    json.object([
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post(api_url <> "/auth/login", body, handler)
}
