import app/form.{type Form}

pub type Metadata {
  Metadata(user: User, tokens: Tokens)
}

pub type User {
  User(username: String, email: String)
}

pub type Tokens {
  Tokens(access_token: String, refresh_token: String)
}

pub type Auth {
  Unauthenticated(UnauthenticatedForms)
  Authenticated(Metadata)
}

pub type UnauthenticatedForms {
  UnauthenticatedForms(login: Form, register: Form)
}
