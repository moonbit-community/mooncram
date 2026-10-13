///|
fn assert_error_contains(f : () -> Unit raise, expected : String) -> Unit raise {
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
test "artifact JSON is validated" {
  assert_eq(
    parse_artifact("{\"artifacts_path\":[\"/tmp/a.wasm\"]}\n"),
    "/tmp/a.wasm",
  )
  for
    text in [
      "not JSON", "{}", "{\"artifacts_path\":[]}", "{\"artifacts_path\":[\"a\",\"b\"]}",
    ] {
    assert_error_contains(() => ignore(parse_artifact(text)), "artifact")
  }
}

///|
test "reserved statuses apply only to imports and report binding and segment" {
  let binding = @markdown.parse_document(
      "test.md", "```mooncram-import\ngrep : user/module@1.2.3\n```\n",
    ).imports["grep"]
  for status in [255, -1] {
    for
      expected in [
        "import 'grep' (user/module@1.2.3)",
        "pipeline segment 2",
        "status \{status}",
      ] {
      assert_error_contains(
        () => check_import_status(Some(binding), 2, status),
        expected,
      )
    }
    check_import_status(None, 2, status)
  }
  for status in [0, 1, 2, 254, -2, -9] {
    check_import_status(Some(binding), 1, status)
  }
}

///|
async test "working directory validation resolves all declarations including configuration-only blocks" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-cwd"))
  defer @fs.rmdir(root, recursive=true)
  let docs = @files.resolve_from(root, "docs")
  let workspace = @files.resolve_from(root, "workspace with spaces")
  @fs.mkdir(docs)
  @fs.mkdir(workspace)
  @fs.symlink(target=workspace, @files.resolve_from(docs, "link"))
  let path = @files.resolve_from(docs, "test.md")
  for
    argument in [
      "'../workspace with spaces'",
      "link",
      "'" + workspace.replace(old="\\", new="/") + "'",
    ] {
    let doc = @markdown.parse_document(
      path,
      "```mooncram\n$ set-current-working-directory " + argument + "\n```\n",
    )
    let directories = validate_document_working_directories(doc)
    assert_eq(directories.length(), 1)
    assert_eq(directories[2], @fs.realpath(workspace))
  }
  @fs.write_file(@files.resolve_from(docs, "file"), "")
  for name in ["missing", "file"] {
    let doc = @markdown.parse_document(
      path,
      "```mooncram\n$ ./a.mbtx\n```\n```mooncram\n$ set-current-working-directory " +
      name +
      "\n```\n",
    )
    for expected in [path + ":5:", @files.resolve_from(docs, name)] {
      assert_async_error_contains(
        () => ignore(validate_document_working_directories(doc)),
        expected,
      )
    }
  }
}
