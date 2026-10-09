///|
priv struct Command {
  program : String
  args : Array[String]
}

///|
/// Only the final stdout is captured. OS pipes carry intermediate bytes without
/// decoding or normalization. Task-group failure cancels and reaps every child.
// ProcessInput.close is hidden/deprecated but is the dependency's cleanup API
// for inputs that have not been consumed because spawning failed or was cancelled.
#warnings("-deprecated")
async fn capture_pipeline(
  commands : Array[Command],
  cwd : String,
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
  @async.with_task_group(group => {
    let stdout = group.spawn(() => out_reader.read_all().text())
    let errors = []
    let processes = []
    for i, command in commands {
      let (err_reader, err_writer) = @process.read_from_process()
      readers.push(err_reader)
      // Track even unconsumed handles so a failed spawn cannot leak them.
      defer err_writer.close()
      errors.push(group.spawn(() => err_reader.read_all().text()))
      processes.push(
        @process.spawn(
          group,
          command.program,
          command.args,
          cwd~,
          stdin=inputs[i],
          stdout=outputs[i],
          stderr=err_writer,
          cancel_handler=@process.hard_cancel(),
        ),
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
