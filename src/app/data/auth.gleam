pub type User {
  User(username: String, email: String)
}

pub type Tokens {
  Tokens(access_token: String, refresh_token: String)
}

pub type Metadata {
  Metadata(user: User, tokens: Tokens)
}

pub type Status {
  Unauthenticated
  Pending(access_token_from_storage: String)
  Authenticated(metadata: Metadata)
}
