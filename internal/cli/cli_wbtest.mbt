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
test "CLI defaults and options before or after paths" {
  let cli = parse_cli(["test"])
  assert_eq(cli.paths, ["."])
  assert_eq(cli.config.target, "wasm")
  assert_eq(cli.config.timeout_ms, 60000)
  let cli = parse_cli([
    "--target", "native", "update", "one.md", "--dry-run", "two", "--timeout-ms",
    "42", "--color", "never",
  ])
  assert_true(cli.update && cli.dry_run)
  assert_eq(cli.paths, ["one.md", "two"])
  assert_eq(cli.config.target, "native")
  assert_eq(cli.config.timeout_ms, 42)
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
