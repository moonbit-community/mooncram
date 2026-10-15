///|
fn semver_number(value : String) -> Bool {
  !value.is_empty() &&
  (value.length() == 1 || value[0] != '0') &&
  value.iter().all(c => c is ('0'..<='9'))
}

///|
fn semver_identifiers(value : String, prerelease~ : Bool) -> Bool {
  value
  .split(".")
  .all(part => {
    !part.is_empty() &&
    part.iter().all(c => c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-')) &&
    (
      !prerelease ||
      !part.iter().all(c => c is ('0'..<='9')) ||
      semver_number(part.to_owned())
    )
  })
}

///|
fn valid_semver(version : String) -> Bool {
  let build = version.split("+").to_array()
  if build.length() > 2 {
    return false
  }
  if build.length() == 2 &&
    !semver_identifiers(build[1].to_owned(), prerelease=false) {
    return false
  }
  let release = build[0].to_owned()
  let core = if release.find("-") is Some(index) {
    if !semver_identifiers(release[index + 1:].to_owned(), prerelease=true) {
      return false
    }
    release[:index].to_owned()
  } else {
    release
  }
  let numbers = core.split(".").to_array()
  numbers.length() == 3 && numbers.all(n => semver_number(n.to_owned()))
}

///|
fn valid_coordinate(coordinate : String) -> Bool {
  match coordinate.split("@").to_array() {
    [path, version] =>
      path.split("/").count() >= 2 &&
      valid_package_name(path.to_owned()) &&
      valid_semver(version.to_owned())
    _ => false
  }
}
