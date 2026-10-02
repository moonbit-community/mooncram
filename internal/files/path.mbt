///|
pub fn resolve_from(directory : String, name : String) -> String {
  let path = @path.Path(name)
  (if path.is_absolute() { path } else { @path.Path(directory).join(path) })
  .normalize()
  .to_string()
}
