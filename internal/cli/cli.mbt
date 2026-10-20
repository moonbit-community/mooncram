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
priv enum CliCommand {
  Run(Cli)
  DocsList
  DocsShow(String)
}

///|
fn positive_int(text : String) -> Int32 raise {
  if text.is_empty() || !text.iter().all(c => c >= '0' && c <= '9') {
    raise @diagnostic.failure(
      "--timeout-ms must be an integer in 1..2147483647; got '\{text}'",
    )
  }
  let value = @string.parse_int(text) catch {
    _ =>
      raise @diagnostic.failure(
        "--timeout-ms must be an integer in 1..2147483647; got '\{text}' (out of range)",
      )
  }
  if value <= 0 {
    raise @diagnostic.failure(
      "--timeout-ms must be an integer in 1..2147483647; got '\{text}'",
    )
  }
  value
}

///|
fn validate_target(target : String) -> Unit raise {
  if target != "wasm" && target != "native" {
    raise @diagnostic.failure(
      "--target must be wasm or native; got '\{target}'",
    )
  }
}

///|
fn case_options(execution~ : Bool = true) -> Array[@argparse.OptionArg] {
  let options = []
  if execution {
    options.push(
      @argparse.OptionArg(
        "target",
        long="target",
        default_values=["wasm"],
        about="Package target: wasm or native",
      ),
    )
    options.push(
      @argparse.OptionArg(
        "timeout-ms",
        long="timeout-ms",
        default_values=["60000"],
        about="Per-case time limit, including build",
      ),
    )
  }
  options.push(
    @argparse.OptionArg(
      "color",
      long="color",
      default_values=["auto"],
      about="Report color: auto, always, never",
    ),
  )
  options
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
    version=MODULE_VERSION,
    subcommand_required=true,
    subcommands=[
      @argparse.Command(
        "docs",
        about="Print embedded mooncram documentation",
        arg_required_else_help=true,
        flags=[
          @argparse.FlagArg(
            "list",
            long="list",
            about="List available document names and summaries",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "doc-name",
            about="Document name from docs --list (case-sensitive)",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      ),
      @argparse.Command(
        "check",
        about="Validate examples and local targets without execution",
        options=case_options(execution=false),
        positionals=[paths],
      ),
      @argparse.Command(
        "test",
        about="Check command output and exit status",
        options=case_options(),
        positionals=[paths],
      ),
      @argparse.Command(
        "update",
        about="Update and normalize expectations, including passing cases",
        options=case_options(),
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
fn parse_cli(args : Array[String]) -> CliCommand raise {
  // argparse exposes display-ready messages through a private error type.
  // Normalize them here so the async reporting boundary can match Failure.
  let matches = cli_command().parse(argv=args) catch {
    e => raise @diagnostic.failure(e.to_string())
  }
  let (name, sub) = matches.subcommand.unwrap()
  if name == "docs" {
    return parse_docs_cli(sub)
  }
  let target = if name == "check" { "wasm" } else { sub.values["target"][0] }
  validate_target(target)
  let timeout_ms = if name == "check" {
    60000
  } else {
    positive_int(sub.values["timeout-ms"][0])
  }
  let color = sub.values["color"][0]
  if color != "auto" && color != "always" && color != "never" {
    raise @diagnostic.failure(
      "--color must be auto, always, or never; got '\{color}'",
    )
  }
  let paths = sub.values.get("paths").unwrap_or([])
  Run({
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
  })
}
