///|
test "remote coordinates require full paths and exact SemVer" {
  for
    coordinate in [
      "module@1.2.3", "user/module", "user/module@latest", "user/module@^1.2.3",
      "user/module@~1.2.3", "user/module@1.*", "user/module@>=1.2.3", "/user/module@1.2.3",
      "user//module@1.2.3", "user/../module@1.2.3", "user/./module@1.2.3", "user/module/@1.2.3",
      "user/module@1.2.3@other", "user/module@1.2", "user/module@1.2.3.4", "user/module@v1.2.3",
      "user/module@01.2.3", "user/module@1.02.3", "user/module@1.2.03", "user/module@1.2.3-",
      "user/module@1.2.3+", "user/module@1.2.3-01", "user/module@1.2.3-alpha..1",
      "user/module@1.2.3+build..1", "user/module@1.2.3+build+again", "user/module@1.2.3-α",
      "user/module@1.2.3_a",
    ] {
    assert_true(!valid_coordinate(coordinate), msg=coordinate)
  }
  for
    coordinate in [
      "user/module@0.0.0", "u/m/pkg@1.2.3-0.a-b+01.x-y", "u/m@999999999999999999999.0.0",
    ] {
    assert_true(valid_coordinate(coordinate), msg=coordinate)
  }
}
