import gleam/dynamic/decode
import gleam/json
import lustre/effect
import rsvp

pub fn register_user_effect(
  api_url: String,
  username: String,
  email: String,
  password: String,
  on_response handle_response: fn(Result(String, rsvp.Error)) -> msg,
) -> effect.Effect(msg) {
  let decoder = {
    use id <- decode.field("userId", decode.string)
    decode.success(id)
  }

  let handler = rsvp.expect_json(decoder, handle_response)
  let body =
    json.object([
      #("username", json.string(username)),
      #("email", json.string(email)),
      #("password", json.string(password)),
    ])

  rsvp.post(api_url <> "/auth/register", body, handler)
}
