import gleam/int
import gleam/io
import gleam/string
import lib/cinemeta/errors.{type CinemetaErrors}
import lustre/effect.{type Effect}
import pog
import services/hero/hero_service

// --- Data types ---

pub type Flags {
  Flags(name: String, email: String, db: pog.Connection)
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
    poster: String,
    logo: String,
    banner_hue: Int,
    imdb_id: String,
  )
}

// --- Model ---

pub type Model {
  Loading(flags: Flags)
  Loaded(flags: Flags, detail: HomePage)
  Errored(flags: Flags, error: CinemetaErrors)
}

// --- Messages ---

pub type Msg {
  ApiResponded(Result(HomePage, CinemetaErrors))
}

// --- Effects ---

pub fn fetch_home(db: pog.Connection) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    io.println("[fetch_home] loading hero from DB")

    // Pick random type
    let media_type = case int.random(2) {
      0 -> "movie"
      _ -> "series"
    }

    let result = case hero_service.get_random_heroes(db, media_type, 1) {
      [hero] ->
        Ok(
          HomePage(hero: Hero(
            name: hero.name,
            description: hero.description,
            genres: string.split(hero.genres, ", "),
            year: hero.year,
            score: hero.imdb_rating,
            banner: hero.background,
            poster: hero.poster,
            logo: hero.logo,
            banner_hue: 220,
            imdb_id: hero.imdb_id,
          )),
        )
      _ -> {
        io.println("[fetch_home] no heroes in DB")
        Error(errors.NetworkError)
      }
    }

    io.println("[fetch_home] done, dispatching")
    dispatch(ApiResponded(result))
    Nil
  })
}
