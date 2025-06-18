import { Ok, Error } from "./gleam.mjs"

export function get_access_token() {
  const accessToken = window.localStorage.getItem("accessToken")
  if (accessToken === null) return new Error(undefined)
  return new Ok(accessToken)
}

export function get_refresh_token() {
  const refreshToken = window.localStorage.getItem("refreshToken")
  if (refreshToken === null) return new Error(undefined)
  return new Ok(refreshToken)
}

export function set_tokens(accessToken, refreshToken) {
  set_access_token(accessToken)
  set_refresh_token(refreshToken)
}

export function set_access_token(accessToken) {
  window.localStorage.setItem("accessToken", accessToken)
}

export function set_refresh_token(refreshToken) {
  window.localStorage.setItem("refreshToken", refreshToken)
}

export function remove_tokens() {
  window.localStorage.removeItem("accessToken")
  window.localStorage.removeItem("refreshToken")
}