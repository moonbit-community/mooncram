///|
test "passing exact expectations normalize to readable text" {
  let lines = [
    "[INFO] ready", "$HOME", "[literal]", "inline `code` and ``ticks``", "  leading",
    "   ", "", "after blank", "hello (foo)",
  ]
  let source = "``````mooncram\n$ moonx ./a.mbtx\n" +
    lines.map(s => "\{Json::string(s).stringify()} (escaped)\n").join("") +
    "[000]\n```````   "
  let output = lines.join("\n") + "\n"
  let actual : @output.Captured = { output, diagnostic: "", exit_code: 0, }
  assert_true(
    @markdown.parse_document("n.md", source).cases[0].expected.matches(actual),
  )
  assert_update(
    source,
    [actual],
    "```mooncram\n$ moonx ./a.mbtx\n" + output + "```   ",
  )
}

///|
test "only ambiguous exact syntax is escaped" {
  for
    (line, rendered) in [
      ("$", "\"$\" (escaped)"),
      ("$ moonx command", "\"$ moonx command\" (escaped)"),
      ("#cwd(.)", "\"#cwd(.)\" (escaped)"),
      ("#cwd()", "\"#cwd()\" (escaped)"),
      ("#cwd(unclosed", "\"#cwd(unclosed\" (escaped)"),
      ("#cwd(x) trailing", "\"#cwd(x) trailing\" (escaped)"),
      (" #cwd(.)", " #cwd(.)"),
      ("#cwd", "#cwd"),
      ("$HOME", "$HOME"),
      (" $ moonx command", " $ moonx command"),
      ("@STDOUT", "\"@STDOUT\" (escaped)"),
      ("@STDERR (unknown)", "\"@STDERR (unknown)\" (escaped)"),
      ("@STDOUTish", "@STDOUTish"),
      ("@stdout", "@stdout"),
      ("[+2]", "[+2]"),
      ("[]", "[]"),
      ("[-]", "[-]"),
      ("\u0000\t\r\u001b\u007f", "\"\\u0000\\t\\r\\u001b\\u007f\" (escaped)"),
    ] {
    assert_update(
      "```mooncram\n$ moonx ./a.mbtx\nold\n```\n",
      [{ output: line + "\n", diagnostic: "", exit_code: 0, }],
      "```mooncram\n$ moonx ./a.mbtx\n" + rendered + "\n```\n",
    )
  }
}

///|
test "only the last trailing blank needs protection where separators are trimmed" {
  for streams in [false, true] {
    for code in [0, 2] {
      for
        (output, body) in [
          ("", ""),
          ("\n", "\n"),
          ("\n\n\n", "\n\n\n"),
          ("a\n\nb\n\n\n", "a\n\nb\n\n\n"),
        ] {
        let prefix = "```mooncram\n$ moonx ./a.mbtx\n" +
          (if streams { "@STDERR (ignore)\n@STDOUT\n" } else { "" })
        let content = if output != "" && (streams || code == 0) {
          body[:body.length() - 1].to_owned() + "\"\" (escaped)\n"
        } else {
          body
        }
        assert_update(
          prefix + "old\n```\n",
          [{ output, diagnostic: "ignored\n", exit_code: code, }],
          prefix + content + (if code == 0 { "" } else { "[2]\n" }) + "```\n",
        )
      }
    }
  }
}

///|
test "numeric brackets are protected only in final case status position" {
  for
    (body, output, diagnostic, expected) in [
      ("old\n", "[2]\nend\n", "", "[2]\nend\n"),
      ("old\n", "[2]", "", "[2] (no-eol)\n"),
      (
        "@STDOUT\nold\n@STDERR (empty)\n", "[2]\n", "", "@STDOUT\n[2]\n@STDERR (empty)\n",
      ),
      (
        "@STDOUT (empty)\n@STDERR\nold\n\n", "", "[-0002]\n", "@STDOUT (empty)\n@STDERR\n\"[-0002]\" (escaped)\n\n",
      ),
    ] {
    assert_update(
      "```mooncram\n$ moonx ./a.mbtx\n" + body + "```\n",
      [{ output, diagnostic, exit_code: 0, }],
      "```mooncram\n$ moonx ./a.mbtx\n" + expected + "```\n",
    )
  }
  assert_update(
    "```mooncram\n$ moonx ./a.mbtx\n[0002]\n```\n",
    [{ output: "", diagnostic: "", exit_code: 2, }],
    "```mooncram\n$ moonx ./a.mbtx\n[2]\n```\n",
  )
}

///|
test "fences use shortest safe length including source indentation and no-eol" {
  for
    (opening, prefix, close) in [
      ("", "", ""),
      ("  ", "", "  "),
      ("  ", "  ", "  "),
      ("> - ", ">   ", ">   "),
      ("- >   ", "  > ", "  >   "),
      ("- outer\n  1. ", "     ", "     "),
    ] {
    let fence_indent = if opening == "  " || opening == "- >   " {
      2
    } else {
      0
    }
    let original_indent = if prefix == "  " { 2 } else { 0 }
    for spaces in 0..<5 {
      for ticks in 2..<7 {
        for suffix in ["", "  ", " tail", "`tail"] {
          for no_eol in [false, true] {
            let line = " ".repeat(spaces) + "`".repeat(ticks) + suffix
            let indent = if spaces > 0 { fence_indent } else { original_indent }
            let length = if !no_eol &&
              indent + spaces <= 3 &&
              ticks >= 3 &&
              (suffix == "" || suffix == "  ") {
              ticks + 1
            } else {
              3
            }
            let marker = "`".repeat(length)
            let source = opening +
              "````````mooncram\n" +
              prefix +
              "$ moonx ./a.mbtx\n" +
              prefix +
              "old\n" +
              close +
              "`````````"
            let extra = " ".repeat(indent - original_indent)
            assert_update(
              source,
              [
                {
                  output: line + (if no_eol { "" } else { "\n" }),
                  diagnostic: "",
                  exit_code: 0,
                },
              ],
              opening +
              marker +
              "mooncram\n" +
              prefix +
              "$ moonx ./a.mbtx\n" +
              prefix +
              extra +
              line +
              (if no_eol { " (no-eol)" } else { "" }) +
              "\n" +
              close +
              marker,
            )
          }
        }
      }
    }
  }
}

///|
test "whole document updates normalize every case fence and count each case once" {
  let source = "``````mooncram\n$ moonx ./a.mbtx\nold\n$ moonx ./b.mbtx\nkeep\n```````\n\n`````mooncram\n$ moonx ./c.mbtx\nkeep\n`````\n"
  let doc = @markdown.parse_document("shared.md", source)
  let a : @output.Captured = { output: "```\n", diagnostic: "", exit_code: 0, }
  let b : @output.Captured = { output: "keep\n", diagnostic: "", exit_code: 0, }
  let c : @output.Captured = { output: "keep\n", diagnostic: "", exit_code: 0, }
  let captures = [a, b, c]
  let result = @update.generate(doc, captures)
  assert_eq(result.changed_cases, 3)
  assert_eq(
    result.source,
    "````mooncram\n$ moonx ./a.mbtx\n```\n$ moonx ./b.mbtx\nkeep\n````\n\n```mooncram\n$ moonx ./c.mbtx\nkeep\n```\n",
  )
  let parsed = @markdown.parse_document("shared.md", result.source)
  let again = @update.generate(parsed, captures)
  assert_eq(again.source, result.source)
  assert_eq(again.changed_cases, 0)
}

///|
test "lookahead keeps shifted patterns and their own source layouts" {
  let prefix = "> ```mooncram\r\n>$ moonx ./a.mbtx\n"
  for
    (old, actual, rendered) in [
      (
        ">v* (glob)\r\n> [0-9]+ (regex)\n", "insert\nversion\n123\n", ">insert\n>v* (glob)\r\n> [0-9]+ (regex)\n",
      ),
      (
        ">obsolete\n>v* (glob)\r\n> [0-9]+ (regex)\n", "version\n123\n", ">v* (glob)\r\n> [0-9]+ (regex)\n",
      ),
      (
        ">v* (glob)\r\n> [0-9]+ (regex)\n", "version\ninsert\n123\n", ">v* (glob)\r\n>insert\n> [0-9]+ (regex)\n",
      ),
      (
        ">same\n>s* (glob)\r\n>same\n", "same\nsame\nsame\nsame\n", ">same\n>s* (glob)\r\n>same\n>same\n",
      ),
      (">v* (glob)\r\n>later\n", "later\nversion\n", ">later\n>version\n"),
    ] {
    assert_update(
      prefix + old + "> ```",
      [{ output: actual, diagnostic: "", exit_code: 0, }],
      prefix + rendered + "> ```",
    )
  }
}

///|
test "dual streams normalize independently and retain ignored and empty constraints" {
  let source = "```mooncram\n$ moonx ./a.mbtx\n\n@STDERR\nold\nerror [0-9]+ (regex)\n\n@STDOUT\nv* (glob)\n\"[INFO] ready\" (escaped)\n[00]\n```\n"
  assert_update(
    source,
    [
      {
        output: "insert\nversion\n[INFO] ready\n",
        diagnostic: "error 2",
        exit_code: 0,
      },
    ],
    "```mooncram\n$ moonx ./a.mbtx\n\n@STDERR\nerror [0-9]+ (regex) (no-eol)\n\n@STDOUT\ninsert\nv* (glob)\n[INFO] ready\n```\n",
  )
  assert_update(
    "````mooncram\n$ moonx ./a.mbtx\n@STDERR (ignore)\n@STDOUT (empty)\n[0]\n````\n",
    [{ output: "", diagnostic: "anything", exit_code: 0, }],
    "```mooncram\n$ moonx ./a.mbtx\n@STDERR (ignore)\n@STDOUT (empty)\n```\n",
  )
}

///|
test "leading spaces round trip across nested containers and tab prefixes" {
  for
    (opening, prefix, closing) in [
      ("  ", "", "  "),
      (">   ", ">", ">   "),
      ("> - item\n>     ", ">   ", ">     "),
      ("- outer\n  > 1. inner\n  >      ", "  >    ", "  >      "),
      ("-   ", "\t", "    "),
      (">   ", ">\t", ">   "),
      ("- >   ", "  >\t", "  >   "),
      ("[^note]:\n\n  ", " ", "  "),
    ] {
    for
      output in [
        " \n", "  leading\n   \nnext\n", "    ````\n", "  $ moonx command\n", "   \n\n\n",
      ] {
      let source = opening +
        "``````mooncram\r\n" +
        prefix +
        "$ moonx ./a.mbtx\n" +
        prefix +
        "old\r\n" +
        closing +
        "``````\n"
      let doc = @markdown.parse_document("nested.md", source) catch {
        e => fail("parse \{source}: \{e}")
      }
      let actual : @output.Captured = { output, diagnostic: "", exit_code: 0, }
      let generated = @update.generate(doc, [actual]) catch {
        e => fail("generate \{source}, output \{output}: \{e}")
      }
      let parsed = @markdown.parse_document("nested.md", generated.source)
      assert_true(
        parsed.cases[0].expected.matches(actual),
        msg=generated.source,
      )
      assert_eq(@update.generate(parsed, [actual]).source, generated.source)
      if output != "   \n\n\n" {
        assert_true(
          !generated.source.contains("(escaped)"),
          msg=generated.source,
        )
      }
    }
  }
}

///|
test "partially consumed tabs keep unchanged rows and do not duplicate virtual spaces" {
  let source = "- ```mooncram\n  $ moonx ./a.mbtx\n\told\r\n  ```"
  for
    (output, row) in [
      ("  old\n", "\told"),
      ("  new\n", "    new"),
      ("new\n", "  new"),
      ("    \n", "      "),
    ] {
    assert_update(
      source,
      [{ output, diagnostic: "", exit_code: 0, }],
      "- ```mooncram\n  $ moonx ./a.mbtx\n" + row + "\r\n  ```",
    )
  }
}

///|
test "a shared fence considers every capture in document order" {
  let source = "````````mooncram\n$ moonx ./a.mbtx\nold\n\n$ moonx ./b.mbtx\nold\n````````\n"
  let a : @output.Captured = { output: "```\n", diagnostic: "", exit_code: 0, }
  let b : @output.Captured = {
    output: "`````\n",
    diagnostic: "",
    exit_code: 0,
  }
  let doc = @markdown.parse_document("shared.md", source)
  let generated = @update.generate(doc, [a, b])
  assert_eq(generated.changed_cases, 2)
  assert_eq(
    generated.source,
    "``````mooncram\n$ moonx ./a.mbtx\n```\n\n$ moonx ./b.mbtx\n`````\n``````\n",
  )
  let parsed = @markdown.parse_document("shared.md", generated.source)
  assert_eq(@update.generate(parsed, [a, b]).changed_cases, 0)
}

///|
test "a tab before backticks cannot close the fence even when partially consumed" {
  for
    (opening, command_prefix, output_prefix, closing) in [
      ("- ", "  ", "\t", "  "),
      (">   ", "> ", ">\t", ">   "),
    ] {
    let source = opening +
      "``````mooncram\n" +
      command_prefix +
      "$ moonx ./a.mbtx\n" +
      output_prefix +
      "````\n" +
      closing +
      "``````\n"
    let output = if opening == "- " { "  ````\n" } else { "````\n" }
    assert_update(
      source,
      [{ output, diagnostic: "", exit_code: 0, }],
      source.replace_all(old="``````", new="```"),
    )
  }
}

///|
test "internal bare LF after CR is protected without changing either newline" {
  for
    (source, wanted) in [
      (
        "```mooncram\n$ moonx ./a.mbtx\rold\nend\r```", "```mooncram\n$ moonx ./a.mbtx\r\"\" (escaped)\nend\r```",
      ),
      (
        "```mooncram\n$ moonx ./a.mbtx\n@STDERR (ignore)\n@STDOUT\rold\nend\r```",
        "```mooncram\n$ moonx ./a.mbtx\n@STDERR (ignore)\n@STDOUT\r\"\" (escaped)\nend\r```",
      ),
    ] {
    assert_update(
      source,
      [{ output: "\nend\n", diagnostic: "", exit_code: 0, }],
      wanted,
    )
  }
  // An inserted blank can also follow an aligned row with a different newline.
  assert_update(
    "```mooncram\n$ moonx ./a.mbtx\nhead\rend\n```",
    [{ output: "head\n\nend\n", diagnostic: "", exit_code: 0, }],
    "```mooncram\n$ moonx ./a.mbtx\nhead\r\"\" (escaped)\nend\n```",
  )
}
