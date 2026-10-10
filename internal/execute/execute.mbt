///|
pub async fn execute_case(
  case : @markdown.Case,
  cwd : String,
  module_context~ : ModuleContext?,
  warning~ : async (String) -> Unit,
  target~ : String,
  timeout_ms~ : Int,
) -> @output.Captured {
  @async.with_timeout(
    timeout_ms,
    () => {
      let commands = []
      // Preflight every segment before any tested program can produce effects.
      for segment in case.pipeline {
        let command = prepare_command(
          segment.argv,
          cwd,
          module_context=if case.module_name is Some(_) {
            module_context
          } else {
            None
          },
          warning~,
          target~,
          extra_env=case.extra_env,
        )
        commands.push({
          ..command,
          stderr_to_stdout: segment.stderr_to_stdout,
          stdout_to_null: segment.stdout_to_null,
        })
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
  module_context~ : ModuleContext?,
  warning~ : async (String) -> Unit,
  target~ : String,
  extra_env~ : Map[String, String],
) -> Command {
  let executable = @files.resolve_from(cwd, argv[0])
  let args = argv[1:].to_owned()
  if executable.has_suffix(".mbtx") {
    if @fs.kind(executable) != Regular {
      raise @diagnostic.Failure(
        "command must name a local .mbtx file: " + argv[0],
      )
    }
    // moonx combines build and program statuses. Check compilation first.
    ignore(
      build_artifact(
        ["run", "--build-only", "--target", "wasm", executable],
        cwd,
        extra_env~,
      ),
    )
    {
      program: "moonx",
      args: [executable, "--"] + args,
      stderr_to_stdout: false,
      stdout_to_null: false,
    }
  } else if module_context is Some(context) {
    let package_path = resolve_package(context, argv[0], warning~)
    let artifact = build_artifact(
      [
        "-C",
        context.root,
        "run",
        "--build-only",
        "--target",
        target,
        package_path,
      ],
      cwd,
      extra_env~,
    )
    if target == "wasm" {
      {
        program: "moonrun",
        args: [artifact, "--"] + args,
        stderr_to_stdout: false,
        stdout_to_null: false,
      }
    } else {
      {
        program: artifact,
        args,
        stderr_to_stdout: false,
        stdout_to_null: false,
      }
    }
  } else {
    raise @diagnostic.Failure(
      "command requires a .mbtx file or a module-declared executable package: \{argv[0]}",
    )
  }
}

///|
async fn build_artifact(
  args : Array[String],
  cwd : String,
  extra_env~ : Map[String, String],
) -> String {
  let build = capture_pipeline(
    [{ program: "moon", args, stderr_to_stdout: false, stdout_to_null: false, }],
    cwd,
    extra_env~,
  )
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
