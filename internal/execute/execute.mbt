///|
/// Build and execute one parsed case using its validated document context.
///
/// `target` must be `"wasm"` or `"native"` and applies to local packages;
/// scripts and remote tools always run as Wasm. `timeout_ms` is the positive
/// deadline for target resolution, all builds, remote fetching and execution.
///
/// Every local segment finishes its build preflight before tested programs
/// start. Segments run concurrently, inheriting the process environment with
/// segment assignments applied. The first segment receives EOF; subsequent
/// segments receive raw bytes through OS pipes.
///
/// Returns final stdout and per-segment stderr (concatenated in segment order),
/// both decoded as UTF-8 with CRLF normalized. The exit code is the rightmost
/// nonzero segment status, or zero. Ordinary nonzero statuses are returned for
/// assertion; remote statuses 255 and -1 raise `@diagnostic.Failure`.
///
/// Resolution, build, startup, UTF-8 capture and timeout errors propagate.
/// Failure cancels and reaps directly managed children. Commands run in the
/// case's working directory and can modify files; no isolation is provided.
/// `case` and `context` must come from the same parsed/validated document.
pub async fn execute_case(
  case : @markdown.Case,
  context : @resolve.DocumentContext,
  target~ : String,
  timeout_ms~ : Int32,
) -> @output.Captured {
  let cwd = context.cwd_for(case)
  let progress = Progress::new(cwd)
  let result = @async.with_timeout_opt(timeout_ms, () => {
    let commands = []
    // Every local build succeeds before any tested program starts.
    for i, segment in case.pipeline {
      progress.phase = "resolve"
      progress.segment = Some(
        segment_label(i, case.pipeline.length(), segment.argv[1]),
      )
      progress.tool = None
      progress.pending = []
      progress.logs = []
      let resolved = context.resolve_target(case, segment.argv[1])
      let command = prepare_command(
        segment.argv,
        cwd,
        resolved,
        target~,
        extra_env=segment.extra_env,
        progress~,
      )
      commands.push(command)
    }
    capture_pipeline(commands, cwd, progress~)
  }) catch {
    e => raise progress.report(e)
  }
  match result {
    Some(actual) => actual
    None =>
      raise progress.report(
        @diagnostic.failure(
          "timed out after \{timeout_ms} ms (including build)",
        ),
      )
  }
}

///|
async fn prepare_command(
  argv : Array[String],
  cwd : String,
  resolved : @resolve.ResolvedTarget,
  target~ : String,
  extra_env~ : Map[String, String],
  progress~ : Progress,
) -> Command {
  let args = argv[2:].to_owned()
  match resolved {
    Remote(coordinate) =>
      {
        label: argv[1],
        program: "moonx",
        extra_env,
        args: ["--target", "wasm", coordinate, "--"] + args,
        remote: Some(coordinate),
      }
    Script(executable) => {
      // moonx combines build and program statuses. Check compilation first.
      ignore(
        build_artifact(
          ["run", "--build-only", "--target", "wasm", executable],
          cwd,
          extra_env~,
          progress~,
        ),
      )
      {
        label: argv[1],
        program: "moonx",
        extra_env,
        remote: None,
        args: [executable, "--"] + args,
      }
    }
    Package(module_root, package_path) => {
      let artifact = build_artifact(
        [
          "-C", module_root, "run", "--build-only", "--target", target, package_path,
        ],
        cwd,
        extra_env~,
        progress~,
      )
      if target == "wasm" {
        {
          label: argv[1],
          program: "moonrun",
          extra_env,
          remote: None,
          args: [artifact, "--"] + args,
        }
      } else {
        { label: argv[1], program: artifact, extra_env, remote: None, args, }
      }
    }
  }
}

///|
async fn build_artifact(
  args : Array[String],
  cwd : String,
  extra_env~ : Map[String, String],
  progress~ : Progress,
) -> String {
  progress.phase = "build"
  progress.tool = Some("moon")
  let build = capture_pipeline(
    [{ label: "moon", program: "moon", extra_env, args, remote: None, }],
    cwd,
    progress~,
    building=true,
  )
  if build.exit_code != 0 {
    raise @diagnostic.failure("build failed (exit \{build.exit_code})")
  }
  let artifact = parse_artifact(build.output) catch {
    e => raise progress.remember(e)
  }
  progress.logs = []
  @files.resolve_from(cwd, artifact)
}

///|
fn parse_artifact(output : String) -> String raise {
  let value = @json.parse(output) catch {
    _ => raise @diagnostic.failure("moon returned invalid build artifact JSON")
  }
  match value {
    { "artifacts_path": [String(path)], .. } => path
    _ =>
      raise @diagnostic.failure(
        "moon must return exactly one artifacts_path entry",
      )
  }
}
