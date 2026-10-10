///|
test "imports apply file-wide with exact coordinates and source positions" {
  let tests = "```mooncram\n$ grep --version\nversion\n```\n"
  let declaration = "\n> - ````mooncram-import\n>   grep : user/module@0.3.5\n>   \n>   Grep_2-x : user/module/cmd/tool@1.2.3-alpha.1+build.007\n>   ````\n"
  for source in [tests + declaration, declaration + tests] {
    let doc = parse_document("imports.md", source)
    assert_eq(doc.cases.length(), 1)
    assert_eq(doc.imports.length(), 2)
    assert_eq(doc.imports["grep"].name, "grep")
    assert_eq(doc.imports["grep"].coordinate, "user/module@0.3.5")
    assert_eq(
      doc.imports["grep"].line,
      if source == tests + declaration {
        7
      } else {
        3
      },
    )
    assert_eq(
      doc.imports["Grep_2-x"].coordinate,
      "user/module/cmd/tool@1.2.3-alpha.1+build.007",
    )
    assert_eq(doc.cases[0].pipeline, plain_pipeline([["grep", "--version"]]))
    assert_eq(doc.cases[0].command, "$ grep --version")
    assert_true(doc.imports.get("GREP") is None)
  }
  assert_true(parse_example("$ ./a.mbtx\n").imports.is_empty())
  assert_eq(parse_document("only.md", declaration).cases.length(), 0)
}

///|
test "imports reject duplicate blocks and aliases with both original locations" {
  let declaration = "```mooncram-import\ngrep : user/module@1.2.3\n```\n"
  for expected in ["duplicates.md:5:", "first declared at duplicates.md:1"] {
    assert_error_contains(
      () => {
        ignore(
          parse_document("duplicates.md", declaration + "\n" + declaration),
        )
      },
      expected,
    )
  }
  let duplicate = "> - ```mooncram-import\n>   grep : user/module@1.2.3\n>   grep : other/module@2.0.0\n>   ```\n"
  for
    expected in [
      "duplicates.md:3: duplicate import alias", "first declared at duplicates.md:2",
    ] {
    assert_error_contains(
      () => ignore(parse_document("duplicates.md", duplicate)),
      expected,
    )
  }
}

///|
test "import fences require declarations closing fences and no settings" {
  for body in ["", "\n \t\n"] {
    assert_error_contains(
      () => {
        ignore(
          parse_document("empty.md", "```mooncram-import\n" + body + "```\n"),
        )
      },
      "empty.md:1: empty mooncram-import block",
    )
  }
  assert_error_contains(
    () => {
      ignore(
        parse_document(
          "open.md", "\n> ```mooncram-import\n> grep : user/module@1.0.0\n",
        ),
      )
    },
    "open.md:2: unclosed mooncram-import fence",
  )
  for settings in ["user/module", "{}", "wasm", "x y"] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "settings.md",
            "```mooncram-import " +
            settings +
            "\ngrep : user/module@1.0.0\n```\n",
          ),
        )
      },
      "settings.md:1: mooncram-import does not accept settings",
    )
  }
  let ignored = "~~~mooncram-import\ninvalid\n~~~\n````markdown\n```mooncram-import\ninvalid\n```\n````\n```Mooncram-import\ninvalid\n```\n"
  assert_true(parse_document("ignored.md", ignored).imports.is_empty())
}

///|
test "import grammar rejects expansion defaults malformed paths and versions" {
  for
    declaration in [
      "grep", "grep = user/module@1.2.3", "grep : user/module@1.2.3 : extra", "export : user/module@1.2.3",
      "1grep : user/module@1.2.3", "-grep : user/module@1.2.3", "a.b : user/module@1.2.3",
      "a/b : user/module@1.2.3", "${NAME} : user/module@1.2.3", "grep : user/module@1.2.3 --flag",
      "grep : ${COORD}", "grep : user/module@${VERSION}",
    ] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "invalid.md",
            "\n- ```mooncram-import\n  " + declaration + "\n  ```\n",
          ),
        )
      },
      "invalid.md:3:",
    )
  }
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
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "invalid.md",
            "```mooncram-import\ngrep : " + coordinate + "\n```\n",
          ),
        )
      },
      "invalid.md:2: invalid import coordinate",
    )
  }
  for
    coordinate in [
      "user/module@0.0.0", "u/m/pkg@1.2.3-0.a-b+01.x-y", "u/m@999999999999999999999.0.0",
    ] {
    assert_true(valid_coordinate(coordinate), msg=coordinate)
  }
}
