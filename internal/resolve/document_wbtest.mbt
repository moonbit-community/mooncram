///|
async test "shared targets use case directories and fence module scope with direct remote coordinates" {
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
    "```mooncram user/foo\n$ set-current-working-directory ../work\n$ moonx ./invalid.mbtx | moonx missing/module@1.2.3\n$ moonx user/foo/cmd/deep\n```\n```mooncram\n$ moonx user/foo/cmd/deep\n$ moonx missing/module@1.2.3\n```\n",
  )
  let context = validate_document(document, startup_cwd=root)
  let first = document.cases[0]
  assert_eq(context.cwd_for(first), work)
  assert_eq(context.cwd_for(document.cases[2]), docs)
  assert_true(
    context.resolve_target(first, "./invalid.mbtx") is Script(path) &&
    path == script,
  )
  for case in [first, document.cases[3]] {
    for
      coordinate in [
        "missing/module@1.2.3", "user/foo@1.2.3", "user/foo/cmd/deep@2.0.0-rc.1+build.007",
      ] {
      assert_true(
        context.resolve_target(case, coordinate) is Remote(value) &&
        value == coordinate,
      )
    }
    for
      coordinate in [
        "missing/module@latest", "missing/module@1.2", "missing/module@^1.2.3",
      ] {
      assert_async_error_contains(
        () => ignore(context.resolve_target(case, coordinate)),
        "exact SemVer required",
      )
    }
  }
  assert_true(
    context.resolve_target(document.cases[1], "user/foo/cmd/deep")
    is Package(module_root, path) &&
    module_root == root &&
    path == package_dir,
  )
  assert_async_error_contains(
    () => ignore(context.resolve_target(document.cases[2], "user/foo/cmd/deep")),
    "module-declared full package name",
  )
  assert_async_error_contains(
    () => ignore(context.resolve_target(first, "./missing.mbtx")),
    "missing.mbtx",
  )
  @fs.mkdir(@files.resolve_from(work, "directory.mbtx"))
  assert_async_error_contains(
    () => ignore(context.resolve_target(first, "./directory.mbtx")),
    "local .mbtx file",
  )
  // Versioned coordinates bypass local package configuration entirely.
  @fs.write_file(
    @files.resolve_from(package_dir, "moon.pkg"),
    "pkgtype(kind: false)",
  )
  assert_true(
    context.resolve_target(first, "user/foo/cmd/deep@1.2.3") is Remote(_),
  )
  assert_async_error_contains(
    () => ignore(context.resolve_target(first, "user/foo/cmd/deep")),
    "invalid configuration",
  )
  // An @ in a local script filename is still part of its path.
  let special = @files.resolve_from(work, "hello@world.mbtx")
  @fs.write_file(special, "not compilable")
  assert_true(
    context.resolve_target(first, "hello@world.mbtx") is Script(path) &&
    path == special,
  )
}

///|
async test "shared validation checks modules before directories including configuration fences" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-validation"))
  defer @fs.rmdir(root, recursive=true)
  let path = @files.resolve_from(root, "test.md")
  let document = @markdown.parse_document(
    path, "```mooncram user/foo\n$ set-current-working-directory .\n```\n```mooncram\n$ set-current-working-directory missing\n```\n",
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
