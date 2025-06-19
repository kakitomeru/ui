import app/api/decoders
import gleam/io
import gleam/json
import rsvp

pub fn message_from_api_error(error: rsvp.Error) -> String {
  case error {
    rsvp.HttpError(response) -> {
      case response.body |> json.parse(decoders.api_error_decoder()) {
        Ok(message) -> message
        Error(_) -> "An unexpected error occurred. Please try again."
      }
    }
    rsvp.NetworkError ->
      "A network error occurred. Please check your connection."
    rsvp.BadBody -> {
      io.println_error(
        "[!] Received an unexpected response format from the server.",
      )
      "An unexpected error occurred. Please try again."
    }
    rsvp.BadUrl(url) -> {
      io.println_error("[!] Invalid URL.")
      echo url
      "An unexpected error occurred. Please try again."
    }
    rsvp.JsonError(decode_error) -> {
      io.println_error("[!] JSON decoding error.")
      echo decode_error
      "An unexpected error occurred. Please try again."
    }
    rsvp.UnhandledResponse(response) -> {
      io.println_error("[!] Received an unhandled response from the server.")
      echo response
      "An unexpected error occurred. Please try again."
    }
  }
}

pub fn status_code_from_api_error(error: rsvp.Error) -> Int {
  case error {
    rsvp.HttpError(response) -> response.status
    _ -> 500
  }
}
