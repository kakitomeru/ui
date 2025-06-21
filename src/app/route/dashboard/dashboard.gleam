import app/api/types
import app/route/dashboard/effects
import app/route/dashboard/types.{type Pagination, type Snippet} as _
import gleam/list
import gleam/option.{None, Some}
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/element/keyed
import lustre/event
import rsvp

pub type Model {
  Model(
    snippets: List(Snippet),
    pagination: option.Option(Pagination),
    loading: Bool,
    error: option.Option(String),
  )
}

pub fn init() -> #(Model, effect.Effect(Msg)) {
  let model = Model(snippets: [], pagination: None, loading: False, error: None)

  // TODO: more size per page
  let effect =
    effect.from(fn(dispatch) { dispatch(UserRequestedPublicSnippets(1, 3)) })

  #(model, effect)
}

pub type Msg {
  UserRequestedPublicSnippets(page: Int, size: Int)
  ApiFetchedPublicSnippets(Result(#(List(Snippet), Pagination), rsvp.Error))
}

pub type OutMsg {
  AuthenticationRequiredFor(retry_thunk: fn(String) -> effect.Effect(Msg))
}

pub fn update(
  model: Model,
  msg: Msg,
  api_url: String,
  access_token: String,
) -> #(Model, effect.Effect(Msg), option.Option(OutMsg)) {
  case msg {
    UserRequestedPublicSnippets(page, size) -> {
      let new_model = Model(..model, loading: True, error: None)
      let effect =
        effects.fetch_public_snippets_effect(
          api_url,
          size,
          page,
          access_token,
          ApiFetchedPublicSnippets,
        )

      #(new_model, effect, None)
    }
    ApiFetchedPublicSnippets(Ok(#(snippets, pagination))) -> {
      let new_snippets = list.append(model.snippets, snippets)

      let new_model =
        Model(
          ..model,
          snippets: new_snippets,
          pagination: Some(pagination),
          loading: False,
        )

      #(new_model, effect.none(), None)
    }
    ApiFetchedPublicSnippets(Error(err)) -> {
      case types.status_code_from_api_error(err) {
        401 -> {
          let retry_thunk = fn(access_token) {
            let #(page, size) =
              model.pagination
              |> option.map(fn(pagination) {
                #(pagination.current_page + 1, pagination.size)
              })
              |> option.unwrap(#(1, 3))

            effects.fetch_public_snippets_effect(
              api_url,
              size,
              page,
              access_token,
              ApiFetchedPublicSnippets,
            )
          }

          let out_msg = Some(AuthenticationRequiredFor(retry_thunk))

          #(model, effect.none(), out_msg)
        }
        _ -> {
          let new_model =
            Model(
              ..model,
              loading: False,
              error: Some(types.message_from_api_error(err)),
            )

          #(new_model, effect.none(), None)
        }
      }
    }
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Dashboard")]),
    case model.error {
      Some(error) -> html.text(error)
      None -> element.none()
    },
    keyed.ul(
      [],
      list.map(model.snippets, fn(s) {
        #(s.id, html.li([], [html.text("Title: "), html.text(s.title)]))
      }),
    ),
    case model.loading, model.pagination {
      False, Some(pagination) -> {
        case pagination.current_page == pagination.total_pages {
          True -> element.none()
          False ->
            html.button(
              [
                event.on_click(UserRequestedPublicSnippets(
                  pagination.current_page + 1,
                  pagination.size,
                )),
              ],
              [html.text("Load more")],
            )
        }
      }
      True, _ -> html.p([], [html.text("Loading...")])
      False, None -> element.none()
    },
  ])
}
