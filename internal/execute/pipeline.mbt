///|
priv struct Command {
  program : String
  args : Array[String]
  imported : @markdown.ToolImport?
  stderr_to_stdout : Bool
  stdout_to_null : Bool
}

///|
/// Only the final routed output is captured. OS pipes carry intermediate bytes without
/// decoding or normalization. Task-group failure cancels and reaps every child.
// ProcessInput.close is hidden/deprecated but is the dependency's cleanup API
// for inputs that have not been consumed because spawning failed or was cancelled.
#warnings("-deprecated")
async fn capture_pipeline(
  commands : Array[Command],
  cwd : String,
  extra_env~ : Map[String, String],
) -> @output.Captured {
  let inputs : Array[&@process.ProcessInput] = []
  let outputs : Array[&@process.ProcessOutput] = []
  let readers : Array[@process.ReadFromProcess] = []
  defer {
    for input in inputs {
      input.close()
    }
    for output in outputs {
      output.close()
    }
    for reader in readers {
      reader.close()
    }
  }
  let (input, input_writer) = @process.write_to_process()
  inputs.push(input)
  input_writer.close()
  for _ in 1..<commands.length() {
    let (input, output) = @process.pipe()
    inputs.push(input)
    outputs.push(output)
  }
  let (out_reader, out_writer) = @process.read_from_process()
  readers.push(out_reader)
  outputs.push(out_writer)
  // The first commands.length() outputs are the per-segment output routes.
  // Additional drain/diagnostic writers join the same cleanup registry below.
  @async.with_task_group(group => {
    let stdout = group.spawn(() => out_reader.read_all().text())
    let errors = []
    let processes = []
    for i, command in commands {
      let stdout_writer = if command.stdout_to_null {
        let (reader, writer) = @process.read_from_process()
        readers.push(reader)
        outputs.push(writer)
        group.spawn_bg(() => drain_output(reader))
        if !command.stderr_to_stdout {
          // No stream uses the downstream pipe: release it before spawning so
          // the consumer can see EOF without waiting for this process to exit.
          outputs[i].close()
        }
        writer
      } else {
        outputs[i]
      }
      let stderr_writer = if command.stderr_to_stdout {
        // ProcessOutput permits stdout and stderr of one child to share a pipe.
        outputs[i]
      } else {
        let (reader, writer) = @process.read_from_process()
        readers.push(reader)
        outputs.push(writer)
        errors.push(group.spawn(() => reader.read_all().text()))
        writer
      }
      let process = @process.spawn(
        group,
        command.program,
        command.args,
        cwd~,
        extra_env~,
        inherit_env=true,
        stdin=inputs[i],
        stdout=stdout_writer,
        stderr=stderr_writer,
        cancel_handler=@process.hard_cancel(),
      )
      // Monitor every segment concurrently. A failure here cancels the group,
      // whose process tasks hard-cancel and reap all remaining children.
      processes.push(
        group.spawn(() => {
          let status = process.wait()
          check_import_status(command.imported, i + 1, status)
          status
        }),
      )
    }
    let mut exit_code = 0
    for process in processes {
      exit_code = process.wait()
    }
    let diagnostic = StringBuilder()
    for stderr in errors {
      diagnostic.write_string(@output.normalize_output(stderr.wait()))
    }
    {
      output: @output.normalize_output(stdout.wait()),
      diagnostic: diagnostic.to_string(),
      exit_code,
    }
  })
}

///|
fn check_import_status(
  imported : @markdown.ToolImport?,
  segment : Int,
  status : Int,
) -> Unit raise {
  if imported is Some(binding) && (status == 255 || status == -1) {
    raise @diagnostic.Failure(
      "import '\{binding.name}' (\{binding.coordinate}), pipeline segment \{segment}: reserved execution status \{status}",
    )
  }
}

///|
/// Discard bytes without accumulating output or attempting UTF-8 decoding.
async fn drain_output(reader : @process.ReadFromProcess) -> Unit {
  let buffer = FixedArray::make(8192, b'\x00')
  while reader.read(buffer) != 0 {
    ()
  }
}
