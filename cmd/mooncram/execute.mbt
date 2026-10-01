///|
fn resolve_from(directory : String, name : String) -> String {
  let path = @path.Path(name)
  (if path.is_absolute() { path } else { @path.Path(directory).join(path) })
  .normalize()
  .to_string()
}

///|
/// Both readers run while the child runs. Merged output uses the same OS pipe
/// for stdout and stderr, preserving the order in which bytes reach that pipe.
async fn capture(
  program : String,
  args : Array[String],
  cwd : String,
  config : Config,
) -> Captured {
  let (out_reader, out_writer) = @process.read_from_process()
  defer out_reader.close()
  defer out_writer.close()
  let (err_reader, err_writer) = @process.read_from_process()
  defer err_reader.close()
  defer err_writer.close()
  let input = match config.stdin {
    Some(file) => @process.redirect_from_file(resolve_from(cwd, file))
    None => {
      let (input, writer) = @process.write_to_process()
      writer.close()
      input
    }
  }
  @async.with_task_group(group => {
    let stdout = group.spawn(() => out_reader.read_all().text())
    let stderr = if config.stream == Merged {
      err_writer.close()
      None
    } else {
      Some(group.spawn(() => err_reader.read_all().text()))
    }
    let code = @process.run(
      program,
      args,
      cwd~,
      extra_env=config.env,
      stdin=input,
      stdout=out_writer,
      stderr=if config.stream == Merged { out_writer } else { err_writer },
      cancel_handler=@process.hard_cancel(),
    )
    let out = normalize_output(stdout.wait())
    let err = match stderr {
      Some(task) => normalize_output(task.wait())
      None => ""
    }
    if config.stream == Stderr {
      { output: err, diagnostic: out, exit_code: code, }
    } else {
      { output: out, diagnostic: err, exit_code: code, }
    }
  })
}

///|
async fn execute_case(case : Case, cwd : String) -> Captured {
  @async.with_timeout(
    case.config.timeout_ms,
    () => {
      let executable = resolve_from(cwd, case.argv[0])
      let args = case.argv[1:].to_owned()
      let kind = @fs.kind(executable)
      if kind == Regular && executable.has_suffix(".mbtx") {
        // moonx combines build and program statuses. Preflight the script so a
        // compiler failure cannot be accepted or saved as an expected exit.
        ignore(
          build_artifact(
            ["run", "--build-only", "--target", "wasm", executable],
            cwd,
            case.config,
          ),
        )
        capture("moonx", [executable, "--"] + args, cwd, case.config)
      } else if kind == Directory {
        if !@fs.exists(resolve_from(executable, "moon.pkg")) &&
          !@fs.exists(resolve_from(executable, "moon.pkg.json")) {
          raise Failure(
            "directory is not a local MoonBit package: \{executable}",
          )
        }
        // moon validates is-main and the requested backend. Build output is never
        // mixed into the executable's expected stdout/stderr.
        let artifact = build_artifact(
          [
            "-C",
            executable,
            "run",
            "--build-only",
            "--target",
            case.config.target,
            executable,
          ],
          cwd,
          case.config,
        )
        if case.config.target == "wasm" {
          capture("moonrun", [artifact, "--"] + args, cwd, case.config)
        } else {
          capture(artifact, args, cwd, case.config)
        }
      } else {
        raise Failure(
          "command must name a local .mbtx file or executable MoonBit package: \{case.argv[0]}",
        )
      }
    },
    error=Failure(
      "timed out after \{case.config.timeout_ms} ms (including build)",
    ),
  )
}

///|
async fn build_artifact(
  args : Array[String],
  cwd : String,
  config : Config,
) -> String {
  let build = capture("moon", args, cwd, {
    ..config,
    stream: Stdout,
    stdin: None,
  })
  if build.exit_code != 0 {
    raise Failure(
      "build failed (exit \{build.exit_code})\n\{build.output}\{build.diagnostic}",
    )
  }
  let artifact = parse_artifact(build.output) catch {
    e => raise Failure("\{error_text(e)}\n\{build.output}\{build.diagnostic}")
  }
  resolve_from(cwd, artifact)
}

///|
fn parse_artifact(output : String) -> String raise {
  let value = @json.parse(output) catch {
    _ => raise Failure("moon returned invalid build artifact JSON")
  }
  match value {
    { "artifacts_path": [String(path)], .. } => path
    _ => raise Failure("moon must return exactly one artifacts_path entry")
  }
}
