///|
async fn main {
  let code = try {
    let args = @env.args()
    run_cli(parse_cli(args[1:].to_owned()))
  } catch {
    e => {
      @stdio.stderr.write("ERROR \{error_text(e)}\n")
      2
    }
  }
  @sys.exit(code)
}
