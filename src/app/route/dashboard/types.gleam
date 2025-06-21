pub type Snippet {
  Snippet(
    id: String,
    owner_id: String,
    title: String,
    content: String,
    language_hint: String,
    is_public: Bool,
    created_at: String,
    updated_at: String,
  )
}

pub type Pagination {
  Pagination(size: Int, total_items: Int, current_page: Int, total_pages: Int)
}
