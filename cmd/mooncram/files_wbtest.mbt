///|
async test "discovery sorts deduplicates and skips hidden build and symlink directories" {
  let dir = @fs.tmpdir(prefix="mooncram-discovery")
  defer @fs.rmdir(dir, recursive=true)
  for sub in ["visible", ".hidden", "_build", "target"] {
    @fs.mkdir(resolve_from(dir, sub))
    @fs.write_file(resolve_from(dir, sub + "/test.md"), "")
  }
  @fs.write_file(resolve_from(dir, "a.md"), "")
  @fs.write_file(resolve_from(dir, "b.md"), "")
  @fs.write_file(resolve_from(dir, "ignore.txt"), "")
  @fs.symlink(target=dir, resolve_from(dir, "cycle"))
  @fs.symlink(target=resolve_from(dir, "a.md"), resolve_from(dir, "alias.md"))
  let paths = discover([dir, resolve_from(dir, "a.md")])
  assert_eq(paths, [
    resolve_from(dir, "a.md"),
    resolve_from(dir, "b.md"),
    resolve_from(dir, "visible/test.md"),
  ])
}

///|
async test "atomic document replacement rejects concurrent edits and cleans up" {
  let dir = @fs.tmpdir(prefix="mooncram-update")
  defer @fs.rmdir(dir, recursive=true)
  let path = resolve_from(dir, "test.md")
  @fs.write_file(path, "original")
  let doc = { path, source: "original", cases: [], }
  write_document(doc, "updated")
  assert_eq(@fs.read_file(path).text(), "updated")
  assert_eq(@fs.readdir(dir, include_hidden=true), ["test.md"])
  try write_document(doc, "would overwrite") catch {
    e => assert_true(error_text(e).contains("source changed"))
  } noraise {
    _ => fail("concurrent modification should fail")
  }
  assert_eq(@fs.read_file(path).text(), "updated")
  assert_eq(@fs.readdir(dir, include_hidden=true), ["test.md"])
}
