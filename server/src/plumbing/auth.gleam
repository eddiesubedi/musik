import envoy
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/http
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/uri
import mist.{type Connection, type ResponseData}
import plumbing/session
import pog

const authorize_path = "/application/o/authorize/"

const token_path = "/application/o/token/"

const userinfo_path = "/application/o/userinfo/"

fn authentik_url() -> String {
  let assert Ok(url) = envoy.get("AUTHENTIK_URL")
  url
}

fn redirect_uri() -> String {
  let assert Ok(uri) = envoy.get("REDIRECT_URI")
  uri
}

fn client_id() -> String {
  let assert Ok(id) = envoy.get("AUTHENTIK_CLIENT_ID")
  id
}

fn client_secret() -> String {
  let assert Ok(secret) = envoy.get("AUTHENTIK_CLIENT_SECRET")
  secret
}

// --- Public handlers ---

/// Redirect to Authentik login page.
pub fn login(_req: Request(Connection)) -> Response(ResponseData) {
  let query =
    uri.query_to_string([
      #("client_id", client_id()),
      #("response_type", "code"),
      #("redirect_uri", redirect_uri()),
      #("scope", "openid profile email offline_access"),
    ])

  redirect(authentik_url() <> authorize_path <> "?" <> query)
}

/// Handle OAuth2 callback from Authentik.
pub fn callback(
  req: Request(Connection),
  db: pog.Connection,
) -> Response(ResponseData) {
  let result = {
    use query <- result.try(request.get_query(req))
    use code <- result.try(list.key_find(query, "code"))
    use tokens <- result.try(exchange_code(code))
    let #(access_token, refresh_token) = tokens
    use user <- result.try(get_userinfo(access_token))
    Ok(#(user, access_token, refresh_token))
  }

  case result {
    Ok(#(#(name, email), access_token, refresh_token)) -> {
      let session_id = session.generate_id()
      session.set(db, session_id, name, email, access_token, refresh_token)

      redirect("/")
      |> response.set_cookie(
        "session",
        session_id,
        cookie.Attributes(
          max_age: option.Some(86_400),
          domain: option.None,
          path: option.Some("/"),
          secure: False,
          http_only: True,
          same_site: option.Some(cookie.Lax),
        ),
      )
    }
    Error(_) -> redirect("/auth/login")
  }
}

/// Delete session and redirect to login.
pub fn logout(
  req: Request(Connection),
  db: pog.Connection,
) -> Response(ResponseData) {
  let cookies = request.get_cookies(req)
  case list.key_find(cookies, "session") {
    Ok(session_id) -> session.remove(db, session_id)
    Error(_) -> Nil
  }

  redirect("/auth/login")
  |> response.set_cookie(
    "session",
    "",
    cookie.Attributes(
      max_age: option.Some(0),
      domain: option.None,
      path: option.Some("/"),
      secure: False,
      http_only: True,
      same_site: option.Some(cookie.Lax),
    ),
  )
}

/// Check if request has a valid session. Returns Ok(#(name, email)) or Error.
pub fn get_user(
  req: Request(Connection),
  db: pog.Connection,
) -> Result(#(String, String), Nil) {
  let cookies = request.get_cookies(req)
  use session_id <- result.try(list.key_find(cookies, "session"))
  session.get(db, session_id)
}

/// Redirect to login page.
pub fn redirect_to_login() -> Response(ResponseData) {
  redirect("/auth/login")
}

// --- Internal ---

fn exchange_code(code: String) -> Result(#(String, String), Nil) {
  let body =
    uri.query_to_string([
      #("grant_type", "authorization_code"),
      #("code", code),
      #("redirect_uri", redirect_uri()),
      #("client_id", client_id()),
      #("client_secret", client_secret()),
    ])

  token_request(body)
}

/// Exchange a refresh token for new access + refresh tokens.
pub fn refresh_access_token(
  refresh_token: String,
) -> Result(#(String, String), Nil) {
  let body =
    uri.query_to_string([
      #("grant_type", "refresh_token"),
      #("refresh_token", refresh_token),
      #("client_id", client_id()),
      #("client_secret", client_secret()),
    ])

  token_request(body)
}

fn token_request(body: String) -> Result(#(String, String), Nil) {
  let assert Ok(req) = request.to(authentik_url() <> token_path)
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/x-www-form-urlencoded")
    |> request.set_body(body)

  case httpc.send(req) {
    Ok(resp) -> {
      let decoder = {
        use access_token <- decode.field("access_token", decode.string)
        use refresh_token <- decode.optional_field(
          "refresh_token",
          "",
          decode.string,
        )
        decode.success(#(access_token, refresh_token))
      }
      json.parse(resp.body, decoder) |> result.replace_error(Nil)
    }
    Error(_) -> Error(Nil)
  }
}

pub fn get_userinfo(access_token: String) -> Result(#(String, String), Nil) {
  let assert Ok(req) = request.to(authentik_url() <> userinfo_path)
  let req =
    req
    |> request.set_header("authorization", "Bearer " <> access_token)

  case httpc.send(req) {
    Ok(resp) -> {
      let decoder = {
        use name <- decode.field("name", decode.string)
        use email <- decode.field("email", decode.string)
        decode.success(#(name, email))
      }
      json.parse(resp.body, decoder) |> result.replace_error(Nil)
    }
    Error(_) -> Error(Nil)
  }
}

fn redirect(url: String) -> Response(ResponseData) {
  response.new(302)
  |> response.set_header("location", url)
  |> response.set_body(mist.Bytes(bytes_tree.new()))
}
