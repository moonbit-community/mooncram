///|
/// A user-facing parsing, validation or execution error.
///
/// The payload is the complete diagnostic message, optionally including a
/// source location. Use `error_text` to display it without the error wrapper.
pub(all) suberror Failure {
  /// Wrap a diagnostic message without changing its text.
  Failure(String)
}

///|
/// Return the message of a `Failure`, or the standard string representation of
/// any other error. No location or extra prefix is added.
///
/// ```mbt check
/// test {
///   assert_eq(
///     @diagnostic.error_text(
///       @diagnostic.located("README.md", 3, "invalid command"),
///     ),
///     "README.md:3: invalid command",
///   )
/// }
/// ```
pub fn error_text(error : Error) -> String {
  match error {
    Failure(message) => message
    _ => error.to_string()
  }
}

///|
/// Construct a diagnostic formatted as `file:line: message`.
///
/// `line` is a one-based source line number. This function only formats the
/// location; it neither reads the file nor validates the line number.
pub fn located(file : String, line : Int32, message : String) -> Failure {
  Failure("\{file}:\{line}: \{message}")
}
