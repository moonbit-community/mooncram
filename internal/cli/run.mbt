///|
/// Run the command line and translate errors to the CLI exit status.
pub async fn run(args : Array[String]) -> Int {
  run_cli(parse_cli(args)) catch {
    e => {
      @stdio.stderr.write("ERROR \{@diagnostic.error_text(e)}\n")
      2
    }
  }
}
