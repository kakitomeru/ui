import app/shared.{type Metadata, type User, Metadata, Tokens, User}
import formal/form
import gleam/dynamic/decode.{type Decoder}

pub type ApiError {
  ApiError(String)
}

pub type LoginData {
  LoginData(email: String, password: String)
}

pub type RegisterData {
  RegisterData(username: String, email: String, password: String)
}

pub fn api_error_decoder() -> Decoder(ApiError) {
  use message <- decode.field("error", decode.string)
  decode.success(ApiError(message))
}

pub fn user_decoder() -> Decoder(User) {
  use username <- decode.field("username", decode.string)
  use email <- decode.field("email", decode.string)

  decode.success(User(username:, email:))
}

pub fn metadata_decoder() -> Decoder(Metadata) {
  use user <- decode.field("user", user_decoder())
  use access_token <- decode.field("accessToken", decode.string)
  use refresh_token <- decode.field("refreshToken", decode.string)
  decode.success(Metadata(user:, tokens: Tokens(access_token:, refresh_token:)))
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
