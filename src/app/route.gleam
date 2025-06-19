import app/data/auth
import gleam/uri
import lustre/effect
import modem

pub type Route {
  Landing

  Login
  Register

  Dashboard

  Loading
  NotFound(uri: uri.Uri)
}

pub fn parse_uri(uri: uri.Uri) -> Route {
  case uri.path_segments(uri.path) {
    ["home"] -> Landing

    ["login"] -> Login
    ["register"] -> Register

    [] -> Dashboard

    _ -> NotFound(uri)
  }
}

pub fn route_to_path(route: Route) -> String {
  case route {
    Landing -> "/home"
    Login -> "/login"
    Register -> "/register"
    Dashboard -> "/"
    NotFound(uri) -> uri.path
    // TODO: handle Loading maybe?
    _ -> ""
  }
}

pub fn determine_allowed_route(
  auth_status: auth.Status,
  attempted_route: Route,
) -> Route {
  case attempted_route, auth_status {
    Login, auth.Authenticated(_) | Register, auth.Authenticated(_) -> Dashboard
    Dashboard, auth.Unauthenticated | Dashboard, auth.Pending(_) -> Login
    Loading, auth.Authenticated(_) -> Dashboard
    Loading, auth.Unauthenticated | Loading, auth.Pending(_) -> Login
    _, _ -> attempted_route
  }
}

pub fn init_route_effect(
  on_route_parse handle_route_parse: fn(Route) -> msg,
) -> effect.Effect(msg) {
  use dispatch <- effect.from()
  let initial_parsed_route = case modem.initial_uri() {
    Ok(uri_data) -> parse_uri(uri_data)
    Error(Nil) -> Landing
  }

  dispatch(handle_route_parse(initial_parsed_route))
}
