import envoy
import gleam/erlang/process
import pog

/// Start the database connection pool. Call once on startup.
pub fn connect() -> pog.Connection {
  let assert Ok(database_url) = envoy.get("DATABASE_URL")
  let pool_name = process.new_name(prefix: "db")
  let assert Ok(config) = pog.url_config(pool_name, database_url)

  let assert Ok(started) =
    config
    |> pog.pool_size(10)
    |> pog.start

  started.data
}
