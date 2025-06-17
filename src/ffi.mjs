import { Ok, Error } from "./gleam.mjs"

export async function get_localstorage_user() {
  const json = window.localStorage.getItem("user")
  if (json === null) return new Error(undefined)

  try {
    const auth = JSON.parse(json)

    let response = await fetch("http://localhost:8080/api/v1/me", {
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${auth.accessToken}`,
      },
    })
    let body = await response.json()

    if (response.ok) {
      return new Ok({ ...body, accessToken: auth.accessToken, refreshToken: auth.refreshToken })
    }

    if (body.error !== "expired token") {
      return new Error(undefined)
    }

    response = await fetch("http://localhost:8080/api/v1/auth/refresh", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ refreshToken: auth.refreshToken }),
    })
    body = await response.json()
    if (response.ok) {
      const { accessToken } = body
      window.localStorage.setItem("user", JSON.stringify({ accessToken, refreshToken: auth.refreshToken }))
      
      let response = await fetch("http://localhost:8080/api/v1/me", {
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
      })
      body = await response.json()

      if (response.ok) {
        return new Ok({ user: body.user, accessToken, refreshToken: auth.refreshToken })
      }

      return new Error(undefined)
    }

    window.localStorage.removeItem("user")
    return new Error(undefined)
  } catch (e) {
    console.error(e)
    return new Error(undefined)
  }
}

export function set_localstorage_user(accessToken, refreshToken) {
  window.localStorage.setItem("user", JSON.stringify({ accessToken, refreshToken }))
}

export function remove_localstorage_user() {
  window.localStorage.removeItem("user")
}