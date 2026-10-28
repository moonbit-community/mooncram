///|
/// A complete toolchain double: calls record the executable path and inherited
/// environment, without compiling Wasm or relying on different real ABIs.
async fn main {
  let args = @env.args()
  let executable = @path.Path(args[0])
  let name = executable.basename().to_owned()
  let bin = executable.dirname()
  @fs.write_text(
    @env.get_env_var("MOONCRAM_TOOLCHAIN_LOG").unwrap(),
    Json::object({
      "tool": args[0].to_json(),
      "args": args[1:].to_owned().to_json(),
      "path": @env.get_env_var("PATH").unwrap_or("").to_json(),
      "cwd": @env.current_dir().unwrap().to_json(),
    }).stringify() + "\n",
    append=true,
    create_mode=OpenOrCreate,
  )
  if name == "moon" || name == "moon.exe" {
    assert_true(args.contains("--build-only"))
    let artifact = bin.join(@path.Path(if @path.sep == '\\' { "program.exe" } else { "program" })).to_string()
    println(Json::object({ "artifacts_path": [artifact].to_json() }).stringify())
  } else {
    if name == "moonx" || name == "moonx.exe" {
      assert_eq(args[1:3].to_owned(), ["--target", "wasm"])
      assert_eq(args[4], "--")
      if args.get(5) is Some("remove-file") {
        @fs.remove(args[6])
      }
    }
    println("fixture output")
  }
}
