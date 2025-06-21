import app/api/effects
import app/route/dashboard/decoders
import app/route/dashboard/types.{type Pagination, type Snippet}
import gleam/http
import gleam/http/request
import gleam/int
import lustre/effect
import rsvp

pub fn fetch_public_snippets_effect(
  api_url: String,
  size: Int,
  page: Int,
  access_token: String,
  on_response handle_response: fn(
    Result(#(List(Snippet), Pagination), rsvp.Error),
  ) ->
    msg,
) -> effect.Effect(msg) {
  let handler =
    rsvp.expect_json(
      decoders.public_snippets_response_decoder(),
      handle_response,
    )
  let url =
    api_url
    <> "/snippets?size="
    <> int.to_string(size)
    <> "&page="
    <> int.to_string(page)
  let assert Ok(request) = request.to(url)

  request
  |> request.set_method(http.Get)
  |> effects.with_access_token(access_token)
  |> rsvp.send(handler)
}
