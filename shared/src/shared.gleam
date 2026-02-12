import gleam/json
import gleam/dynamic/decode

pub type Anime {
  Anime(id: Int, title: String, episodes: Int)
}

pub fn anime_decorder() -> decode.Decoder(Anime) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use episodes <- decode.field("episodes", decode.int)

  decode.success(Anime(id: ,title:, episodes:))
}

pub fn anime_list_decorder() -> decode.Decoder(List(Anime)) {
  decode.list(anime_decorder())
}

pub fn anime_to_json(anime: Anime) -> json.Json {
  json.object([
    #("id", json.int(anime.id)),
    #("title", json.string(anime.title)),
    #("episodes", json.int(anime.episodes)),
  ])
}

pub fn anime_list_to_json(animes: List(Anime)) -> json.Json {
  json.array(animes, anime_to_json)
}