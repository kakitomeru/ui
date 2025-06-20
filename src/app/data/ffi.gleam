@external(javascript, "../../ffi.mjs", "get_access_token")
pub fn get_access_token() -> Result(String, Nil)

@external(javascript, "../../ffi.mjs", "get_refresh_token")
pub fn get_refresh_token() -> Result(String, Nil)

@external(javascript, "../../ffi.mjs", "set_tokens")
pub fn set_tokens(access_token: String, refresh_token: String) -> Nil

@external(javascript, "../../ffi.mjs", "set_access_token")
pub fn set_access_token(access_token: String) -> Nil

@external(javascript, "../../ffi.mjs", "remove_tokens")
pub fn remove_tokens() -> Nil

@external(javascript, "../../ffi.mjs", "console_group")
pub fn console_group(message: String) -> Nil

@external(javascript, "../../ffi.mjs", "console_group_end")
pub fn console_group_end() -> Nil

@external(javascript, "../../ffi.mjs", "console_group_collapsed")
pub fn console_group_collapsed(message: String) -> Nil
