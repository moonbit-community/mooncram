///|
async fn test_toolchain(root : String) -> String {
  let bin = @files.resolve_from(root, "bin")
  for
    directory in [
      bin,
      @files.resolve_from(root, "include"),
      @files.resolve_from(root, "lib/core"),
    ] {
    @fs.mkdir(directory, recursive=true)
  }
  for name in ["moon", "moonc"] {
    @fs.write_text(
      @files.resolve_from(bin, tool_name(name)),
      "",
      permission=0o755,
    )
  }
  bin
}

///|
fn toolchain_with_path(cwd : String, path : String?) -> Toolchain {
  { startup_cwd: cwd, startup_path: path, resolved: None, }
}

///|
async fn capture_toolchain_error(tools : Toolchain) -> @diagnostic.Diagnostic {
  try tools.resolve(Progress::new(tools.startup_cwd)) catch {
    @diagnostic.Failure(diagnostic) => diagnostic
    e => raise e
  } noraise {
    _ => fail("expected toolchain resolution to fail")
  }
}

///|
async fn assert_toolchain_error(tools : Toolchain, expected : String) -> Unit {
  let diagnostic = capture_toolchain_error(tools)
  let report = @diagnostic.render(@diagnostic.Failure(diagnostic))
  assert_true(report.contains(expected), msg=report)
}

///|
async test "toolchain PATH selection is ordered and relative to startup cwd" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-toolchain"))
  defer @fs.rmdir(root, recursive=true)
  let a = test_toolchain(@files.resolve_from(root, "A with spaces"))
  let b = test_toolchain(@files.resolve_from(root, "B"))
  let separator = @path.delimiter.to_string()
  for
    (path, expected) in [
      (a + separator + b, a),
      (b + separator + a, b),
      ("A with spaces/bin" + separator + b, a),
    ] {
    let tools = toolchain_with_path(root, Some(path))
    let paths = tools.resolve(Progress::new(root))
    assert_eq(paths.bin, expected)
  }
  for path in ["", separator + b, "." + separator + b] {
    let tools = toolchain_with_path(a, Some(path))
    assert_eq(tools.resolve(Progress::new(root)).bin, a)
  }
  assert_toolchain_error(toolchain_with_path(a, None), "startup PATH")
}

///|
async test "toolchain skips missing, non-directory and non-executable PATH candidates" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-toolchain"))
  defer @fs.rmdir(root, recursive=true)
  let bin = test_toolchain(@files.resolve_from(root, "valid"))
  @fs.write_text(@files.resolve_from(root, "file"), "")
  @fs.mkdir(
    @files.resolve_from(root, "directory/" + tool_name("moon")),
    recursive=true,
  )
  @fs.mkdir(@files.resolve_from(root, "not-executable"))
  let entries = ["missing", "file", "directory"]
  if @path.sep != '\\' {
    @fs.write_text(
      @files.resolve_from(root, "not-executable/moon"),
      "",
      permission=0o644,
    )
    entries.push("not-executable")
  }
  entries.push(bin)
  let tools = toolchain_with_path(
    root,
    Some(entries.join(@path.delimiter.to_string())),
  )
  assert_eq(tools.resolve(Progress::new(root)).bin, bin)
}

///|
async test "toolchain caches the selected installation across cases" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-toolchain"))
  defer @fs.rmdir(root, recursive=true)
  let a = test_toolchain(@files.resolve_from(root, "A"))
  let b = test_toolchain(@files.resolve_from(root, "B"))
  let path = Some(a + @path.delimiter.to_string() + b)
  let tools = toolchain_with_path(root, path)
  let first = tools.resolve(Progress::new(root))
  @fs.remove(first.moon)
  assert_eq(tools.resolve(Progress::new(b)).moon, first.moon)
  assert_eq(toolchain_with_path(root, path).resolve(Progress::new(root)).bin, b)
}

///|
async test "invalid first installation fails without falling back and caches its error" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-toolchain"))
  defer @fs.rmdir(root, recursive=true)
  // Windows paths already contain backslashes. POSIX permits both backslashes
  // and quotes in a directory name, exposing extra escaping on either platform.
  let name = if @path.sep == '\\' {
    "A with spaces"
  } else {
    "A with spaces \\and \"quotes\""
  }
  let installation = @files.resolve_from(root, name)
  let a = test_toolchain(installation)
  let b = test_toolchain(@files.resolve_from(root, "B"))
  let path = Some(a + @path.delimiter.to_string() + b)
  let moon = @files.resolve_from(a, tool_name("moon"))
  for
    (entry, required, as_file) in [
      ("include", "include", false),
      ("lib/core", "lib/core", false),
      ("include", "include", true),
      ("lib/core", "lib/core", true),
      ("lib", "lib/core", true),
      ("bin/" + tool_name("moonc"), "bin/" + tool_name("moonc"), false),
    ] {
    let invalid = @files.resolve_from(installation, entry)
    let required = @files.resolve_from(installation, required)
    let saved = invalid + ".saved"
    @fs.rename(invalid, saved)
    if as_file {
      @fs.write_text(invalid, "")
    }
    let tools = toolchain_with_path(root, path)
    let diagnostic = capture_toolchain_error(tools)
    let kind = if entry.has_prefix("bin/") { "executable" } else { "directory" }
    let cause = "expected toolchain \{kind} '\{required}'"
    assert_eq(diagnostic.summary, "failed to resolve MoonBit toolchain")
    assert_eq(diagnostic.tool, Some(moon))
    assert_eq(diagnostic.cause, Some(cause))
    let report = @diagnostic.render(@diagnostic.Failure(diagnostic))
    assert_true(report.contains("tool: " + moon), msg=report)
    assert_true(report.contains("cause: " + cause), msg=report)
    assert_eq(
      @diagnostic.render(@diagnostic.Failure(capture_toolchain_error(tools))),
      report,
    )
    if as_file {
      @fs.remove(invalid)
    }
    @fs.rename(saved, invalid)
    assert_eq(
      @diagnostic.render(@diagnostic.Failure(capture_toolchain_error(tools))),
      report,
    )
    assert_eq(
      toolchain_with_path(root, path).resolve(Progress::new(root)).bin,
      a,
    )
  }
  let moon = @files.resolve_from(root, tool_name("moon"))
  @fs.write_text(moon, "", permission=0o755)
  assert_toolchain_error(
    toolchain_with_path(root, Some(root + @path.delimiter.to_string() + b)),
    "bin directory",
  )
}

///|
async test "moon symlinks select their real installation and preserve companion entry names" {
  // True file symlinks require extra privileges on Windows; integration also
  // exercises them on Windows when the host permits creation.
  if @path.sep == '\\' {
    return
  }
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-toolchain"))
  defer @fs.rmdir(root, recursive=true)
  let bin = test_toolchain(@files.resolve_from(root, "A"))
  let links = @files.resolve_from(root, "links")
  @fs.mkdir(links)
  let moon = @files.resolve_from(bin, tool_name("moon"))
  @fs.symlink(target=moon, @files.resolve_from(links, tool_name("moon")))
  let moonx = @files.resolve_from(bin, tool_name("moonx"))
  @fs.symlink(target=moon, moonx)
  let tools = toolchain_with_path(root, Some(links))
  let paths = tools.resolve(Progress::new(root))
  assert_eq(paths.moon, moon)
  assert_eq(paths.tool("moonx"), moonx)
  assert_eq(
    paths.tool("moonrun"),
    @files.resolve_from(bin, tool_name("moonrun")),
  )
}
