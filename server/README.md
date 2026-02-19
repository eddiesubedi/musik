# Muskia Server

Gleam server using Lustre server components, Mist, and PostgreSQL.

## Quick Start

```sh
# From the muskia root directory
./server.sh
```

This loads `.env`, runs Tailwind, and starts the server with hot reload on `http://localhost:3000`.

## Environment Variables

All env vars live in `.env` at the project root (not in `server/`). The `server.sh` script sources it automatically.

```
AUTHENTIK_CLIENT_ID=<your-client-id>
AUTHENTIK_CLIENT_SECRET=<your-client-secret>
DATABASE_URL=postgresql://gleam:Gleam2828_@192.168.139.102/muskia?sslmode=require
```

## Authentication (Authentik + OAuth2)

Auth is handled via OAuth2/OIDC with Authentik running at `http://192.168.139.62:9000`.

### How it works

1. Unauthenticated user hits a protected route
2. Router redirects to `/auth/login`
3. `/auth/login` redirects to Authentik's authorize endpoint
4. User logs in on Authentik
5. Authentik redirects to `/auth/callback?code=...`
6. Server exchanges code for access token (POST to Authentik's token endpoint)
7. Server fetches user info (name, email) from Authentik's userinfo endpoint
8. Server creates a session in PostgreSQL and sets a `session` cookie
9. User is redirected to `/` with the cookie — now authenticated

### Route protection

In `plumbing/router.gleam`, the `case` statement determines what's public vs protected:

- **Public**: `/auth/*`, `/dev/reload`
- **Protected** (behind `auth.get_user` check): everything else — pages, websockets, static assets

### Key files

- `plumbing/auth.gleam` — OAuth2 flow (login, callback, logout, get_user)
- `plumbing/session.gleam` — session CRUD using Postgres
- `plumbing/context.gleam` — `Context` type carrying `db` + `user` through handlers

### Authentik setup

The Authentik application is called `animu` with a Confidential OAuth2 provider. Redirect URI is `http://localhost:3000/auth/callback`. Scopes: `openid profile email`.

## Database (PostgreSQL + pog + squirrel)

### Connection

`plumbing/db.gleam` reads `DATABASE_URL` from env, creates a connection pool via `pog`, and returns a `pog.Connection`. This is called once in `server.gleam` on startup.

### Squirrel (type-safe SQL)

SQL queries live as `.sql` files in `src/plumbing/sql/`. Squirrel reads them, connects to Postgres, checks the types, and generates `src/plumbing/sql.gleam` with fully typed functions and row types.

**To add a new query:**

1. Create a `.sql` file in `src/plumbing/sql/`:
   ```sql
   -- src/plumbing/sql/get_anime_by_id.sql
   select id, title, episodes from anime where id = $1
   ```

2. Run squirrel (needs `DATABASE_URL` set):
   ```sh
   DATABASE_URL='postgresql://gleam:Gleam2828_@192.168.139.102/muskia?sslmode=require' gleam run -m squirrel
   ```

3. Use the generated function:
   ```gleam
   import plumbing/sql
   let assert Ok(pog.Returned(_, [row])) = sql.get_anime_by_id(ctx.db, 1)
   // row.id, row.title, row.episodes are all typed
   ```

**To modify an existing query:** edit the `.sql` file and re-run squirrel. The generated `sql.gleam` is overwritten — never edit it by hand.

**Requires Postgres 16+.** Currently running Postgres 18 at `192.168.139.102`.

### Schema changes

The `sessions` table is created automatically by `session.init(db)` on server startup. For other tables, create them manually via psql or add a migration to `session.init`.

## Context

`plumbing/context.gleam` defines:

```gleam
pub type Context {
  Context(db: pog.Connection, user: User)
}

pub type User {
  User(name: String, email: String)
}
```

The router builds a `Context` after authenticating the user and passes it to all page handlers. Access `ctx.db` for database queries and `ctx.user` for the logged-in user.

## Project Structure

```
server/src/
  server.gleam                  # Entry point — connects DB, starts Mist
  components/
    homepage.gleam              # Lustre server component wiring
    homepage/
      model.gleam               # Types, messages, effects
      hero.gleam                # Hero view
  pages/
    home.gleam                  # Page handlers + route definition
    layout.gleam                # HTML shell (head, body wrapper)
  plumbing/
    router.gleam                # Request routing + auth gate
    route.gleam                 # Route type, builder, dispatcher
    auth.gleam                  # OAuth2 flow with Authentik
    session.gleam               # Session CRUD (Postgres-backed)
    context.gleam               # Context + User types
    db.gleam                    # Postgres connection pool
    ws.gleam                    # WebSocket plumbing for server components
    sql.gleam                   # [GENERATED] squirrel output — do not edit
    sql/
      get_session.sql           # Session lookup query
      insert_session.sql        # Session upsert query
      delete_session.sql        # Session delete query
  dev/
    reload.gleam                # Dev hot-reload over WebSocket
    dev_ffi.erl                 # Erlang FFI for file mtime
```

## Adding a New Page

1. Create `src/pages/about.gleam`:
   ```gleam
   pub fn routes() -> route.Route {
     route.new(page)
   }

   pub fn page(_req, ctx: Context) -> Response(ResponseData) {
     layout.render(title: "About", head: [], body: [
       html.h1([], [html.text("Hello " <> ctx.user.name)]),
     ])
   }
   ```

2. Add one line in `plumbing/router.gleam`:
   ```gleam
   route.dispatch(req, ctx, segments, [
     #("", home.routes()),
     #("about", about.routes()),   // <-- this
   ])
   ```
