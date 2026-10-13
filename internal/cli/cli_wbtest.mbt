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
test "check supports color and paths but rejects explicit execution options" {
  let cli = parse_cli(["check"])
  assert_true(cli.command is Check)
  assert_eq(cli.paths, ["."])
  for
    args in [
      ["--color", "always", "check", "one.md", "two.md"],
      ["check", "one.md", "--color", "always", "two.md"],
    ] {
    let cli = parse_cli(args)
    assert_true(cli.command is Check)
    assert_eq(cli.paths, ["one.md", "two.md"])
    assert_eq(cli.color, "always")
  }
  for (option, value) in [("target", "wasm"), ("timeout-ms", "60000")] {
    for
      args in [
        ["--" + option, value, "check"],
        ["check", "one.md", "--" + option + "=" + value],
      ] {
      assert_error_contains(
        () => ignore(parse_cli(args)),
        "only supported by test/update",
      )
    }
  }
  for args in [["check", "--dry-run"], ["--dry-run", "check"]] {
    assert_error_contains(() => ignore(parse_cli(args)), "dry-run")
  }
}

///|
test "CLI defaults and options before or after paths" {
  let cli = parse_cli(["test"])
  assert_eq(cli.paths, ["."])
  assert_eq(cli.target, "wasm")
  assert_eq(cli.timeout_ms, 60000)
  let cli = parse_cli([
    "--target", "native", "update", "one.md", "--dry-run", "two", "--timeout-ms",
    "42", "--color", "never",
  ])
  assert_true(cli.command is Update(dry_run=true))
  assert_eq(cli.paths, ["one.md", "two"])
  assert_eq(cli.target, "native")
  assert_eq(cli.timeout_ms, 42)
  assert_eq(cli.color, "never")
  for
    args in [
      ["test", "--target", "js"],
      ["test", "--timeout-ms", "0"],
      ["test", "--timeout-ms", "1.5"],
      ["test", "--color", "yes"],
      ["test", "--dry-run"],
      ["test", "--unknown"],
      ["update", "--target"],
      ["bogus"],
      [],
    ] {
    assert_error_contains(() => ignore(parse_cli(args)), "")
  }
}
