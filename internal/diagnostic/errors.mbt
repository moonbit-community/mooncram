///|
pub(all) suberror Failure {
  Failure(String)
}

///|
pub fn error_text(error : Error) -> String {
  match error {
    Failure(message) => message
    _ => error.to_string()
  }
}

///|
pub fn located(file : String, line : Int, message : String) -> Failure {
  Failure("\{file}:\{line}: \{message}")
}
