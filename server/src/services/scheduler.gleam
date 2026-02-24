import exception
import gleam/erlang/process
import gleam/list

pub type Service {
  Service(service: fn() -> Nil, interval: Int)
}

pub fn init_scheduler(tasks: List(Service)) {
  list.each(tasks, fn(task) {
    process.spawn(fn() {
      task.service()
      loop(task.service, task.interval)
    })
  })
  Nil
}

fn loop(service, interval: Int) {
  process.sleep(interval)
  let _ = exception.rescue(service)
  loop(service, interval)
}
