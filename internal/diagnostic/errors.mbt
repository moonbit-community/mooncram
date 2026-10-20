///|
/// A diagnostic keeps its location and execution context separate from text.
pub struct Diagnostic {
  summary : String
  file : String?
  line : Int32?
  command : String?
  phase : String?
  segment : String?
  tool : String?
  cwd : String?
  cause : String?
  hint : String?
  logs : Array[Log]
}

///|
/// Raw captured output. An incomplete stream has not reached EOF.
pub(all) struct Log {
  label : String
  bytes : Bytes
  complete : Bool
}

///|
/// A user-facing error, rendered only at the reporting boundary.
pub(all) suberror Failure {
  Failure(Diagnostic)
}

///|
/// Construct an error without source or execution context.
pub fn failure(summary : String) -> Failure {
  Failure({
    summary,
    file: None,
    line: None,
    command: None,
    phase: None,
    segment: None,
    tool: None,
    cwd: None,
    cause: None,
    hint: None,
    logs: [],
  })
}

///|
fn diagnostic(error : Error) -> Diagnostic {
  match error {
    Failure(value) => value
    _ => {
      let Failure(value) = failure(error.to_string())
      value
    }
  }
}

///|
fn[T] prefer(existing : T?, fallback : T?) -> T? {
  if existing is Some(_) {
    existing
  } else {
    fallback
  }
}

///|
/// Fill absent context without replacing a more precise inner location.
pub fn context(
  error : Error,
  file? : String,
  line? : Int32,
  command? : String,
  phase? : String,
  segment? : String,
  tool? : String,
  cwd? : String,
  hint? : String,
) -> Failure {
  let d = diagnostic(error)
  Failure({
    ..d,
    file: prefer(d.file, file),
    line: if d.file is Some(_) && d.file != file {
      d.line
    } else {
      prefer(d.line, line)
    },
    command: prefer(d.command, command),
    phase: prefer(d.phase, phase),
    segment: prefer(d.segment, segment),
    tool: prefer(d.tool, tool),
    cwd: prefer(d.cwd, cwd),
    hint: prefer(d.hint, hint),
  })
}

///|
/// Explain an operation while preserving its underlying reason and context.
pub fn wrap(error : Error, summary : String) -> Failure {
  let d = diagnostic(error)
  let cause = if d.cause is Some(cause) {
    d.summary + "\n" + cause
  } else {
    d.summary
  }
  Failure({ ..d, summary, cause: Some(cause), })
}

///|
/// Attach a single snapshot of captured output after child cleanup finishes.
pub fn with_logs(error : Error, logs : Array[Log]) -> Failure {
  Failure({ ..diagnostic(error), logs, })
}

///|
/// Construct a located error without embedding a location in the summary.
pub fn located(file : String, line : Int32, message : String) -> Failure {
  context(failure(message), file~, line~)
}
