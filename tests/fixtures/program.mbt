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
    "check-env" => {
      assert_eq(@env.get_env_var(args[2]), Some(args[3]))
      println(args[3])
    }
    "check-env-echo" => {
      assert_eq(@env.get_env_var(args.get(3).unwrap_or("MODE")), Some(args[2]))
      @stdio.stdout.write(@stdio.stdin.read_all())
    }
    "read-file" => @stdio.stdout.write(@fs.read_file(args[2]))
    "relay" => {
      @stdio.stderr.write(args[2] + "\n")
      @stdio.stdout.write(@stdio.stdin.read_all())
    }
    "noisy-echo" => {
      for _ in 0..<128 {
        @stdio.stderr.write("e".repeat(8192))
      }
      @stdio.stdout.write(@stdio.stdin.read_all())
    }
    "binary" => {
      let bytes = Bytes::makei(8192, i => (i % 256).to_byte())
      for _ in 0..<128 {
        @stdio.stdout.write(bytes)
        @stdio.stderr.write("e".repeat(8192))
      }
    }
    "check-binary" => {
      for _ in 0..<128 {
        @stdio.stderr.write("e".repeat(8192))
      }
      let bytes = @stdio.stdin.read_all().binary()
      assert_eq(bytes.length(), 8192 * 128)
      for i, byte in bytes {
        assert_eq(byte, (i % 256).to_byte())
      }
      println("all bytes preserved")
    }
    "raw" => @stdio.stdout.write(b"one\r\ntwo\r\n\x00\xff")
    "check-raw" => {
      assert_eq(@stdio.stdin.read_all().binary(), b"one\r\ntwo\r\n\x00\xff")
      println("raw bytes preserved")
    }
    "raw-stderr" => {
      @stdio.stdout.write("discard me")
      @stdio.stderr.write(b"one\r\ntwo\r\n\x00\xff")
    }
    "check-eof" => {
      assert_eq(@stdio.stdin.read_all().binary().length(), 0)
      println("EOF")
    }
    "wait-downstream" => {
      @stdio.stdout.write("discard me")
      // The downstream pipe must close while this process is still alive.
      while !@fs.exists("downstream-eof.txt") {
        @async.sleep(10)
      }
    }
    "signal-eof" => {
      assert_eq(@stdio.stdin.read_all().binary().length(), 0)
      @fs.write_file("downstream-eof.txt", "EOF")
      println("EOF")
    }
    "check-large-merged" => {
      let bytes = @stdio.stdin.read_all().binary()
      assert_eq(bytes.length(), 2 * 8192 * 128 + 2)
      let mut out = 0
      let mut err = 0
      let mut newlines = 0
      for byte in bytes {
        match byte {
          b'o' => out += 1
          b'e' => err += 1
          b'\n' => newlines += 1
          _ => fail("unexpected merged byte")
        }
      }
      assert_eq(out, 8192 * 128)
      assert_eq(err, 8192 * 128)
      assert_eq(newlines, 2)
      println("large streams merged")
    }
    "check-large-stderr" => {
      let bytes = @stdio.stdin.read_all().binary()
      assert_eq(bytes.length(), 8192 * 128 + 1)
      for byte in bytes[:bytes.length() - 1] {
        assert_eq(byte, b'e')
      }
      assert_eq(bytes[bytes.length() - 1], b'\n')
      println("large stderr preserved")
    }
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
      let filename = args.get(2).unwrap_or("slow-finished.txt")
      @fs.write_file(filename + ".started", "started")
      @async.sleep(5000)
      @fs.write_file(filename, "finished")
    }
    "invalid-utf8" => @stdio.stdout.write(b"\xff")
    "invalid-stderr" => @stdio.stderr.write(b"\xff")
    _ => @sys.exit(3)
  }
}
