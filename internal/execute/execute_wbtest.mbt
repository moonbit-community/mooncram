///|
fn assert_error_contains(f : () -> Unit raise, expected : String) -> Unit raise {
  try f() catch {
    e =>
      assert_true(
        @diagnostic.error_text(e).contains(expected),
        msg=@diagnostic.error_text(e),
      )
  } noraise {
    _ => fail("expected error containing: " + expected)
  }
}

///|
test "artifact JSON is validated" {
  assert_eq(
    parse_artifact("{\"artifacts_path\":[\"/tmp/a.wasm\"]}\n"),
    "/tmp/a.wasm",
  )
  for
    text in [
      "not JSON", "{}", "{\"artifacts_path\":[]}", "{\"artifacts_path\":[\"a\",\"b\"]}",
    ] {
    assert_error_contains(() => ignore(parse_artifact(text)), "artifact")
  }
}

///|
test "reserved statuses apply only to remote tools and report coordinate and segment" {
  let coordinate = "user/module@1.2.3"
  for status in [255, -1] {
    for
      expected in [
        "remote 'user/module@1.2.3'",
        "pipeline segment 2",
        "status \{status}",
      ] {
      assert_error_contains(
        () => check_remote_status(Some(coordinate), 2, status),
        expected,
      )
    }
    check_remote_status(None, 2, status)
  }
  for status in [0, 1, 2, 254, -2, -9] {
    check_remote_status(Some(coordinate), 1, status)
  }
}

///|
test "cleanup errors cannot replace the original failure context" {
  let progress = Progress::new("/repo")
  progress.phase = "build"
  progress.segment = Some("2/3 (tool)")
  progress.tool = Some("moon")
  ignore(progress.remember(@diagnostic.failure("compiler failed")))
  progress.phase = "capture"
  progress.segment = None
  let log = StreamCapture::new("build", "stderr", "2/3 (tool)", "moon")
  log.bytes.write_bytes(b"compiler detail\n")
  progress.logs.push(log)
  let report = @diagnostic.render(
    progress.report(@diagnostic.failure("reader closed")),
  )
  assert_true(
    report.contains(
      "compiler failed\n  phase: build\n  segment: 2/3 (tool)\n  tool: moon",
    ),
    msg=report,
  )
  assert_true(!report.contains("reader closed"), msg=report)
  assert_true(report.contains("; partial\ncompiler detail\n"), msg=report)
}

///|
async test "capture IO errors identify the operation and stream endpoint" {
  let (reader, writer) = @process.read_from_process()
  reader.close()
  writer.close()
  let progress = Progress::new("/repo")
  let log = StreamCapture::new("run", "stdout", "2/3 (tool)", "moonx")
  try capture_stream(reader, log, progress) catch {
    e => {
      let report = @diagnostic.render(progress.report(e))
      assert_true(
        report.has_prefix("ERROR failed to read captured stdout\n"),
        msg=report,
      )
      assert_true(
        report.contains("phase: capture\n  segment: 2/3 (tool)\n  tool: moonx"),
        msg=report,
      )
      assert_true(report.contains("cause:"), msg=report)
    }
  } noraise {
    _ => fail("reading a closed stream should fail")
  }
}
