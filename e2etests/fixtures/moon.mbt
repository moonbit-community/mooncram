///|
/// Offline build double: no compiler or registry is used by the tested CLI.
async fn main {
  match @env.get_env_var("MOONCRAM_TEST_BUILD_MODE").unwrap() {
    "fail" => {
      @stdio.stdout.write("build stdout detail\n")
      @stdio.stderr.write("compiler stderr detail\n")
      @sys.exit(9)
    }
    "invalid" => {
      @stdio.stdout.write("not build JSON\n")
      @stdio.stderr.write("artifact stderr detail\n")
    }
    "slow" => {
      @stdio.stderr.write("build started\n")
      @async.sleep(5000)
      @fs.write_file("build-timeout-finished.txt", "uncancelled build")
    }
    _ => @sys.exit(2)
  }
}
