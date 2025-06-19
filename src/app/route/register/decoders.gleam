import formal/form

pub type RegisterData {
  RegisterData(username: String, email: String, password: String)
}

pub fn decode_register_data(
  data: List(#(String, String)),
) -> Result(RegisterData, form.Form) {
  form.decoding({
    use username <- form.parameter
    use email <- form.parameter
    use password <- form.parameter
    RegisterData(username, email, password)
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
