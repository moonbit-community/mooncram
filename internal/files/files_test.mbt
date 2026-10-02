///|
async test "discovery sorts deduplicates and skips hidden build and symlink directories" {
  let dir = @fs.tmpdir(prefix="mooncram-discovery")
  defer @fs.rmdir(dir, recursive=true)
  for sub in ["visible", ".hidden", "_build", "target"] {
    @fs.mkdir(@files.resolve_from(dir, sub))
    @fs.write_file(@files.resolve_from(dir, sub + "/test.md"), "")
  }
  @fs.write_file(@files.resolve_from(dir, "a.md"), "")
  @fs.write_file(@files.resolve_from(dir, "b.md"), "")
  @fs.write_file(@files.resolve_from(dir, "ignore.txt"), "")
  @fs.symlink(target=dir, @files.resolve_from(dir, "cycle"))
  @fs.symlink(
    target=@files.resolve_from(dir, "a.md"),
    @files.resolve_from(dir, "alias.md"),
  )
  let paths = @files.discover([dir, @files.resolve_from(dir, "a.md")])
  // Canonical paths can include a volume prefix on Windows.
  assert_eq(paths, [
    @fs.realpath(@files.resolve_from(dir, "a.md")),
    @fs.realpath(@files.resolve_from(dir, "b.md")),
    @fs.realpath(@files.resolve_from(dir, "visible/test.md")),
  ])
}

///|
async test "atomic document replacement rejects concurrent edits and cleans up" {
  let dir = @fs.tmpdir(prefix="mooncram-update")
  defer @fs.rmdir(dir, recursive=true)
  let path = @files.resolve_from(dir, "test.md")
  @fs.write_file(path, "original")
  @files.write_document(path, "original", "updated")
  assert_eq(@fs.read_file(path).text(), "updated")
  assert_eq(@fs.readdir(dir, include_hidden=true), ["test.md"])
  try @files.write_document(path, "original", "would overwrite") catch {
    e => assert_true(@diagnostic.error_text(e).contains("source changed"))
  } noraise {
    _ => fail("concurrent modification should fail")
  }
  assert_eq(@fs.read_file(path).text(), "updated")
  assert_eq(@fs.readdir(dir, include_hidden=true), ["test.md"])
}
