///|
fn positive_int(text : String) -> Int raise {
  if text.is_empty() || !text.iter().all(c => c >= '0' && c <= '9') {
    raise Failure("expected a positive integer, got '\{text}'")
  }
  let value = @string.parse_int(text) catch {
    _ => raise Failure("integer out of range: '\{text}'")
  }
  if value <= 0 {
    raise Failure("expected a positive integer, got '\{text}'")
  }
  value
}

///|
fn validate_target(target : String) -> Unit raise {
  if target != "wasm" && target != "native" {
    raise Failure("target must be wasm or native")
  }
}

///|
fn parse_config(text : String, defaults : Config) -> Config raise {
  if text.trim().is_empty() {
    return defaults
  }
  let json = @json.parse(text) catch {
    e => raise Failure("invalid block configuration JSON: \{error_text(e)}")
  }
  guard json is Object(fields) else {
    raise Failure("block configuration must be a JSON object")
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
          raise Failure("stdin must be a nonempty file path without NUL")
        }
        stdin = Some(path)
      }
      ("target", String(t)) => {
        validate_target(t)
        target = t
      }
      ("timeout_ms", Number(n, ..)) => {
        if n <= 0 || n > 2147483647 || n != n.to_int().to_double() {
          raise Failure("timeout_ms must be a positive 32-bit integer")
        }
        timeout_ms = n.to_int()
      }
      ("env", Object(values)) => {
        let parsed : Map[String, String] = Map([])
        for name, value in values {
          guard value is String(s) else {
            raise Failure("env values must be strings")
          }
          if name == "" ||
            name.contains("=") ||
            name.contains("\u0000") ||
            s.contains("\u0000") {
            raise Failure("invalid environment variable name or value")
          }
          parsed[name] = s
        }
        env = parsed
      }
      ("stream" | "stdin" | "target" | "timeout_ms" | "env", _) =>
        raise Failure("invalid value for block configuration '\{key}'")
      _ => raise Failure("unknown block configuration '\{key}'")
    }
  }
  { stream, stdin, env, target, timeout_ms, }
}
