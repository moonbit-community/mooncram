///|
async test "shared targets use case directories and fence module scope with file imports" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-resolve"))
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(@files.resolve_from(root, "moon.mod"), "name = \"user/foo\"")
  let docs = @files.resolve_from(root, "docs")
  let work = @files.resolve_from(root, "work")
  @fs.mkdir(docs)
  @fs.mkdir(work)
  let script = @files.resolve_from(work, "invalid.mbtx")
  @fs.write_file(script, "not compilable")
  let package_dir = @files.resolve_from(root, "cmd/deep")
  @fs.mkdir(package_dir, recursive=true)
  @fs.write_file(
    @files.resolve_from(package_dir, "moon.pkg"),
    "pkgtype(kind: \"executable\")\nsupported_targets = \"js\"",
  )
  let document = @markdown.parse_document(
    @files.resolve_from(docs, "test.md"),
    "```mooncram user/foo\n$ set-current-working-directory ../work\n$ ./invalid.mbtx | remote\n$ cmd/deep\n```\n```mooncram\n$ cmd/deep\n$ remote\n```\n```mooncram-import\nremote : missing/module@1.2.3\n```\n",
  )
  let context = validate_document(document, startup_cwd=root)
  let first = document.cases[0]
  assert_eq(context.cwd_for(first), work)
  assert_eq(context.cwd_for(document.cases[2]), docs)
  assert_true(
    context.resolve_target(first, "./invalid.mbtx", warning=_ => ())
    is Script(path) &&
    path == script,
  )
  for case in [first, document.cases[3]] {
    assert_true(
      context.resolve_target(case, "remote", warning=_ => ())
      is Imported(binding) &&
      binding.coordinate == "missing/module@1.2.3",
    )
  }
  assert_true(
    context.resolve_target(document.cases[1], "cmd/deep", warning=_ => ())
    is Package(module_root, path) &&
    module_root == root &&
    path == package_dir,
  )
  assert_async_error_contains(
    () => {
      ignore(
        context.resolve_target(document.cases[2], "cmd/deep", warning=_ => ()),
      )
    },
    "command requires a .mbtx file",
  )
  assert_async_error_contains(
    () => {
      ignore(context.resolve_target(first, "./missing.mbtx", warning=_ => ()))
    },
    "missing.mbtx",
  )
  @fs.mkdir(@files.resolve_from(work, "directory.mbtx"))
  assert_async_error_contains(
    () => {
      ignore(context.resolve_target(first, "./directory.mbtx", warning=_ => ()))
    },
    "local .mbtx file",
  )
  // Conflict checks apply only in module-declared fences, including malformed configs.
  let local_dir = @files.resolve_from(root, "remote")
  @fs.mkdir(local_dir)
  let config = @files.resolve_from(local_dir, "moon.pkg")
  @fs.write_file(config, "pkgtype(kind: \"executable\")")
  assert_async_error_contains(
    () => ignore(context.resolve_target(first, "remote", warning=_ => ())),
    "ambiguous import alias 'remote' (missing/module@1.2.3)",
  )
  assert_true(
    context.resolve_target(document.cases[3], "remote", warning=_ => ())
    is Imported(_),
  )
  @fs.write_file(config, "pkgtype(kind: false)")
  assert_async_error_contains(
    () => ignore(context.resolve_target(first, "remote", warning=_ => ())),
    "invalid configuration",
  )
}

///|
async test "shared validation checks modules before directories including configuration fences" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-validation"))
  defer @fs.rmdir(root, recursive=true)
  let path = @files.resolve_from(root, "test.md")
  let document = @markdown.parse_document(
    path, "```mooncram user/foo\n$ export A=x\n```\n```mooncram\n$ set-current-working-directory missing\n```\n",
  )
  assert_async_error_contains(
    () => ignore(validate_document(document, startup_cwd=root)),
    "requires moon.mod",
  )
  @fs.write_file(@files.resolve_from(root, "moon.mod"), "name = \"user/foo\"")
  assert_async_error_contains(
    () => ignore(validate_document(document, startup_cwd=root)),
    "test.md:5: invalid working directory",
  )
}
