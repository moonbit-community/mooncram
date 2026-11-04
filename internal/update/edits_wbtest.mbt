///|
test "insertions precede replacements at the same source position" {
  let insertion : Edit = { start: 2, end: 2, text: "hello\n", }
  let replacement : Edit = { start: 2, end: 6, text: "```", }
  for edits in [[replacement, insertion], [insertion, replacement]] {
    assert_eq(apply_edits("ab````cd", edits), "abhello\n```cd")
  }
}

///|
test "edits allow adjacent replacements and insertions at document boundaries" {
  assert_eq(
    apply_edits("abc", [
      { start: 3, end: 3, text: ">", },
      { start: 1, end: 3, text: "BC", },
      { start: 0, end: 1, text: "A", },
      { start: 0, end: 0, text: "<", },
    ]),
    "<ABC>",
  )
  assert_eq(apply_edits("", [{ start: 0, end: 0, text: "new", }]), "new")
  assert_eq(apply_edits("unchanged", []), "unchanged")
}

///|
test "edits reject invalid ranges overlaps and insertions inside replacements" {
  for
    edits in [
      [{ start: -1, end: 0, text: "", }],
      [{ start: 1, end: 0, text: "", }],
      [{ start: 0, end: 4, text: "", }],
      [{ start: 4, end: 4, text: "", }],
      [{ start: 0, end: 2, text: "a", }, { start: 1, end: 3, text: "b", }],
      [{ start: 0, end: 2, text: "a", }, { start: 1, end: 1, text: "b", }],
      [{ start: 0, end: 1, text: "a", }, { start: 0, end: 1, text: "b", }],
    ] {
    try apply_edits("abc", edits) catch {
      @diagnostic.Failure(_) as e =>
        assert_true(
          @diagnostic.error_text(e).has_prefix(
            "invalid or overlapping update edit",
          ),
        )
      e => raise e
    } noraise {
      _ => fail("accepted invalid edits")
    }
  }
}
