///|
/// Build and execute one parsed case using its validated document context.
///
/// `target` must be `"wasm"` or `"native"` and applies to local packages;
/// scripts and imported tools always run as Wasm. `timeout_ms` is the positive
/// deadline for target resolution, all builds, remote fetching and execution.
/// `warning` receives nonfatal target-resolution diagnostics.
///
/// Every local segment finishes its build preflight before tested programs
/// start. Segments run concurrently, inheriting the process environment with
/// document exports and then segment assignments applied. The first segment
/// receives EOF; subsequent segments receive raw bytes through OS pipes.
///
/// Returns final stdout and unmerged stderr (concatenated in segment order),
/// both decoded as UTF-8 with CRLF normalized. The exit code is the rightmost
/// nonzero segment status, or zero. Ordinary nonzero statuses are returned for
/// assertion; imported statuses 255 and -1 raise `@diagnostic.Failure`.
///
/// Resolution, build, startup, UTF-8 capture and timeout errors propagate.
/// Failure cancels and reaps directly managed children. Commands run in the
/// case's working directory and can modify files; no isolation is provided.
/// `case` and `context` must come from the same parsed/validated document.
pub async fn execute_case(
  case : @markdown.Case,
  context : @resolve.DocumentContext,
  warning~ : async (String) -> Unit,
  target~ : String,
  timeout_ms~ : Int32,
) -> @output.Captured {
  let cwd = context.cwd_for(case)
  @async.with_timeout(
    timeout_ms,
    () => {
      let commands = []
      // Preflight every segment before any tested program can produce effects.
      for segment in case.pipeline {
        let extra_env = case.extra_env.copy()
        for name, value in segment.extra_env {
          extra_env[name] = value
        }
        let command = prepare_command(
          segment.argv,
          cwd,
          context.resolve_target(case, segment.argv[0], warning~),
          target~,
          extra_env~,
        )
        commands.push({
          ..command,
          stderr_to_stdout: segment.stderr_to_stdout,
          stdout_to_null: segment.stdout_to_null,
        })
      }
      capture_pipeline(commands, cwd)
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
  resolved : @resolve.ResolvedTarget,
  target~ : String,
  extra_env~ : Map[String, String],
) -> Command {
  let args = argv[1:].to_owned()
  match resolved {
    Imported(binding) =>
      {
        program: "moonx",
        extra_env,
        args: ["--target", "wasm", binding.coordinate, "--"] + args,
        imported: Some(binding),
        stderr_to_stdout: false,
        stdout_to_null: false,
      }
    Script(executable) => {
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
        extra_env,
        imported: None,
        args: [executable, "--"] + args,
        stderr_to_stdout: false,
        stdout_to_null: false,
      }
    }
    Package(module_root, package_path) => {
      let artifact = build_artifact(
        [
          "-C", module_root, "run", "--build-only", "--target", target, package_path,
        ],
        cwd,
        extra_env~,
      )
      if target == "wasm" {
        {
          program: "moonrun",
          extra_env,
          imported: None,
          args: [artifact, "--"] + args,
          stderr_to_stdout: false,
          stdout_to_null: false,
        }
      } else {
        {
          program: artifact,
          extra_env,
          imported: None,
          args,
          stderr_to_stdout: false,
          stdout_to_null: false,
        }
      }
    }
  }
}

///|
async fn build_artifact(
  args : Array[String],
  cwd : String,
  extra_env~ : Map[String, String],
) -> String {
  let build = capture_pipeline(
    [
      {
        program: "moon",
        extra_env,
        args,
        imported: None,
        stderr_to_stdout: false,
        stdout_to_null: false,
      },
    ],
    cwd,
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
