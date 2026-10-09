///|
pub async fn execute_case(
  case : @markdown.Case,
  cwd : String,
  target~ : String,
  timeout_ms~ : Int,
) -> @output.Captured {
  @async.with_timeout(
    timeout_ms,
    () => {
      let commands = []
      // Preflight every segment before any tested program can produce effects.
      for argv in case.pipeline {
        commands.push(
          prepare_command(argv, cwd, target~, extra_env=case.extra_env),
        )
      }
      capture_pipeline(commands, cwd, extra_env=case.extra_env)
    },
    error=@diagnostic.Failure(
      "timed out after \{timeout_ms} ms (including build)",
    ),
  )
}

///|
async fn prepare_command(
  argv : Array[String],
  cwd : String,
  target~ : String,
  extra_env~ : Map[String, String],
) -> Command {
  let executable = @files.resolve_from(cwd, argv[0])
  let args = argv[1:].to_owned()
  let kind = @fs.kind(executable)
  if kind == Regular && executable.has_suffix(".mbtx") {
    // moonx combines build and program statuses. Check compilation first.
    ignore(
      build_artifact(
        ["run", "--build-only", "--target", "wasm", executable],
        cwd,
        extra_env~,
      ),
    )
    { program: "moonx", args: [executable, "--"] + args, }
  } else if kind == Directory {
    if !@fs.exists(@files.resolve_from(executable, "moon.pkg")) &&
      !@fs.exists(@files.resolve_from(executable, "moon.pkg.json")) {
      raise @diagnostic.Failure(
        "directory is not a local MoonBit package: \{executable}",
      )
    }
    let artifact = build_artifact(
      ["-C", executable, "run", "--build-only", "--target", target, executable],
      cwd,
      extra_env~,
    )
    if target == "wasm" {
      { program: "moonrun", args: [artifact, "--"] + args, }
    } else {
      { program: artifact, args, }
    }
  } else {
    raise @diagnostic.Failure(
      "command must name a local .mbtx file or executable MoonBit package: \{argv[0]}",
    )
  }
}

///|
async fn build_artifact(
  args : Array[String],
  cwd : String,
  extra_env~ : Map[String, String],
) -> String {
  let build = capture_pipeline([{ program: "moon", args, }], cwd, extra_env~)
  if build.exit_code != 0 {
    raise @diagnostic.Failure(
      "build failed (exit \{build.exit_code})\n\{build.output}\{build.diagnostic}",
    )
  }
  let artifact = parse_artifact(build.output) catch {
    e =>
      raise @diagnostic.Failure(
        "\{@diagnostic.error_text(e)}\n\{build.output}\{build.diagnostic}",
      )
  }
  @files.resolve_from(cwd, artifact)
}

///|
fn parse_artifact(output : String) -> String raise {
  let value = @json.parse(output) catch {
    _ => raise @diagnostic.Failure("moon returned invalid build artifact JSON")
  }
  match value {
    { "artifacts_path": [String(path)], .. } => path
    _ =>
      raise @diagnostic.Failure(
        "moon must return exactly one artifacts_path entry",
      )
  }
}
