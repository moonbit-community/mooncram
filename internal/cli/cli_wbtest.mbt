///|
fn assert_error_contains(f : () -> Unit raise, expected : String) -> Unit raise {
  try f() catch {
    @diagnostic.Failure(_) as e =>
      assert_true(
        @diagnostic.error_text(e).contains(expected),
        msg=@diagnostic.error_text(e),
      )
    e => raise e
  } noraise {
    _ => fail("expected error containing: " + expected)
  }
}

///|
fn parse_run_cli(args : Array[String]) -> Cli raise {
  match parse_cli(args) {
    Run(cli) => cli
    _ => fail("expected a case command")
  }
}

///|
test "check supports color and paths but rejects explicit execution options" {
  let cli = parse_run_cli(["check"])
  assert_true(cli.command is Check)
  assert_eq(cli.paths, ["."])
  for
    args in [
      ["check", "--color", "always", "one.md", "two.md"],
      ["check", "one.md", "--color", "always", "two.md"],
    ] {
    let cli = parse_run_cli(args)
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
      assert_error_contains(() => ignore(parse_cli(args)), "--" + option)
    }
  }
  for args in [["check", "--dry-run"], ["--dry-run", "check"]] {
    assert_error_contains(() => ignore(parse_cli(args)), "dry-run")
  }
}

///|
test "CLI defaults and options before or after paths" {
  let cli = parse_run_cli(["test"])
  assert_eq(cli.paths, ["."])
  assert_eq(cli.target, "wasm")
  assert_eq(cli.timeout_ms, 60000)
  let cli = parse_run_cli([
    "update", "--target", "native", "one.md", "--dry-run", "two", "--timeout-ms",
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

///|
test "case options retain values before and after paths" {
  for
    (option, value) in [
      ("target", "native"),
      ("timeout-ms", "42"),
      ("color", "always"),
    ] {
    for command in ["test", "update"] {
      for
        args in [
          [command, "--" + option, value, "one.md"],
          [command, "one.md", "--" + option + "=" + value],
        ] {
        let cli = parse_run_cli(args)
        assert_eq(cli.paths, ["one.md"])
        match option {
          "target" => assert_eq(cli.target, value)
          "timeout-ms" => assert_eq(cli.timeout_ms, 42)
          _ => assert_eq(cli.color, value)
        }
      }
    }
  }
}

///|
test "case options reject repetitions" {
  for
    (command, options) in [
      ("check", [("color", "auto")]),
      ("test", [("target", "wasm"), ("timeout-ms", "60000"), ("color", "auto")]),
      (
        "update",
        [("target", "wasm"), ("timeout-ms", "60000"), ("color", "auto")],
      ),
    ] {
    for (option, value) in options {
      assert_error_contains(
        () => {
          ignore(
            parse_cli([command, "--" + option, value, "--" + option, value]),
          )
        },
        "cannot be used multiple times",
      )
    }
  }
}

///|
test "case options cannot precede a subcommand" {
  for command in ["check", "test", "update", "docs", "help"] {
    for
      (option, value) in [
        ("target", "wasm"),
        ("timeout-ms", "60000"),
        ("color", "auto"),
      ] {
      assert_error_contains(
        () => ignore(parse_cli(["--" + option, value, command])),
        "--" + option,
      )
    }
  }
}
