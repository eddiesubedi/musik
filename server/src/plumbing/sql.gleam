//// This module contains the code to run the sql queries defined in
//// `./src/plumbing/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// Delete a session by its ID.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_session(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Delete a session by its ID.
delete from sessions
where id = $1
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_session` query
/// defined in `./src/plumbing/sql/get_session.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetSessionRow {
  GetSessionRow(name: String, email: String)
}

/// Look up a session by its ID.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_session(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(GetSessionRow), pog.QueryError) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    use email <- decode.field(1, decode.string)
    decode.success(GetSessionRow(name:, email:))
  }

  "-- Look up a session by its ID.
select name, email
from sessions
where id = $1
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_stale_sessions` query
/// defined in `./src/plumbing/sql/get_stale_sessions.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetStaleSessionsRow {
  GetStaleSessionsRow(id: String, refresh_token: String)
}

/// Get sessions that haven't been refreshed in over 1 hour.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_stale_sessions(
  db: pog.Connection,
) -> Result(pog.Returned(GetStaleSessionsRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use refresh_token <- decode.field(1, decode.string)
    decode.success(GetStaleSessionsRow(id:, refresh_token:))
  }

  "-- Get sessions that haven't been refreshed in over 1 hour.
select id, refresh_token
from sessions
where refreshed_at < now() - interval '1 hour'
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Insert or update a session with tokens.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_session(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Insert or update a session with tokens.
insert into sessions (id, name, email, access_token, refresh_token, refreshed_at)
values ($1, $2, $3, $4, $5, now())
on conflict (id) do update set name = $2, email = $3, access_token = $4, refresh_token = $5, refreshed_at = now()
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Update a session's tokens and user info after a refresh.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn update_session_tokens(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Update a session's tokens and user info after a refresh.
update sessions
set name = $2, email = $3, access_token = $4, refresh_token = $5, refreshed_at = now()
where id = $1
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
