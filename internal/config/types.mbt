///|
pub(all) enum Stream {
  Stdout
  Stderr
  Merged
}

///|
pub(all) struct Config {
  stream : Stream
  stdin : String?
  env : Map[String, String]
  target : String
  timeout_ms : Int
}

///|
pub fn default_config() -> Config {
  { stream: Stdout, stdin: None, env: {}, target: "wasm", timeout_ms: 60000, }
}
