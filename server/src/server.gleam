import envoy
import gleam/erlang/process
import lib/cache
import lib/img
import mist
import plumbing/db
import plumbing/init
import plumbing/refresher
import plumbing/router
import services/hero/hero_service
import services/scheduler

pub fn main() {
  let assert Ok(imgproxy_url) = envoy.get("IMGPROXY_URL")
  img.init(imgproxy_url)
  let db = db.connect()
  init.init(db)
  cache.start(db)
  refresher.start(db)

  [
    scheduler.Service(
      service: fn() { hero_service.start(db) },
      interval: 86_400_000,
    ),
  ]
  |> scheduler.init_scheduler()

  let assert Ok(_) =
    router.handle(db)
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
