import app/data/ffi
import gleam/io

pub type Env {
  Env(mode: AppMode, api_url: String)
}

pub type AppMode {
  Dev
  Prod
}

pub fn dev_env(api_url: String) -> Env {
  Env(mode: Dev, api_url:)
}

pub fn prod_env(api_url: String) -> Env {
  Env(mode: Prod, api_url:)
}

// pub fn debug(env: Env, message: String, any: a) -> a {
//   case env.mode {
//     Dev -> {
//       ffi.console_group(message)
//       echo any
//       ffi.console_group_end()

//       any
//     }
//     Prod -> any
//   }
// } 

pub fn start_debug(env: Env, title: String, handle_next: fn() -> b) -> b {
  case env.mode {
    Dev -> {
      ffi.console_group_collapsed(title)
      let result = handle_next()
      ffi.console_group_end()
      result
    }
    Prod -> handle_next()
  }
}

pub fn debug(env: Env, message: String, any: a) -> Env {
  case env.mode {
    Dev -> {
      ffi.console_group(message)
      io.debug(any)
      ffi.console_group_end()

      env
    }
    Prod -> env
  }
}
