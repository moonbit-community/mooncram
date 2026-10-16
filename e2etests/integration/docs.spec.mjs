import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import {
  ROOT,
  EXIT_CODE,
  createCli,
  createEnvironment,
  findTool,
  isolatedExecutable,
} from "./basic.mjs";

const DOCUMENT_NAMES = [
  "quickstart", "recipes", "troubleshooting",
  "invocation", "discovery", "markdown", "commands", "execution",
  "expectations", "reports", "updates", "errors", "summaries",
];

export function testDocs({ cli, executable, target, docs }) {
  assert(cli(["--help"]).stdout.includes("docs"));
  for (const args of [["docs"], ["docs", "--help"], ["docs", "-h"], ["help", "docs"]]) {
    const result = cli(args);
    assert(result.stdout.includes("Usage: mooncram docs"), result.stdout);
    assert(result.stdout.includes("--list"), result.stdout);
    for (const option of ["--target", "--timeout-ms", "--color"]) {
      assert(!result.stdout.includes(option), result.stdout);
    }
    assert.equal(result.stderr, "");
  }

  // Run outside a module, beside invalid Markdown, with no build/run tools on PATH.
  const standalone = createCli(
    isolatedExecutable(executable, target, target === "wasm" ? findTool("moonrun") : ""),
    docs,
  );
  const options = { env: { ...createEnvironment(), PATH: "" } };
  const invalidDocument = join(docs, "docs-command-invalid.md");
  const invalidContents = "```mooncram\nnot a command\n```\n";
  fs.writeFileSync(invalidDocument, invalidContents);
  try {
    const result = standalone(["docs", "--list"], options);
    assert.equal(result.stderr, "");
    assert(result.stdout.endsWith("\n"));
    const summaryColumn = Math.max(...DOCUMENT_NAMES.map(name => name.length)) + 2;
    const entries = result.stdout.trimEnd().split("\n").map(line => {
      const fields = /^(\S+)( {2,})(\S.*)$/.exec(line);
      assert(fields, line);
      assert.equal(fields[1].length + fields[2].length, summaryColumn, line);
      return fields[1];
    });
    assert.deepEqual(entries, DOCUMENT_NAMES);
    for (const name of entries) {
      const source = fs.readFileSync(join(ROOT, "internal/docs/mdfiles", `${name}.md`), "utf8")
        .replaceAll("\r\n", "\n");
      const shown = standalone(["docs", name], options);
      assert.equal(shown.stdout, source, name);
      assert.equal(shown.stderr, "", name);
    }
    assert.equal(
      standalone(["docs", "--", "invocation"], options).stdout,
      fs.readFileSync(join(ROOT, "internal/docs/mdfiles/invocation.md"), "utf8").replaceAll("\r\n", "\n"),
    );
    for (const name of ["README", "README_CN", "MissingDoc", "Invocation", "invocation.md", "../invocation", "implementation"]) {
      const unknown = standalone(["docs", name], { ...options, expected: EXIT_CODE.ERROR });
      assert.equal(unknown.stdout, "");
      assert(unknown.stderr.includes(`unknown document '${name}'`), unknown.stderr);
      assert(unknown.stderr.includes("mooncram docs --list"), unknown.stderr);
    }
    for (const args of [
      ["docs", "--list", "invocation"],
      ["docs", "invocation", "--list"],
      ["docs", "invocation", "discovery"],
      ["docs", "--unknown"],
      ["docs", "--dry-run"],
      ["docs", "--version"],
      ["docs", "--"],
      ["--target", "wasm", "docs", "--list"],
      ["docs", "invocation", "--target=native"],
      ["--timeout-ms", "60000", "docs", "invocation"],
      ["docs", "--list", "--timeout-ms=60000"],
      ["--color", "always", "docs", "--list"],
      ["docs", "invocation", "--color=never"],
      ["docs", "--list", "--color=invalid"],
    ]) {
      const invalid = standalone(args, { ...options, expected: EXIT_CODE.ERROR });
      assert.equal(invalid.stdout, "", JSON.stringify(args));
      assert(invalid.stderr.length > 0, JSON.stringify(args));
    }
    assert.equal(fs.readFileSync(invalidDocument, "utf8"), invalidContents);
  } finally {
    fs.rmSync(invalidDocument);
  }
}
