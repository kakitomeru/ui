import app/route.{type Route}
import app/shared.{type Metadata, type User}
import rsvp

pub type Msg {
  AppRouteInitialized(Route)
  UserNavigatedTo(Route)

  UserSubmittedLogin(List(#(String, String)))
  ApiUserLoggedIn(Result(Metadata, rsvp.Error))

  UserSubmittedRegister(List(#(String, String)))
  ApiUserRegistered(Result(String, rsvp.Error))

  UserLoggedOut

  ApiUserFetched(Result(User, rsvp.Error))
  TokenRefreshedForRetry(Result(String, rsvp.Error))
}
