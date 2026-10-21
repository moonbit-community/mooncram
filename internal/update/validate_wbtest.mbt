///|
test "validation rejects changed commands configuration case counts and output" {
  let source = "```mooncram user/tool\n#cwd(.)\n$ MODE=one moonx ./a.mbtx\nold\n```\n"
  let doc = @markdown.parse_document("validation.md", source)
  let captures : Array[@output.Captured] = [
    { output: "old\n", diagnostic: "", exit_code: 0, },
  ]
  validate_generated(doc, source, captures)
  for
    (changed, message) in [
      (
        source
        .replace(old="./a.mbtx", new="./b.mbtx")
        .replace(old="old\n", new="wrong\n"),
        "generated document changed command or configuration for case 1",
      ),
      (
        source.replace(old="user/tool", new="user/other"),
        "generated document changed cases or configuration",
      ),
      (
        source.replace(old="MODE=one", new="MODE=two"),
        "generated document changed command or configuration for case 1",
      ),
      (
        source.replace(old="#cwd(.)", new="#cwd(..)"),
        "generated document changed cases or configuration",
      ),
      (
        source.replace(old="old\n", new="wrong\n"),
        "generated expectation does not match captured output for case 1",
      ),
      (
        source.replace(old="old\n", new="old\n$ moonx ./b.mbtx\n"),
        "generated document changed cases or configuration",
      ),
      (
        source.replace(old="old\n", new="@STDOUT\n"),
        "generated document failed validation",
      ),
    ] {
    try validate_generated(doc, changed, captures) catch {
      e =>
        assert_true(
          @diagnostic.error_text(e).contains(message),
          msg=@diagnostic.error_text(e),
        )
    } noraise {
      _ => fail("validation accepted: " + changed)
    }
  }
}

///|
test "validation checks each capture before advancing to later commands" {
  let source = "```mooncram\n$ moonx ./a.mbtx\nfirst\n$ moonx ./b.mbtx\nsecond\n```\n"
  let doc = @markdown.parse_document("order.md", source)
  let changed = source.replace(old="./b.mbtx", new="./other.mbtx")
  for
    (output, message) in [
      (
        "wrong\n", "generated expectation does not match captured output for case 1",
      ),
      (
        "first\n", "generated document changed command or configuration for case 2",
      ),
    ] {
    try
      validate_generated(doc, changed, [
        { output, diagnostic: "", exit_code: 0, },
        { output: "second\n", diagnostic: "", exit_code: 0, },
      ])
    catch {
      e => assert_eq(@diagnostic.error_text(e), message)
    } noraise {
      _ => fail("validation accepted changed commands and output")
    }
  }
}
