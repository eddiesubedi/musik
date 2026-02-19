import pog

pub type User {
  User(name: String, email: String)
}

pub type Context {
  Context(db: pog.Connection, user: User)
}
