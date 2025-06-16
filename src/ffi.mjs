import { Ok, Error } from "./gleam.mjs"

export function get_localstorage_user() {
  const json = window.localStorage.getItem("user")
  if (json === null) return new Error(undefined)

  try {
    return new Ok(JSON.parse(json))
  } catch (e) {
    return new Error(undefined)
  }
}

export function set_localstorage_user(user) {
  window.localStorage.setItem("user", JSON.stringify(user))
}

export function remove_localstorage_user() {
  window.localStorage.removeItem("user")
}