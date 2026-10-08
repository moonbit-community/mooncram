///|
/// Both readers run while the child runs. Merged output uses the same OS pipe
/// for stdout and stderr, preserving the order in which bytes reach that pipe.
async fn capture(
  program : String,
  args : Array[String],
  cwd : String,
) -> @output.Captured {
  let (out_reader, out_writer) = @process.read_from_process()
  defer out_reader.close()
  defer out_writer.close()
  let (err_reader, err_writer) = @process.read_from_process()
  defer err_reader.close()
  defer err_writer.close()
  let (input, input_writer) = @process.write_to_process()
  input_writer.close()
  @async.with_task_group(group => {
    let stdout = group.spawn(() => out_reader.read_all().text())
    let stderr = group.spawn(() => err_reader.read_all().text())
    let code = @process.run(
      program,
      args,
      cwd~,
      stdin=input,
      stdout=out_writer,
      stderr=err_writer,
      cancel_handler=@process.hard_cancel(),
    )
    let out = @output.normalize_output(stdout.wait())
    let err = @output.normalize_output(stderr.wait())
    { output: out, diagnostic: err, exit_code: code, }
  })
}

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
      let executable = @files.resolve_from(cwd, case.argv[0])
      let args = case.argv[1:].to_owned()
      let kind = @fs.kind(executable)
      if kind == Regular && executable.has_suffix(".mbtx") {
        // moonx combines build and program statuses. Preflight the script so a
        // compiler failure cannot be accepted or saved as an expected exit.
        ignore(
          build_artifact(
            ["run", "--build-only", "--target", "wasm", executable],
            cwd,
          ),
        )
        capture("moonx", [executable, "--"] + args, cwd)
      } else if kind == Directory {
        if !@fs.exists(@files.resolve_from(executable, "moon.pkg")) &&
          !@fs.exists(@files.resolve_from(executable, "moon.pkg.json")) {
          raise @diagnostic.Failure(
            "directory is not a local MoonBit package: \{executable}",
          )
        }
        // moon validates is-main and the requested backend. Build output is never
        // mixed into the executable's expected stdout/stderr.
        let artifact = build_artifact(
          [
            "-C", executable, "run", "--build-only", "--target", target, executable,
          ],
          cwd,
        )
        if target == "wasm" {
          capture("moonrun", [artifact, "--"] + args, cwd)
        } else {
          capture(artifact, args, cwd)
        }
      } else {
        raise @diagnostic.Failure(
          "command must name a local .mbtx file or executable MoonBit package: \{case.argv[0]}",
        )
      }
    },
    error=@diagnostic.Failure(
      "timed out after \{timeout_ms} ms (including build)",
    ),
  )
}

///|
async fn build_artifact(args : Array[String], cwd : String) -> String {
  let build = capture("moon", args, cwd)
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
