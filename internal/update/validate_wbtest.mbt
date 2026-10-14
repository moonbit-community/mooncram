///|
test "validation rejects changed commands configuration case counts and output" {
  let source = "```mooncram user/tool\n$ export MODE=one\n$ set-current-working-directory .\n$ ./a.mbtx\nold\n```\n"
  let doc = @markdown.parse_document("validation.md", source)
  let captures : Array[@output.Captured] = [
    { output: "old\n", diagnostic: "", exit_code: 0, },
  ]
  validate_generated(doc, source, captures)
  for
    changed in [
      source.replace(old="./a.mbtx", new="./b.mbtx"),
      source.replace(old="user/tool", new="user/other"),
      source.replace(old="MODE=one", new="MODE=two"),
      source.replace(old="directory .", new="directory .."),
      source.replace(old="old\n", new="wrong\n"),
      source.replace(old="old\n", new="old\n$ ./b.mbtx\n"),
      source.replace(old="old\n", new="@STDOUT\n"),
    ] {
    try validate_generated(doc, changed, captures) catch {
      _ => ()
    } noraise {
      _ => fail("validation accepted: " + changed)
    }
  }
}
