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
