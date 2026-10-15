///|
test "locations and inner execution context survive outer enrichment" {
  let error = @diagnostic.context(
    @diagnostic.located("inner.md", 7, "invalid command"),
    phase="resolve",
    segment="2/3 (tool)",
  )
  let error = @diagnostic.context(
    error,
    file="outer.md",
    line=20,
    command="$ moonx tool",
    phase="run",
    segment="1/1 (other)",
    cwd="/repo",
  )
  assert_eq(
    @diagnostic.render(error),
    "ERROR inner.md:7: invalid command\n  $ moonx tool\n  phase: resolve\n  segment: 2/3 (tool)\n  cwd: /repo\n",
  )
  assert_eq(
    @diagnostic.error_text(@diagnostic.located("test.md", 3, "bad")),
    "test.md:3: bad",
  )
  assert_eq(
    @diagnostic.render(
      @diagnostic.context(
        @diagnostic.context(@diagnostic.failure("bad"), file="config"),
        file="readme",
        line=9,
      ),
    ),
    "ERROR config: bad\n",
  )
}

///|
test "operation causes and hints render in stable order" {
  let error = @diagnostic.context(
    @diagnostic.wrap(
      @diagnostic.failure("permission denied\nextra detail"),
      "failed to start 'moonx'",
    ),
    file="test.md",
    line=2,
    command="$ moonx user/tool@1.2.3",
    phase="start",
    segment="1/1 (user/tool@1.2.3)",
    tool="moonx",
    cwd="/repo",
    hint="check PATH",
  )
  assert_eq(
    @diagnostic.render(error),
    "ERROR test.md:2: failed to start 'moonx'\n  $ moonx user/tool@1.2.3\n  phase: start\n  segment: 1/1 (user/tool@1.2.3)\n  tool: moonx\n  cwd: /repo\n  cause: permission denied\n    extra detail\n  hint: check PATH\n",
  )
}

///|
test "logs retain all captured bytes and label incomplete or invalid streams" {
  let text = "a".repeat(70000) + "\n\n"
  let report = @diagnostic.render(
    @diagnostic.with_logs(@diagnostic.failure("failed"), [
      { label: "run stdout", bytes: b"", complete: false, },
      { label: "run stderr", bytes: @utf8.encode(text), complete: true, },
      { label: "run stdout", bytes: b"tail\r\nmore\r\n", complete: false, },
      { label: "run stderr", bytes: b"\xff", complete: true, },
    ]),
  )
  assert_true(report.contains(text))
  assert_true(report.contains("--- captured run stdout; partial\ntail\nmore\n"))
  assert_true(
    report.contains("--- captured run stderr; escaped bytes\nb\"\\xff\""),
    msg=report,
  )
  assert_eq(report.split("--- captured").count(), 4)
  assert_true(report.has_suffix("\n"))
}
