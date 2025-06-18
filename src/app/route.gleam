import gleam/uri.{type Uri}

pub type Route {
  Landing

  Login
  Register

  Dashboard

  Loading
  NotFound(uri: uri.Uri)
}

pub fn parse_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    ["home"] -> Landing

    ["auth", "login"] -> Login
    ["auth", "register"] -> Register

    [] -> Dashboard

    _ -> NotFound(uri:)
  }
}
