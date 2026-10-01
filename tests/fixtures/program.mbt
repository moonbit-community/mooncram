///|
async fn main {
  let args = @env.args()
  match args.get(1).unwrap_or("hello") {
    "hello" => @stdio.stdout.write("Hello, Moon Bit!\n")
    "args" => println(args[2:].to_owned().to_json().stringify())
    "context" => {
      @stdio.stdout.write(@env.get_env_var("MODE").unwrap_or("missing") + "\n")
      @stdio.stdout.write(@env.get_env_var("MOONCRAM_INHERITED").unwrap_or("missing") + "\n")
      @stdio.stdout.write(@fs.read_file("relative.txt"))
      @stdio.stdout.write(@stdio.stdin.read_all())
    }
    "echo" => @stdio.stdout.write(@stdio.stdin.read_all())
    "streams" => {
      @stdio.stdout.write("one\n")
      @stdio.stderr.write("two\n")
      @stdio.stdout.write("three\n")
      @sys.exit(2)
    }
    "large" => {
      let out = "o".repeat(8192)
      let err = "e".repeat(8192)
      for _ in 0..<128 {
        @stdio.stdout.write(out)
        @stdio.stderr.write(err)
      }
      @stdio.stdout.write("\n")
      @stdio.stderr.write("\n")
    }
    "special" => @stdio.stdout.write("$ ./fake.mbtx\n[2]\n```\n\nvalue (regex)\n\u001b[31m\t\r\u0000😀  \nlast" )
    "crlf" => @stdio.stdout.write("one\r\ntwo\r\n")
    "setup" => @fs.write_file("side-effect.txt", "side effect preserved\n")
    "read" => @stdio.stdout.write(@fs.read_file("side-effect.txt"))
    "mutate" => @fs.write_file("mutate.md", "changed by command\n")
    "slow" => {
      @async.sleep(5000)
      @fs.write_file("slow-finished.txt", "finished")
    }
    "invalid-utf8" => @stdio.stdout.write(b"\xff")
    _ => @sys.exit(3)
  }
}
