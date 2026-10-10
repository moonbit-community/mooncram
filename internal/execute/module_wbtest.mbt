///|
async fn assert_async_error_contains(
  f : async () -> Unit,
  expected : String,
) -> Unit {
  try f() catch {
    e =>
      assert_true(
        @diagnostic.error_text(e).contains(expected),
        msg=@diagnostic.error_text(e),
      )
  } noraise {
    _ => fail("expected error containing: " + expected)
  }
}

///|
test "new and legacy package configurations determine callability" {
  for
    source in [
      "pkgtype(kind: \"executable\")", "options(\"is-main\": true)", "{\"is-main\":true}",
    ] {
    assert_true(
      callable_config(
        source,
        if source.has_prefix("{") {
          "moon.pkg.json"
        } else {
          "moon.pkg"
        },
      ),
    )
  }
  for
    source in [
      "", "pkgtype(kind: \"library\")", "options(\"is-main\": false)", "{\"is-main\":false}",
    ] {
    assert_true(
      !callable_config(
        source,
        if source.has_prefix("{") {
          "moon.pkg.json"
        } else {
          "moon.pkg"
        },
      ),
    )
  }
  for
    source in [
      "pkgtype(kind: true)", "{", "options(\"is-main\": \"yes\")", "options(\"is-main\":true, \"is-main\":false)",
    ] {
    assert_error_contains(
      () => {
        ignore(
          callable_config(
            source,
            if source.has_prefix("{") {
              "moon.pkg.json"
            } else {
              "moon.pkg"
            },
          ),
        )
      },
      "moon.pkg",
    )
  }
  for
    name in [
      "/tmp/foo", "./foo", "../foo", "cmd/../foo", "cmd//foo", "C:\\foo", "cmd\\foo",
      "",
    ] {
    assert_true(!valid_package_name(name))
  }
  for name in ["foo", "cmd/boo", "deep/cmd/boo"] {
    assert_true(valid_package_name(name))
  }
}

///|
async test "root and same-name subpackage selection matrix with source directory" {
  // Use canonical paths consistently, including Windows temporary paths.
  let dir = @fs.realpath(@fs.tmpdir(prefix="mooncram-module"))
  defer @fs.rmdir(dir, recursive=true)
  let src = @files.resolve_from(dir, "src")
  @fs.mkdir(src)
  let sub = @files.resolve_from(src, "foo")
  @fs.mkdir(sub)
  @fs.write_file(
    @files.resolve_from(dir, "moon.mod"),
    "name = \"user/foo\"\nsource = \"src\"",
  )
  let context = load_module(dir)
  assert_eq(context.name, "user/foo")
  assert_eq(context.root, @fs.realpath(dir))
  assert_eq(context.source_root, src)
  let warnings = []
  let warning : async (String) -> Unit = message => warnings.push(message)
  for root_main in [false, true] {
    for sub_main in [false, true] {
      @fs.write_file(
        @files.resolve_from(src, "moon.pkg"),
        if root_main {
          "pkgtype(kind: \"executable\")"
        } else {
          ""
        },
      )
      @fs.write_file(
        @files.resolve_from(sub, "moon.pkg.json"),
        if sub_main {
          "{\"is-main\":true}"
        } else {
          "{}"
        },
      )
      if root_main || sub_main {
        assert_eq(
          resolve_package(context, "foo", warning~),
          if root_main {
            src
          } else {
            sub
          },
        )
      } else {
        assert_async_error_contains(
          () => ignore(resolve_package(context, "foo", warning~)),
          "no executable package",
        )
      }
    }
  }
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0].contains("user/foo and user/foo/foo; selected user/foo"),
  )
  @fs.write_file(@files.resolve_from(sub, "moon.pkg"), "pkgtype(kind: false)")
  assert_async_error_contains(
    () => ignore(resolve_package(context, "foo", warning~)),
    "invalid configuration",
  )
}

///|
async test "deep packages and nested modules including symlinks stay within module boundaries" {
  let dir = @fs.realpath(@fs.tmpdir(prefix="mooncram-boundary"))
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file(@files.resolve_from(dir, "moon.mod"), "name = \"user/foo\"")
  let context = load_module(dir)
  let deep = @files.resolve_from(dir, "cmd/deep/boo")
  @fs.mkdir(deep, recursive=true)
  @fs.write_file(
    @files.resolve_from(deep, "moon.pkg"),
    "pkgtype(kind: \"executable\")",
  )
  assert_eq(resolve_package(context, "cmd/deep/boo", warning=_ => ()), deep)
  for config in ["moon.mod", "moon.mod.json"] {
    let boundary = @files.resolve_from(dir, "cmd/" + config)
    @fs.write_file(boundary, "")
    assert_async_error_contains(
      () => ignore(resolve_package(context, "cmd/deep/boo", warning=_ => ())),
      "nested modules",
    )
    @fs.symlink(target=deep, @files.resolve_from(dir, "alias"))
    assert_async_error_contains(
      () => ignore(resolve_package(context, "alias", warning=_ => ())),
      "nested modules",
    )
    @fs.remove(@files.resolve_from(dir, "alias"))
    @fs.remove(boundary)
  }
}

///|
async test "module declarations validate export-only fences before execution" {
  let dir = @fs.realpath(@fs.tmpdir(prefix="mooncram-declaration"))
  defer @fs.rmdir(dir, recursive=true)
  let doc = @markdown.parse_document(
    "test.md", "```mooncram\n$ ./a.mbtx\n```\n```mooncram user/foo\n$ export A=x\n```\n",
  )
  assert_async_error_contains(
    () => ignore(validate_document_modules(doc, dir)),
    "test.md:4: module declaration requires moon.mod",
  )
  let path = @files.resolve_from(dir, "moon.mod")
  for source in ["", "src"] {
    @fs.write_file(path, "name = \"user/foo\"\nsource = \"\{source}\"")
    assert_true(validate_document_modules(doc, dir) is Some(_))
    assert_eq(load_module(dir).source_root, @files.resolve_from(dir, source))
  }
  @fs.write_file(path, "name = \"user/bar\"")
  assert_async_error_contains(
    () => ignore(validate_document_modules(doc, dir)),
    "test.md:4: module declaration 'user/foo' does not match 'user/bar'",
  )
  @fs.write_file(path, "name =")
  assert_async_error_contains(
    () => ignore(validate_document_modules(doc, dir)),
    "test.md:4: invalid configuration",
  )
  @fs.write_file(path, "name = \"user/foo\"\nsource = \"../outside\"")
  assert_async_error_contains(
    () => ignore(load_module(dir)),
    "source must stay inside",
  )
  @fs.write_file(path, "name = \"user/foo\"\nsource = true")
  assert_async_error_contains(
    () => ignore(load_module(dir)),
    "source must be a string",
  )
}
