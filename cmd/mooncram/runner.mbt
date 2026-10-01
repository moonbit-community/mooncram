///|
async fn run_cli(cli : Cli) -> Int {
  let files = discover(cli.paths)
  let color = use_color(cli.color)
  let mut total = 0
  let mut failed = 0
  let mut errors = 0
  let mut updated_cases = 0
  for file in files {
    try {
      let source = @fs.read_file(file).text()
      // Parse the whole document before executing anything in it.
      let document = parse_document(file, source, cli.config)
      let cwd = @path.Path(file).dirname().to_string()
      let edits = []
      let mut document_error = false
      for case in document.cases {
        total += 1
        try {
          let actual = execute_case(case, cwd)
          if !case.expected.matches(actual) {
            failed += 1
            @stdio.stdout.write(failure_report(file, case, actual, color))
            if cli.update {
              edits.push(case_edit(case, actual))
            }
          }
        } catch {
          e => {
            document_error = true
            errors += 1
            @stdio.stderr.write(
              "ERROR \{file}:\{case.line}: \{error_text(e)}\n  \{case.command}\n",
            )
          }
        }
      }
      if !edits.is_empty() && !document_error {
        let updated = apply_edits(source, edits)
        if cli.dry_run {
          @stdio.stdout.write("--- \{file}\n+++ \{file} (updated)\n")
          @stdio.stdout.write(
            diff_lines(output_lines(source).0, output_lines(updated).0, color),
          )
        } else {
          write_document(document, updated)
        }
        updated_cases += edits.length()
      }
      if document_error && !edits.is_empty() {
        @stdio.stderr.write(
          "Not updating \{file}: execution errors in this document\n",
        )
      }
    } catch {
      e => {
        errors += 1
        @stdio.stderr.write("ERROR \{file}: \{error_text(e)}\n")
      }
    }
  }
  if total == 0 && errors == 0 {
    @stdio.stderr.write("ERROR no mooncram cases found\n")
    return 2
  }
  let summary = if cli.update {
    let verb = if cli.dry_run { "would update" } else { "updated" }
    "\{total} cases, \{verb} \{updated_cases}, \{errors} errors\n"
  } else {
    "\{total} cases, \{failed} failed, \{errors} errors\n"
  }
  @stdio.stdout.write(summary)
  if errors > 0 {
    2
  } else if failed > 0 && !cli.update {
    1
  } else {
    0
  }
}
