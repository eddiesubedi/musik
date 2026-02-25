import pog

pub fn init(db: pog.Connection) -> Nil {
  create_sessions(db)
  create_http_cache(db)
  create_hero_content(db)
  Nil
}

fn create_sessions(db: pog.Connection) -> Nil {
  let assert Ok(_) =
    pog.query(
      "CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        access_token TEXT NOT NULL DEFAULT '',
        refresh_token TEXT NOT NULL DEFAULT '',
        refreshed_at TIMESTAMPTZ DEFAULT now(),
        created_at TIMESTAMPTZ DEFAULT now()
      )",
    )
    |> pog.execute(db)
  Nil
}

fn create_http_cache(db: pog.Connection) -> Nil {
  let assert Ok(_) =
    pog.query(
      "CREATE TABLE IF NOT EXISTS http_cache (
        url          TEXT PRIMARY KEY,
        body         BYTEA NOT NULL,
        content_type TEXT NOT NULL DEFAULT '',
        fetched_at   TIMESTAMPTZ DEFAULT now()
      )",
    )
    |> pog.execute(db)
  Nil
}

fn create_hero_content(db: pog.Connection) -> Nil {
  let assert Ok(_) =
    pog.query(
      "CREATE TABLE IF NOT EXISTS hero_content (
        id TEXT PRIMARY KEY,
        imdb_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        imdb_rating TEXT NOT NULL DEFAULT '',
        genres TEXT NOT NULL DEFAULT '',
        media_type TEXT NOT NULL,
        background TEXT NOT NULL DEFAULT '',
        logo TEXT NOT NULL DEFAULT '',
        poster TEXT NOT NULL DEFAULT '',
        trailer_yt_id TEXT NOT NULL DEFAULT '',
        trailer_url TEXT NOT NULL DEFAULT '',
        trailer_audio_url TEXT NOT NULL DEFAULT '',
        created_at TIMESTAMPTZ DEFAULT now()
      )",
    )
    |> pog.execute(db)
  // Add trailer columns if table already exists without them
  let _ =
    pog.query(
      "ALTER TABLE hero_content ADD COLUMN IF NOT EXISTS trailer_url TEXT NOT NULL DEFAULT ''",
    )
    |> pog.execute(db)
  let _ =
    pog.query(
      "ALTER TABLE hero_content ADD COLUMN IF NOT EXISTS trailer_yt_id TEXT NOT NULL DEFAULT ''",
    )
    |> pog.execute(db)
  let _ =
    pog.query(
      "ALTER TABLE hero_content ADD COLUMN IF NOT EXISTS trailer_audio_url TEXT NOT NULL DEFAULT ''",
    )
    |> pog.execute(db)
  Nil
}
