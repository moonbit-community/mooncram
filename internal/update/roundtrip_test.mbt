///|
fn assert_container_blank_updates(streams : Bool) -> Unit raise {
  for
    (opening, prefix, blank) in [
      ("- ", "  ", ""),
      ("- ", "  ", " "),
      ("1. ", "   ", ""),
      ("1. ", "   ", "  "),
      ("> - ", ">   ", ">"),
      ("> - ", ">   ", "> "),
    ] {
    let separator = if opening.has_prefix(">") { ">" } else { "" }
    for
      (newline, blank_newline) in [
        ("\n", "\n"),
        ("\r\n", "\r\n"),
        ("\n", "\r\n"),
        ("\r\n", "\n"),
      ] {
      let before = "Intro" +
        newline +
        newline +
        opening +
        "```mooncram" +
        newline +
        prefix +
        "$ ./a.mbtx" +
        newline +
        (if streams {
          separator + blank_newline + prefix + "@STDOUT" + newline
        } else {
          ""
        })
      let after = (if streams {
          separator +
          blank_newline +
          prefix +
          "@STDERR" +
          blank_newline +
          prefix +
          "err [0-9]+ (regex)" +
          newline
        } else {
          ""
        }) +
        separator +
        blank_newline +
        prefix +
        "$ ./b.mbtx" +
        newline +
        prefix +
        "untouched" +
        newline +
        prefix +
        "```" +
        newline +
        "Tail"
      let retained = prefix + "keep * (glob)" + newline
      let source = before + blank + blank_newline + retained + after
      for (output, rendered) in [("new", "new"), ("", "\"\" (escaped)")] {
        assert_update(
          source,
          {
            output: output + "\nkeep me\nextra\n",
            diagnostic: "err 42\n",
            exit_code: 0,
          },
          before +
          prefix +
          rendered +
          blank_newline +
          retained +
          prefix +
          "extra" +
          newline +
          after,
        )
      }
    }
  }
}

///|
test "legacy updates fill underindented container blanks and preserve newlines" {
  assert_container_blank_updates(false)
}

///|
test "stream updates fill underindented blanks and preserve unchanged sections" {
  assert_container_blank_updates(true)
}

///|
test "unchanged stream whitespace keeps its original container layout" {
  let source = "- ```mooncram\n  $ ./a.mbtx\n  @STDOUT\n  old\n\n  @STDERR\n \n  keep\n  ```\n"
  assert_update(
    source,
    { output: "new\n", diagnostic: " \nkeep\n", exit_code: 0, },
    source.replace(old="old", new="new"),
  )
}

///|
test "retained status-looking output gains a newline without becoming exit status" {
  for streams in [false, true] {
    for line in ["[2]", "[-2]", "[2147483648]", "[-2147483649]", "[literal]"] {
      let before = "```mooncram\n$ ./a.mbtx\n" +
        (if streams { "@STDERR (empty)\n\n@STDOUT\n" } else { "" })
      let source = before + line + " (no-eol)\n[7]\n```\n"
      for exit_code in [0, 7, 3] {
        let status = if exit_code == 0 { "" } else { "[\{exit_code}]\n" }
        assert_update(
          source,
          { output: line + "\n", diagnostic: "", exit_code, },
          before + "\"" + line + "\" (escaped)\n" + status + "```\n",
        )
      }
    }
  }
}

///|
test "matching annotations survive changes to the final output newline" {
  for streams in [false, true] {
    for
      (raw, output) in [
        ("version * (glob)", "version 9"),
        ("[0-9]+ (regex)", "123"),
        ("\"[2]\" (escaped)", "[2]"),
      ] {
      let before = "```mooncram\n$ ./a.mbtx\n" +
        (if streams { "@STDERR (empty)\n@STDOUT\n" } else { "" })
      for no_eol in [false, true] {
        let old_suffix = if no_eol { "" } else { " (no-eol)" }
        let new_suffix = if no_eol { " (no-eol)" } else { "" }
        assert_update(
          before + raw + old_suffix + "\n```\n",
          {
            output: output + (if no_eol { "" } else { "\n" }),
            diagnostic: "",
            exit_code: 0,
          },
          before + raw + new_suffix + "\n```\n",
        )
      }
    }
  }
}
