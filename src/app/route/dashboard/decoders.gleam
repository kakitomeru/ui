import app/route/dashboard/types.{
  type Pagination, type Snippet, Pagination, Snippet,
}
import gleam/dynamic/decode

pub fn public_snippets_response_decoder() -> decode.Decoder(
  #(List(Snippet), Pagination),
) {
  use snippets <- decode.field("snippets", decode.list(snippet_decoder()))
  use pagination <- decode.field("pagination", pagination_decoder())

  decode.success(#(snippets, pagination))
}

pub fn snippet_decoder() -> decode.Decoder(Snippet) {
  use id <- decode.field("id", decode.string)
  use owner_id <- decode.field("ownerId", decode.string)
  use title <- decode.field("title", decode.string)
  use content <- decode.field("content", decode.string)
  use language_hint <- decode.field("languageHint", decode.string)
  use is_public <- decode.field("isPublic", decode.bool)
  use created_at <- decode.field("createdAt", decode.string)
  use updated_at <- decode.field("updatedAt", decode.string)

  decode.success(Snippet(
    id,
    owner_id,
    title,
    content,
    language_hint,
    is_public,
    created_at,
    updated_at,
  ))
}

pub fn pagination_decoder() -> decode.Decoder(Pagination) {
  use size <- decode.field("size", decode.int)
  use total_items <- decode.field("totalItems", decode.int)
  use current_page <- decode.field("currentPage", decode.int)
  use total_pages <- decode.field("totalPages", decode.int)

  decode.success(Pagination(size, total_items, current_page, total_pages))
}
