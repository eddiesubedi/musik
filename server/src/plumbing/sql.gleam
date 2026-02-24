//// This module contains the code to run the sql queries defined in
//// `./src/plumbing/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `count_hero_content` query
/// defined in `./src/plumbing/sql/count_hero_content.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CountHeroContentRow {
  CountHeroContentRow(total: Int)
}

/// Runs the `count_hero_content` query
/// defined in `./src/plumbing/sql/count_hero_content.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn count_hero_content(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(CountHeroContentRow), pog.QueryError) {
  let decoder = {
    use total <- decode.field(0, decode.int)
    decode.success(CountHeroContentRow(total:))
  }

  "SELECT count(*)::int as total
  FROM hero_content
  WHERE media_type = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `delete_hero_content` query
/// defined in `./src/plumbing/sql/delete_hero_content.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_hero_content(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "DELETE FROM hero_content
  WHERE media_type = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `delete_incomplete_heroes` query
/// defined in `./src/plumbing/sql/delete_incomplete_heroes.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_incomplete_heroes(
  db: pog.Connection,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "DELETE FROM hero_content
  WHERE name = ''
     OR description = ''
     OR year = ''
     OR imdb_rating = ''
     OR genres = ''
     OR background = ''
     OR logo = ''
     OR poster = '';
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

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

/// A row you get from running the `get_hero_content` query
/// defined in `./src/plumbing/sql/get_hero_content.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetHeroContentRow {
  GetHeroContentRow(
    id: String,
    imdb_id: String,
    name: String,
    description: String,
    year: String,
    imdb_rating: String,
    genres: String,
    media_type: String,
    background: String,
    logo: String,
    poster: String,
  )
}

/// Runs the `get_hero_content` query
/// defined in `./src/plumbing/sql/get_hero_content.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_hero_content(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
) -> Result(pog.Returned(GetHeroContentRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use imdb_id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.string)
    use year <- decode.field(4, decode.string)
    use imdb_rating <- decode.field(5, decode.string)
    use genres <- decode.field(6, decode.string)
    use media_type <- decode.field(7, decode.string)
    use background <- decode.field(8, decode.string)
    use logo <- decode.field(9, decode.string)
    use poster <- decode.field(10, decode.string)
    decode.success(GetHeroContentRow(
      id:,
      imdb_id:,
      name:,
      description:,
      year:,
      imdb_rating:,
      genres:,
      media_type:,
      background:,
      logo:,
      poster:,
    ))
  }

  "SELECT id, imdb_id, name, description, year, imdb_rating, genres, media_type, background, logo, poster
  FROM hero_content
  WHERE media_type = $1
  ORDER BY random()
  LIMIT $2;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
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

/// A row you get from running the `hero_content_age_minutes` query
/// defined in `./src/plumbing/sql/hero_content_age_minutes.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type HeroContentAgeMinutesRow {
  HeroContentAgeMinutesRow(age_minutes: Int)
}

/// Runs the `hero_content_age_minutes` query
/// defined in `./src/plumbing/sql/hero_content_age_minutes.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn hero_content_age_minutes(
  db: pog.Connection,
) -> Result(pog.Returned(HeroContentAgeMinutesRow), pog.QueryError) {
  let decoder = {
    use age_minutes <- decode.field(0, decode.int)
    decode.success(HeroContentAgeMinutesRow(age_minutes:))
  }

  "SELECT coalesce(
  extract(epoch FROM (now() - max(created_at))) / 60,
  999999
)::int AS age_minutes
FROM hero_content;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `insert_hero_content` query
/// defined in `./src/plumbing/sql/insert_hero_content.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_hero_content(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: String,
  arg_6: String,
  arg_7: String,
  arg_8: String,
  arg_9: String,
  arg_10: String,
  arg_11: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO hero_content (id, imdb_id, name, description, year, imdb_rating, genres, media_type, background, logo, poster)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
  ON CONFLICT (id) DO UPDATE SET
    background = EXCLUDED.background,
    logo = EXCLUDED.logo,
    poster = EXCLUDED.poster;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.text(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.text(arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.text(arg_11))
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
