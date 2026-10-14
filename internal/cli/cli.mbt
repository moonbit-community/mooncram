///|
priv enum Subcommand {
  Test
  Update(dry_run~ : Bool)
  Check
}

///|
priv struct Cli {
  command : Subcommand
  paths : Array[String]
  target : String
  timeout_ms : Int32
  color : String
}

///|
fn positive_int(text : String) -> Int32 raise {
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
fn validate_target(target : String) -> Unit raise {
  if target != "wasm" && target != "native" {
    raise @diagnostic.Failure("target must be wasm or native")
  }
}

///|
fn cli_command() -> @argparse.Command {
  let paths = @argparse.PositionArg(
    "paths",
    about="Markdown files or directories (default: .)",
    num_args=@argparse.ValueRange(lower=0),
  )
  @argparse.Command(
    "mooncram",
    about="Run MoonBit command examples in Markdown mooncram fences.",
    version="0.0.4",
    subcommand_required=true,
    options=[
      @argparse.OptionArg(
        "target",
        long="target",
        global=true,
        default_values=["wasm"],
        about="Package target for test/update: wasm or native",
      ),
      @argparse.OptionArg(
        "timeout-ms",
        long="timeout-ms",
        global=true,
        default_values=["60000"],
        about="Per-case time limit for test/update, including build",
      ),
      @argparse.OptionArg(
        "color",
        long="color",
        global=true,
        default_values=["auto"],
        about="Color: auto, always, never",
      ),
    ],
    subcommands=[
      @argparse.Command(
        "check",
        about="Validate examples and local targets without execution",
        positionals=[paths],
      ),
      @argparse.Command("test", about="Check command output and exit status", positionals=[
        paths,
      ]),
      @argparse.Command(
        "update",
        about="Update and normalize expectations, including passing cases",
        positionals=[paths],
        flags=[
          @argparse.FlagArg(
            "dry-run",
            long="dry-run",
            about="Show document diffs without writing",
          ),
        ],
      ),
    ],
  )
}

///|
fn parse_cli(args : Array[String]) -> Cli raise {
  let matches = cli_command().parse(argv=args)
  guard matches.subcommand is Some((name, sub)) else {
    raise @diagnostic.Failure("expected test, update, or check")
  }
  if name == "check" {
    for option in ["target", "timeout-ms"] {
      if sub.sources.get(option) is Some(@argparse.Argv) {
        raise @diagnostic.Failure(
          "--" + option + " is only supported by test/update",
        )
      }
    }
  }
  let target = sub.values["target"][0]
  validate_target(target)
  let timeout_ms = positive_int(sub.values["timeout-ms"][0])
  let color = sub.values["color"][0]
  if color != "auto" && color != "always" && color != "never" {
    raise @diagnostic.Failure("color must be auto, always, or never")
  }
  let paths = sub.values.get("paths").unwrap_or([])
  {
    command: match name {
      "check" => Check
      "update" => Update(dry_run=sub.flags.get("dry-run").unwrap_or(false))
      _ => Test
    },
    paths: if paths.is_empty() {
      ["."]
    } else {
      paths
    },
    target,
    timeout_ms,
    color,
  }
}
