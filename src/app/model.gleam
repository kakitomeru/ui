import app/form
import app/message.{type Msg}
import app/route.{type Route} as r
import app/shared.{
  type Auth, Authenticated, Unauthenticated, UnauthenticatedForms,
}
import gleam/option
import lustre/effect

pub type Model {
  App(
    route: Route,
    auth: Auth,
    retry_thunk_after_refresh: option.Option(fn(String) -> effect.Effect(Msg)),
  )
}

pub fn model_with_route(route: Route) -> Model {
  App(
    route: route,
    auth: Unauthenticated(UnauthenticatedForms(
      login: form.new_form(),
      register: form.new_form(),
    )),
    retry_thunk_after_refresh: option.None,
  )
}

pub fn validate_navigation(model: Model, route: Route) -> Model {
  case route, model.auth {
    r.Login, Authenticated(_) | r.Register, Authenticated(_) ->
      App(..model, route: r.Dashboard)

    r.Dashboard, Unauthenticated(_) -> App(..model, route: r.Login)

    _, _ -> App(..model, route: route)
  }
}
