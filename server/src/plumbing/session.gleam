import gleam/bit_array
import pog
import plumbing/sql

/// Generate a cryptographically random session ID.
pub fn generate_id() -> String {
  strong_rand_bytes(32)
  |> bit_array.base64_url_encode(False)
}

/// Store a session with tokens.
pub fn set(
  db: pog.Connection,
  session_id: String,
  name: String,
  email: String,
  access_token: String,
  refresh_token: String,
) -> Nil {
  let assert Ok(_) =
    sql.insert_session(db, session_id, name, email, access_token, refresh_token)
  Nil
}

/// Look up a session. Returns Ok(#(name, email)) or Error(Nil).
pub fn get(
  db: pog.Connection,
  session_id: String,
) -> Result(#(String, String), Nil) {
  case sql.get_session(db, session_id) {
    Ok(pog.Returned(_, [row])) -> Ok(#(row.name, row.email))
    _ -> Error(Nil)
  }
}

/// Delete a session.
pub fn remove(db: pog.Connection, session_id: String) -> Nil {
  let assert Ok(_) = sql.delete_session(db, session_id)
  Nil
}

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(n: Int) -> BitArray
