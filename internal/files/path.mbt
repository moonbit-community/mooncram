///|
/// Normalize `name`, resolving relative paths against `directory`.
///
/// Absolute names ignore `directory`. Resolution is lexical: it does not check
/// existence, follow symlinks or make a relative `directory` absolute.
pub fn resolve_from(directory : String, name : String) -> String {
  let path = @path.Path(name)
  (if path.is_absolute() { path } else { @path.Path(directory).join(path) })
  .normalize()
  .to_string()
}
