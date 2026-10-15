///|
test "legacy import fences are ordinary ignored Markdown" {
  for
    declaration in [
      "```mooncram-import\ngrep : user/tool@1.2.3\n```\n", "```mooncram-import ignored settings\ninvalid : declaration\n```\n",
      "```mooncram-import\n\n```\n",
    ] {
    for
      source in [
        declaration + "```mooncram\n$ moonx user/tool@1.2.3 --version\n```\n",
        "```mooncram\n$ moonx user/tool@1.2.3 --version\n```\n" +
        declaration +
        declaration,
      ] {
      let doc = parse_document("legacy.md", source)
      assert_eq(doc.cases.length(), 1)
      assert_eq(
        doc.cases[0].pipeline,
        plain_pipeline([["user/tool@1.2.3", "--version"]]),
      )
    }
    assert_true(parse_document("legacy.md", declaration).cases.is_empty())
  }
}
