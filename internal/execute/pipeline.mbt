///|
priv struct Command {
  label : String
  program : String
  args : Array[String]
  extra_env : Map[String, String]
  remote : String?
}

///|
/// Readers outlive the inner process group on failure, so reaping children
/// does not cancel their diagnostics. Every group still has bounded lifetime.
// Hidden/deprecated cleanup API for routes not consumed by a successful spawn.
#warnings("-deprecated")
async fn capture_pipeline(
  commands : Array[Command],
  cwd : String,
  progress~ : Progress,
  building~ : Bool = false,
) -> @output.Captured {
  progress.logs = []
  progress.pending = []
  progress.phase = if building { "build" } else { "start" }
  if !building {
    progress.segment = Some(
      segment_label(0, commands.length(), commands[0].label),
    )
    progress.tool = Some(commands[0].program)
  }
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
  let labels = commands.mapi((i, command) => {
    if building {
      progress.segment.unwrap()
    } else {
      segment_label(i, commands.length(), command.label)
    }
  })
  progress.pending = labels.map(label => Some(label))
  let phase = if building { "build" } else { "run" }
  let last = commands.length() - 1
  let stdout_log = StreamCapture::new(
    phase,
    "stdout",
    labels[last],
    commands[last].program,
  )
  progress.logs.push(stdout_log)
  @async.with_task_group(log_group => {
    let stdout = log_group.spawn(() => {
      capture_stream(out_reader, stdout_log, progress)
    })
    let errors = []
    try {
      let exit_code = @async.with_task_group(process_group => {
        // Close unused routes as soon as processes have been cancelled/reaped,
        // before the bounded diagnostic drain starts.
        defer {
          for input in inputs {
            input.close()
          }
          for output in outputs {
            output.close()
          }
        }
        let processes = []
        for i, command in commands {
          progress.phase = if building { "build" } else { "start" }
          progress.segment = Some(labels[i])
          progress.tool = Some(command.program)
          let is_last = i == last
          let stdout_writer = if is_last { out_writer } else { outputs[i] }
          let (reader, stderr_writer) = @process.read_from_process()
          readers.push(reader)
          outputs.push(stderr_writer)
          let log = StreamCapture::new(
            phase,
            "stderr",
            labels[i],
            command.program,
          )
          progress.logs.push(log)
          errors.push(
            log_group.spawn(() => capture_stream(reader, log, progress)),
          )
          let process = @process.spawn(
            process_group,
            command.program,
            command.args,
            cwd~,
            extra_env=command.extra_env,
            inherit_env=true,
            stdin=inputs[i],
            stdout=stdout_writer,
            stderr=stderr_writer,
            cancel_handler=@process.hard_cancel(),
          ) catch {
            @os_error.OSError(_) as e => {
              let error = @diagnostic.wrap(
                e,
                "failed to start '\{command.program}'",
              )
              raise progress.remember(error)
            }
            e => raise e
          }
          processes.push(
            process_group.spawn(() => {
              let status = process.wait()
              progress.pending[i] = None
              check_remote_status(command.remote, i + 1, status) catch {
                @diagnostic.Failure(_) as e =>
                  raise progress.remember(
                    @diagnostic.context(
                      e,
                      phase~,
                      segment=labels[i],
                      tool=command.program,
                    ),
                  )
                e => raise e
              }
              status
            }),
          )
        }
        progress.phase = phase
        progress.segment = if building { Some(labels[0]) } else { None }
        progress.tool = if building { Some(commands[0].program) } else { None }
        let mut exit_code = 0
        for process in processes {
          let status = process.wait()
          if status != 0 {
            exit_code = status
          }
        }
        exit_code
      })
      progress.phase = if building { "build" } else { "capture" }
      let diagnostic = StringBuilder()
      for stderr in errors {
        diagnostic.write_string(@output.normalize_output(stderr.wait()))
      }
      {
        output: @output.normalize_output(stdout.wait()),
        diagnostic: diagnostic.to_string(),
        exit_code,
      }
    } catch {
      @diagnostic.Failure(_) | @os_error.OSError(_) as e => {
        let primary = progress.remember(e)
        // Only readers remain. A descendant may still hold a pipe open; never
        // let preserving logs delay cancellation indefinitely. The outer case
        // deadline also covers this drain.
        ignore(
          @async.with_timeout_opt(100, () => {
            ignore(stdout.wait())
            for stderr in errors {
              ignore(stderr.wait())
            }
          }),
        ) catch {
          @diagnostic.Failure(_) | @async.WaitedTaskAlreadyCancelled => ()
          e => raise e
        }
        raise primary
      }
      e => raise e
    }
  })
}

///|
fn check_remote_status(
  coordinate : String?,
  segment : Int32,
  status : Int32,
) -> Unit raise {
  if coordinate is Some(coordinate) && (status == 255 || status == -1) {
    raise @diagnostic.failure(
      "remote '\{coordinate}', pipeline segment \{segment}: reserved execution status \{status}",
    )
  }
}
