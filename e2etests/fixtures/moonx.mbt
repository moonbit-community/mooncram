///|
/// Offline moonx double. The integration runner appends the usual fixture
/// program after this helper and builds a native executable named moonx.
async fn remote_args() -> Array[String] {
  let raw = @env.args()
  if raw.get(1) is Some(script) && script.has_suffix(".mbtx") {
    @sys.exit(@process.run(
      @env.get_env_var("MOONCRAM_TEST_REAL_MOONX").unwrap(),
      raw[1:],
      stdin=@stdio.stdin,
      stdout=@stdio.stdout,
      stderr=@stdio.stderr,
    ).exit_code)
  }
  assert_eq(raw[1:3].to_owned(), ["--target", "wasm"])
  assert_true(raw[3] == "mooncram/integration/cmd@1.2.3" || raw[3] == "fixture/tool@1.2.3" || raw[3] == "fixture/tool/cmd@2.0.0-rc.1+build.007")
  assert_eq(raw[4], "--")
  let args = [raw[0]] + raw[5:].to_owned()
  match args.get(1).unwrap_or("hello") {
    "invocation" => {
      println(raw[1:].to_owned().to_json().stringify())
      @sys.exit(0)
    }
    "held-stderr" | "held-success" => {
      let process = @process.spawn_orphan(
        @env.get_env_var("MOONCRAM_TEST_NODE").unwrap(),
        ["-e", "setTimeout(() => {}, 10000)"],
        stdout=@stdio.stdout, stderr=@stdio.stderr,
      )
      @stdio.stderr.text.write("held-pid=\{process.pid}\nheld diagnostic\n")
      @sys.exit(if args[1] == "held-stderr" { 255 } else { 0 })
    }
    "reserved-output" => {
      @stdio.stdout.text.write("stdout before failure\n")
      @stdio.stderr.text.write("stderr-begin\n" + "e".repeat(70000) + "\nstderr-end\n")
      @sys.exit(@string.parse_int(args[2]))
    }
    "reserved-after" => {
      while !@fs.exists(args[3] + ".started") {
        @async.sleep(10)
      }
      @stdio.stderr.text.write("failure after sibling started\n")
      @sys.exit(@string.parse_int(args[2]))
    }
    "signal" | "signal-after" => {
      if args[1] == "signal-after" {
        while !@fs.exists(args[2] + ".started") {
          @async.sleep(10)
        }
      } else {
        @async.sleep(100)
      }
      @stdio.stderr.text.write("stderr before signal\n")
      @process.run(
        @env.get_env_var("MOONCRAM_TEST_NODE").unwrap(),
        ["-e", "process.kill(process.ppid, 'SIGHUP')"],
      ) |> ignore
      @sys.exit(254)
    }
    _ => ()
  }
  args
}
