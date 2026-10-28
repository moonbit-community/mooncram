///|
/// Offline build double: no compiler or registry is used by the tested CLI.
async fn main {
  match @env.get_env_var("MOONCRAM_TEST_BUILD_MODE").unwrap() {
    "fail" => {
      @stdio.stdout.text.write("build stdout detail\n")
      @stdio.stderr.text.write("compiler stderr detail\n")
      @sys.exit(9)
    }
    "invalid" => {
      @stdio.stdout.text.write("not build JSON\n")
      @stdio.stderr.text.write("artifact stderr detail\n")
    }
    "slow" => {
      @stdio.stderr.text.write("build started\n")
      @async.sleep(5000)
      @fs.write_text("build-timeout-finished.txt", "uncancelled build")
    }
    _ => @sys.exit(2)
  }
}
