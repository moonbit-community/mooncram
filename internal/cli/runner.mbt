///|
async fn run_cli(cli : Cli) -> Int32 {
  let startup_cwd = @path.Path(".").resolve().to_string()
  let toolchain = @execute.Toolchain::new(startup_cwd)
  let files = @files.discover(cli.paths)
  let color = @report.use_color(cli.color)
  let mut total = 0
  let mut failed = 0
  let mut errors = 0
  let mut updated_cases = 0
  for file in files {
    try {
      let source = @fs.read_file(file).text() catch {
        @os_error.OSError(_) | @utf8.Malformed(_) as e =>
          raise @diagnostic.wrap(e, "failed to read Markdown document")
        e => raise e
      }
      // Parse the whole document before executing anything in it.
      let document = @markdown.parse_document(file, source)
      let context = @resolve.validate_document(document, startup_cwd~)
      let captures = []
      let mut document_error = false
      for case in document.cases {
        total += 1
        try {
          if cli.command is Check {
            for i, segment in case.pipeline {
              ignore(context.resolve_target(case, segment.argv[1])) catch {
                @diagnostic.Failure(_) as e =>
                  raise @diagnostic.context(
                    e,
                    phase="resolve",
                    cwd=context.cwd_for(case),
                    segment="\{i + 1}/\{case.pipeline.length()} (\{segment.argv[1]})",
                  )
                e => raise e
              }
            }
            continue
          }
          let actual = @execute.execute_case(
            case,
            context,
            toolchain~,
            target=cli.target,
            timeout_ms=cli.timeout_ms,
          )
          if !case.expected.matches(actual) {
            failed += 1
            @stdio.stdout.write(
              @report.failure_report(file, case, actual, color),
            )
          }
          if cli.command is Update(_) {
            captures.push(actual)
          }
        } catch {
          @diagnostic.Failure(_) | @os_error.OSError(_) as e => {
            document_error = true
            errors += 1
            @stdio.stderr.write(
              @diagnostic.render(
                @diagnostic.context(
                  e,
                  file~,
                  line=case.line,
                  command=case.command,
                ),
              ),
            )
          }
          e => raise e
        }
      }
      if !captures.is_empty() && !document_error {
        let generated = @update.generate(document, captures)
        let updated = generated.source
        if updated == source {
          continue
        }
        if cli.command is Update(dry_run=true) {
          @stdio.stdout.write("--- \{file}\n+++ \{file} (updated)\n")
          @stdio.stdout.write(
            @report.diff_lines(
              @output.output_lines(source).0,
              @output.output_lines(updated).0,
              color,
            ),
          )
        } else {
          @files.write_document(document.path, document.source, updated) catch {
            @diagnostic.Failure(_)
            | @os_error.OSError(_)
            | @utf8.Malformed(_) as e =>
              raise @diagnostic.wrap(e, "failed to update Markdown document")
            e => raise e
          }
        }
        updated_cases += generated.changed_cases
      }
      if document_error && !captures.is_empty() {
        @stdio.stderr.write(
          "Not updating \{file}: execution errors in this document\n",
        )
      }
    } catch {
      @diagnostic.Failure(_) | @os_error.OSError(_) as e => {
        errors += 1
        @stdio.stderr.write(@diagnostic.render(@diagnostic.context(e, file~)))
      }
      e => raise e
    }
  }
  if total == 0 && errors == 0 {
    @stdio.stderr.write("ERROR no mooncram cases found\n")
    return 2
  }
  let summary = match cli.command {
    Check => "\{total} cases, \{errors} errors\n"
    Update(dry_run~) => {
      let verb = if dry_run { "would update" } else { "updated" }
      "\{total} cases, \{verb} \{updated_cases}, \{errors} errors\n"
    }
    Test => "\{total} cases, \{failed} failed, \{errors} errors\n"
  }
  @stdio.stdout.write(summary)
  if errors > 0 {
    2
  } else if failed > 0 && cli.command is Test {
    1
  } else {
    0
  }
}
