import app/data/auth
import gleam/dynamic/decode.{type Decoder}

pub fn user_decoder() -> Decoder(auth.User) {
  use username <- decode.field("username", decode.string)
  use email <- decode.field("email", decode.string)
  decode.success(auth.User(username, email))
}

pub fn metadata_decoder() -> Decoder(auth.Metadata) {
  use user <- decode.field("user", user_decoder())
  use access_token <- decode.field("accessToken", decode.string)
  use refresh_token <- decode.field("refreshToken", decode.string)

  let tokens = auth.Tokens(access_token, refresh_token)
  decode.success(auth.Metadata(user, tokens))
}

pub fn api_error_decoder() -> Decoder(String) {
  use message <- decode.field("error", decode.string)
  decode.success(message)
}
