///|
priv struct Cli {
  update : Bool
  dry_run : Bool
  paths : Array[String]
  config : @config.Config
  color : String
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
    version="0.0.1",
    subcommand_required=true,
    options=[
      @argparse.OptionArg(
        "target",
        long="target",
        global=true,
        default_values=["wasm"],
        about="Package target: wasm or native",
      ),
      @argparse.OptionArg(
        "timeout-ms",
        long="timeout-ms",
        global=true,
        default_values=["60000"],
        about="Per-case time limit, including build",
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
      @argparse.Command("test", about="Check command output and exit status", positionals=[
        paths,
      ]),
      @argparse.Command(
        "update",
        about="Update failing expectations in place",
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
    raise @diagnostic.Failure("expected test or update")
  }
  let target = sub.values["target"][0]
  @config.validate_target(target)
  let timeout_ms = @config.positive_int(sub.values["timeout-ms"][0])
  let color = sub.values["color"][0]
  if color != "auto" && color != "always" && color != "never" {
    raise @diagnostic.Failure("color must be auto, always, or never")
  }
  let paths = sub.values.get("paths").unwrap_or([])
  {
    update: name == "update",
    dry_run: sub.flags.get("dry-run").unwrap_or(false),
    paths: if paths.is_empty() {
      ["."]
    } else {
      paths
    },
    config: { ..@config.default_config(), target, timeout_ms, },
    color,
  }
}
