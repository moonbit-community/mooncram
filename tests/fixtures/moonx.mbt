///|
/// Offline moonx double. The integration runner appends the usual fixture
/// program after this helper and builds a native executable named moonx.
async fn imported_args() -> Array[String] {
  let raw = @env.args()
  assert_eq(raw[1:3].to_owned(), ["--target", "wasm"])
  assert_true(raw[3] == "fixture/tool@1.2.3" || raw[3] == "fixture/tool/cmd@2.0.0-rc.1+build.007")
  assert_eq(raw[4], "--")
  let args = [raw[0]] + raw[5:].to_owned()
  match args.get(1).unwrap_or("hello") {
    "invocation" => {
      println(raw[1:].to_owned().to_json().stringify())
      @sys.exit(0)
    }
    "status" | "reserved-after" => {
      if args[1] == "reserved-after" {
        while !@fs.exists(args[3] + ".started") {
          @async.sleep(10)
        }
      } else {
        // Let the runner start all pipeline segments before exiting.
        @async.sleep(100)
      }
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
