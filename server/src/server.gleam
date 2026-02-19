import gleam/erlang/process
import lib/cache
import mist
import plumbing/db
import plumbing/refresher
import plumbing/router
import plumbing/session

pub fn main() {
  let db = db.connect()
  session.init(db)
  cache.start(db)
  refresher.start(db)

  let assert Ok(_) =
    router.handle(db)
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
