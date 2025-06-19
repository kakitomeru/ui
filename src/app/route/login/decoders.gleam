import formal/form

pub type LoginData {
  LoginData(email: String, password: String)
}

pub fn decode_login_data(
  data: List(#(String, String)),
) -> Result(LoginData, form.Form) {
  form.decoding({
    use email <- form.parameter
    use password <- form.parameter
    LoginData(email, password)
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
