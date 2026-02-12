import gleam/erlang/process
import mist
import plumbing/router

pub fn main() {
  let assert Ok(_) =
    router.handle
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
