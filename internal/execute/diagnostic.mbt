///|
/// Updated only by normal execution, never by cancellation cleanup.
priv struct Progress {
  mut phase : String
  mut segment : String?
  mut tool : String?
  cwd : String
  mut pending : Array[String?]
  mut logs : Array[StreamCapture]
  mut primary : @diagnostic.Failure?
}

///|
fn Progress::new(cwd : String) -> Progress {
  {
    phase: "resolve",
    segment: None,
    tool: None,
    cwd,
    pending: [],
    logs: [],
    primary: None,
  }
}

///|
fn Progress::remember(self : Progress, error : Error) -> @diagnostic.Failure {
  if self.primary is Some(primary) {
    return primary
  }
  let pending = []
  for segment in self.pending {
    if segment is Some(segment) {
      pending.push(segment)
    }
  }
  if pending.is_empty() {
    for log in self.logs {
      if !log.complete && !pending.contains(log.segment) {
        pending.push(log.segment)
      }
    }
  }
  let segment = if self.segment is Some(segment) {
    Some(segment)
  } else if pending.is_empty() {
    None
  } else {
    Some(pending.join(", "))
  }
  let error = match error {
    @diagnostic.Failure(_) => error
    _ => @diagnostic.wrap(error, "failed during \{self.phase}")
  }
  let primary = @diagnostic.context(
    error,
    phase=self.phase,
    segment?,
    tool?=self.tool,
    cwd=self.cwd,
  )
  self.primary = Some(primary)
  primary
}

///|
fn Progress::report(self : Progress, error : Error) -> @diagnostic.Failure {
  @diagnostic.with_logs(
    self.remember(error),
    self.logs.map(log => {
      label: "\{log.phase} \{log.stream} (segment \{log.segment})",
      bytes: log.bytes.to_bytes(),
      complete: log.complete,
    }),
  )
}

///|
priv struct StreamCapture {
  bytes : @buffer.Buffer
  phase : String
  stream : String
  segment : String
  tool : String
  mut complete : Bool
}

///|
fn StreamCapture::new(
  phase : String,
  stream : String,
  segment : String,
  tool : String,
) -> StreamCapture {
  { bytes: @buffer.Buffer(), phase, stream, segment, tool, complete: false, }
}

///|
/// Copy each returned chunk before the next suspension, so cancellation cannot
/// discard output already read. Decode only at EOF, including split UTF-8.
async fn capture_stream(
  reader : @process.ReadFromProcess,
  log : StreamCapture,
  progress : Progress,
) -> String {
  try {
    while reader.read() is Some(bytes) {
      log.bytes.write_bytes(bytes)
    }
    log.complete = true
    @utf8.decode(log.bytes.to_bytes()) catch {
      @utf8.Malformed(_) =>
        raise @diagnostic.context(
          @diagnostic.failure("invalid UTF-8 in captured \{log.stream}"),
          phase=if log.phase == "build" { "build" } else { "capture" },
          segment=log.segment,
          tool=log.tool,
        )
    }
  } catch {
    @diagnostic.Failure(_) | @os_error.OsError(_, ..) | @io.ReaderClosed as e => {
      let error = match e {
        @diagnostic.Failure(_) => e
        _ => @diagnostic.wrap(e, "failed to read captured \{log.stream}")
      }
      raise progress.remember(
        @diagnostic.context(
          error,
          phase=if log.phase == "build" { "build" } else { "capture" },
          segment=log.segment,
          tool=log.tool,
        ),
      )
    }
    e => raise e
  }
}

///|
fn segment_label(index : Int32, count : Int32, label : String) -> String {
  "\{index + 1}/\{count} (\{label})"
}
