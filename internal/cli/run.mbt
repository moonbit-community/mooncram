///|
/// Parse and run the `docs`, `check`, `test` or `update` command.
///
/// `args` contains arguments after the executable name. Paths default to `.`;
/// test/update default to Wasm and a 60000 ms deadline per case. Reports and
/// summaries go to stdout; errors go to stderr.
///
/// Returns 0 on success (including updates and dry runs), 1 when `test` has
/// assertion failures, or 2 on parsing, validation, execution or filesystem
/// errors, or when no cases are found. Document/case errors are reported while
/// other documents/cases continue. Argument-parser help/version requests may
/// terminate the process. Diagnostic failures and OS errors caught here are
/// printed and converted to 2; async output errors can still propagate.
///
/// `check` resolves targets without running tools. `test` and `update` build and
/// execute commands; `update` also writes changed documents unless `--dry-run`
/// is supplied. Dry runs still execute commands and can have their side effects.
/// `docs` lists or prints embedded documentation without discovering files or
/// executing cases, and returns 0 on success or 2 for an invalid request.
pub async fn run(args : Array[String]) -> Int32 {
  try {
    match parse_cli(args) {
      Run(cli) => run_cli(cli)
      DocsList => {
        @stdio.stdout.write(render_docs_list() + "\n")
        0
      }
      DocsShow(name) => {
        @stdio.stdout.write(render_doc_body(name))
        0
      }
    }
  } catch {
    @diagnostic.Failure(_) | @os_error.OSError(_) as e => {
      @stdio.stderr.write(@diagnostic.render(e))
      2
    }
    e => raise e
  }
}
