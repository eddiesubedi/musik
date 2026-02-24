pub type TmdbError {
  RequestError(error: String)
  JsonDecodeError
}
