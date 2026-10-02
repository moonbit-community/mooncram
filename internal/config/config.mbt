///|
pub fn positive_int(text : String) -> Int raise {
  if text.is_empty() || !text.iter().all(c => c >= '0' && c <= '9') {
    raise @diagnostic.Failure("expected a positive integer, got '\{text}'")
  }
  let value = @string.parse_int(text) catch {
    _ => raise @diagnostic.Failure("integer out of range: '\{text}'")
  }
  if value <= 0 {
    raise @diagnostic.Failure("expected a positive integer, got '\{text}'")
  }
  value
}

///|
pub fn validate_target(target : String) -> Unit raise {
  if target != "wasm" && target != "native" {
    raise @diagnostic.Failure("target must be wasm or native")
  }
}

///|
pub fn parse_config(text : String, defaults : Config) -> Config raise {
  if text.trim().is_empty() {
    return defaults
  }
  let json = @json.parse(text) catch {
    e =>
      raise @diagnostic.Failure(
        "invalid block configuration JSON: \{@diagnostic.error_text(e)}",
      )
  }
  guard json is Object(fields) else {
    raise @diagnostic.Failure("block configuration must be a JSON object")
  }
  let mut stream = defaults.stream
  let mut stdin = defaults.stdin
  let mut env = defaults.env
  let mut target = defaults.target
  let mut timeout_ms = defaults.timeout_ms
  for key, value in fields {
    match (key, value) {
      ("stream", String("stdout")) => stream = Stdout
      ("stream", String("stderr")) => stream = Stderr
      ("stream", String("merged")) => stream = Merged
      ("stdin", String(path)) => {
        if path == "" || path.contains("\u0000") {
          raise @diagnostic.Failure(
            "stdin must be a nonempty file path without NUL",
          )
        }
        stdin = Some(path)
      }
      ("target", String(t)) => {
        validate_target(t)
        target = t
      }
      ("timeout_ms", Number(n, ..)) => {
        if n <= 0 || n > 2147483647 || n != n.to_int().to_double() {
          raise @diagnostic.Failure(
            "timeout_ms must be a positive 32-bit integer",
          )
        }
        timeout_ms = n.to_int()
      }
      ("env", Object(values)) => {
        let parsed : Map[String, String] = Map([])
        for name, value in values {
          guard value is String(s) else {
            raise @diagnostic.Failure("env values must be strings")
          }
          if name == "" ||
            name.contains("=") ||
            name.contains("\u0000") ||
            s.contains("\u0000") {
            raise @diagnostic.Failure(
              "invalid environment variable name or value",
            )
          }
          parsed[name] = s
        }
        env = parsed
      }
      ("stream" | "stdin" | "target" | "timeout_ms" | "env", _) =>
        raise @diagnostic.Failure(
          "invalid value for block configuration '\{key}'",
        )
      _ => raise @diagnostic.Failure("unknown block configuration '\{key}'")
    }
  }
  { stream, stdin, env, target, timeout_ms, }
}
