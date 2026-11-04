///|
test "empty expectations update alongside fence normalization across document sizes" {
  let actual : @output.Captured = {
    output: "hello\n",
    diagnostic: "",
    exit_code: 0,
  }
  // Cross the sort's small-array boundary and vary the positions of equal keys.
  for count in 1..<=32 {
    for width in [3, 4, 6] {
      for gap in ["", "\n"] {
        let marker = "`".repeat(width)
        let block = marker +
          "mooncram\n$ moonx ./hello.mbtx\n" +
          gap +
          marker +
          "\n"
        let document = @markdown.parse_document("empty.md", block.repeat(count))
        let captures = Array::make(count, actual)
        let generated = @update.generate(document, captures)
        assert_eq(
          generated.source,
          ("```mooncram\n$ moonx ./hello.mbtx\nhello\n" + gap + "```\n").repeat(
            count,
          ),
        )
        assert_eq(generated.changed_cases, count)
        let parsed = @markdown.parse_document("empty.md", generated.source)
        let again = @update.generate(parsed, captures)
        assert_eq(again.source, generated.source)
        assert_eq(again.changed_cases, 0)
      }
    }
  }
}
