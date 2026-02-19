import gleam/erlang/process
import gleam/io
import gleam/list
import pog
import plumbing/auth
import plumbing/session
import plumbing/sql

/// How often to check for stale sessions (5 minutes in milliseconds).
const interval = 300_000

/// Start the background token refresher process.
pub fn start(db: pog.Connection) -> Nil {
  process.spawn(fn() { loop(db) })
  Nil
}

fn loop(db: pog.Connection) -> Nil {
  process.sleep(interval)
  refresh_stale_sessions(db)
  loop(db)
}

fn refresh_stale_sessions(db: pog.Connection) -> Nil {
  case sql.get_stale_sessions(db) {
    Ok(pog.Returned(_, sessions)) -> {
      list.each(sessions, fn(s) { refresh_session(db, s.id, s.refresh_token) })
    }
    Error(_) -> {
      io.println("[refresher] Failed to query stale sessions")
      Nil
    }
  }
}

fn refresh_session(
  db: pog.Connection,
  session_id: String,
  refresh_token: String,
) -> Nil {
  case auth.refresh_access_token(refresh_token) {
    Ok(#(new_access, new_refresh)) -> {
      case auth.get_userinfo(new_access) {
        Ok(#(name, email)) -> {
          let assert Ok(_) =
            sql.update_session_tokens(
              db,
              session_id,
              name,
              email,
              new_access,
              new_refresh,
            )
          Nil
        }
        Error(_) -> {
          io.println("[refresher] Userinfo failed for " <> session_id)
          session.remove(db, session_id)
        }
      }
    }
    Error(_) -> {
      io.println("[refresher] Refresh failed for " <> session_id)
      session.remove(db, session_id)
    }
  }
}
