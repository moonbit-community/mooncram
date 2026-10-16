import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import { ROOT, EXIT_CODE, createCli } from "./basic.mjs";

function exampleBlock(source, language, fence = "```") {
  const pattern = new RegExp(`^${fence}${language}\n([\\s\\S]*?)^${fence}$`, "gm");
  const matches = [...source.matchAll(pattern)];
  assert.equal(matches.length, 1, `expected one complete ${language} example`);
  return matches[0][1];
}

function readExample(name) {
  const source = fs.readFileSync(join(ROOT, "internal/docs/mdfiles", `${name}.md`), "utf8")
    .replaceAll("\r\n", "\n");
  return {
    program: exampleBlock(source, "mbt"),
    document: exampleBlock(source, "markdown", "````"),
  };
}

export function testDocExamples({ executable, directory }) {
  // Materialize the actual published examples, with no repository module or
  // hidden fixture implementation. Both translations must supply the same files.
  const project = join(directory, "doc-examples");
  const tests = join(project, "tests");
  fs.mkdirSync(tests, { recursive: true });
  const cli = createCli(executable, project);
  for (const [topic, program, document, count] of [
    ["quickstart", "hello.mbtx", "hello.md", 1],
    ["recipes", "demo.mbtx", "recipes.md", 8],
  ]) {
    const example = readExample(topic);
    assert.deepEqual(readExample(`${topic}_CN`), example, `${topic} translations drifted`);
    fs.writeFileSync(join(tests, program), example.program);
    fs.writeFileSync(join(tests, document), example.document);
    const path = `tests/${document}`;
    const checked = cli(["check", path]);
    assert.equal(checked.stdout, `${count} cases, 0 errors\n`, topic);
    assert.equal(checked.stderr, "", topic);
    const tested = cli(["test", path]);
    assert.equal(tested.stdout, `${count} cases, 0 failed, 0 errors\n`, topic);
    assert.equal(tested.stderr, "", topic);
  }

  // Follow the documented intentional-change workflow and verify that a
  // successful dry-run does not imply passing assertions or a changed document.
  const script = join(tests, "hello.mbtx");
  const document = join(tests, "hello.md");
  const original = fs.readFileSync(document, "utf8");
  fs.writeFileSync(script, fs.readFileSync(script, "utf8")
    .replace("Hello, MoonBit!", "Hello, updated!"));
  const failed = cli(["test", "tests/hello.md", "--color", "never"], {
    expected: EXIT_CODE.FAILURE,
  });
  assert(failed.stdout.includes("FAIL "), failed.stdout);
  assert(failed.stdout.endsWith("1 cases, 1 failed, 0 errors\n"), failed.stdout);
  assert.equal(failed.stderr, "");

  const preview = cli(["update", "tests/hello.md", "--dry-run", "--color", "never"]);
  assert(preview.stdout.includes("FAIL "), preview.stdout);
  assert(preview.stdout.includes("+Hello, updated!"), preview.stdout);
  assert(preview.stdout.endsWith("1 cases, would update 1, 0 errors\n"), preview.stdout);
  assert.equal(preview.stderr, "");
  assert.equal(fs.readFileSync(document, "utf8"), original);

  const updated = cli(["update", "tests/hello.md", "--color", "never"]);
  assert(updated.stdout.endsWith("1 cases, updated 1, 0 errors\n"), updated.stdout);
  assert.equal(updated.stderr, "");
  assert.equal(fs.readFileSync(document, "utf8"), original
    .replace("Hello, MoonBit!", "Hello, updated!"));
  const passed = cli(["test", "tests/hello.md"]);
  assert.equal(passed.stdout, "1 cases, 0 failed, 0 errors\n");
  assert.equal(passed.stderr, "");
}
