import gleam/erlang/process
import gleam/io
import gleam/result
import lib/cache
import lib/cinemeta/errors.{type FetchError}
import lib/cinemeta/operations as cinemeta
import lib/img
import lustre/effect.{type Effect}

// --- Data types ---

pub type Flags {
  Flags(name: String, email: String)
}

pub type HomePage {
  HomePage(hero: Hero)
}

pub type Hero {
  Hero(
    name: String,
    description: String,
    genres: List(String),
    year: String,
    score: String,
    banner: String,
    logo: String,
    banner_hue: Int,
  )
}

// --- Model ---

pub type Model {
  Loading(flags: Flags)
  Loaded(flags: Flags, detail: HomePage)
  Errored(flags: Flags, error: FetchError)
}

// --- Messages ---

pub type Msg {
  ApiResponded(Result(HomePage, FetchError))
}

// --- Effects ---

pub fn fetch_home() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    // Spawn so we don't block the Lustre actor initialiser.
    // effect.from callbacks run synchronously inside init — if this
    // blocks (cache miss → network fetch), mist's 500ms WS actor
    // timeout fires and kills the connection.
    process.spawn(fn() {
      io.println("[fetch_home] starting")
      let result =
        // cinemeta.get_series("tt3514596")
        // cinemeta.get_series("tt5363918")
        // cinemeta.get_series("tt13660958")
        cinemeta.get_random_series()
        |> result.map(fn(m) {
          // Check logo URL server-side because onerror is unreliable
          // in Lustre server components (src may be set before the
          // onerror handler is attached).
          let logo = case m.logo {
            "" -> {
              io.println("[fetch_home] logo: empty from API")
              ""
            }
            url -> {
              let proxied = img.url(url, "trim:10/")
              io.println("[fetch_home] logo check: " <> proxied)
              case cache.fetch_bytes(proxied) {
                Ok(_) -> {
                  io.println("[fetch_home] logo: OK")
                  url
                }
                Error(_) -> {
                  io.println("[fetch_home] logo: failed, falling back to text")
                  ""
                }
              }
            }
          }
          HomePage(hero: Hero(
            name: m.name,
            description: m.description,
            genres: m.genres,
            year: case m.year == "" {
              True -> ""
              False -> m.year
            },
            score: m.imdb_rating,
            banner: m.background,
            logo:,
            banner_hue: 220,
          ))
        })

      io.println("[fetch_home] done, dispatching")
      dispatch(ApiResponded(result))
    })
    Nil
  })
}
