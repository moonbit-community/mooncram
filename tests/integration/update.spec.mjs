import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import {
  EXIT_CODE,
  CRLF,
  MAIN_PACKAGE_CONFIG,
  INVALID_PROGRAM,
  LIBRARY_PROGRAM,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  block,
  quoteArgument,
  writePackage,
  writeDocument,
  quotedListItem,
} from "./basic.mjs";

const UPDATE_ERROR_CASES = [
  { command: "bad", diagnostic: "build failed" },
  { command: `bad 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo`, diagnostic: "build failed" },
  { command: `./bad.mbtx 2>&1 1>/dev/null | ${LOCAL_PACKAGE} echo`, diagnostic: "build failed" },
  { command: "./bad.mbtx", diagnostic: "build failed" },
  { command: "library" },
  { command: "./missing.mbtx" },
  { command: `${quoteArgument(process.execPath)} hello` },
  { command: `${LOCAL_PACKAGE} invalid-utf8` },
  { command: `${LOCAL_PACKAGE} invalid-stderr 2>&1 | ${LOCAL_PACKAGE} echo` },
  { command: `${LOCAL_PACKAGE} invalid-stderr 1>/dev/null | ${LOCAL_PACKAGE} echo` },
  { command: `${LOCAL_PACKAGE} invalid-stderr 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo` },
  { command: `${LOCAL_PACKAGE} hello | bad`, diagnostic: "build failed" },
  { command: `${LOCAL_PACKAGE} hello | ./bad.mbtx`, diagnostic: "build failed" },
  { command: `${LOCAL_PACKAGE} hello | ./missing.mbtx` },
  { command: `${LOCAL_PACKAGE} hello | ${LOCAL_PACKAGE} invalid-utf8` },
  { command: `${LOCAL_PACKAGE} invalid-utf8 | ${LOCAL_PACKAGE} echo` },
];

function updateDocument() {
  const nested = block(`$ ${SCRIPT_COMMAND} special\nold\n\n$ ${SCRIPT_COMMAND} hello\nHello,* (glob)\n`);
  const source = "😀 Intro\n\n" + quotedListItem(nested) + "\n\n" +
    block(`$ ${LOCAL_PACKAGE} crlf\no* (glob)\nwrong\n`) + "Unchanged tail";
  return Buffer.from(source.replaceAll("\n", CRLF));
}

function createErrorFixtures(project, docs) {
  writePackage(join(project, "bad"), MAIN_PACKAGE_CONFIG, INVALID_PROGRAM);
  fs.writeFileSync(join(docs, "bad.mbtx"), INVALID_PROGRAM);
  writePackage(join(project, "library"), "", LIBRARY_PROGRAM, "lib.mbt");
}

function assertUpdatedDocument(updated) {
  const text = updated.toString("utf8");
  assert(text.startsWith("😀 Intro\r\n\r\n> - ````mooncram mooncram/integration\r\n"));
  assert(updated.includes("Hello,* (glob)\r\n") && updated.includes("o* (glob)\r\n"));
  assert(updated.includes("(escaped)") && updated.includes("(no-eol)"));
  assert(text.endsWith("Unchanged tail"));
  assert(!text.replaceAll(CRLF, "").includes("\n"));
}

function testUpdateRoundTrips({ cli, docs, target }) {
  const blank = quotedListItem(block(
    `$ ${LOCAL_PACKAGE} read-file update-blank.txt\n\nlast\n`,
  )).replace(">   \n", ">\n") + "\n";
  const status = block(`$ ${LOCAL_PACKAGE} read-file update-status.txt\n[2] (no-eol)\n`);
  const mixed = block(`$ ${LOCAL_PACKAGE} read-file update-mixed.txt\nold\nlast\n`)
    .replace("update-mixed.txt\n", "update-mixed.txt\r");
  for (const { name, output, original, wanted } of [
    {
      name: "update-blank",
      output: "new\nlast\n",
      original: blank,
      wanted: blank.replace("\n>\n", "\n>   new\n"),
    },
    {
      name: "update-status",
      output: "[2]\n",
      original: status,
      wanted: status.replace("[2] (no-eol)", '"[2]" (escaped)'),
    },
    {
      name: "update-mixed",
      output: "\nlast\n",
      original: mixed,
      wanted: mixed.replace("old\n", '"" (escaped)\n'),
    },
  ]) {
    fs.writeFileSync(join(docs, `${name}.txt`), output);
    const document = writeDocument(docs, `${name}.md`, original);
    const dryRun = cli(["update", document, "--dry-run", "--target", target]);
    assert(dryRun.stdout.includes("would update 1"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
    cli(["update", document, "--target", target]);
    assert.equal(fs.readFileSync(document, "utf8"), wanted);
    cli(["check", document]);
    cli(["test", document, "--target", target]);
    cli(["update", document, "--target", target]);
    assert.equal(fs.readFileSync(document, "utf8"), wanted);
  }
}

export function testUpdates({ cli, docs, target }) {
  const original = updateDocument();
  const update = writeDocument(docs, "update.md", original);
  const result = cli(["update", update, "--dry-run", "--target", target]);
  assert(result.stdout.includes("would update 3") && result.stdout.includes("(updated)"));
  assert.deepEqual(fs.readFileSync(update), original);
  cli(["update", update, "--target", target]);
  const updated = fs.readFileSync(update);
  assertUpdatedDocument(updated);
  cli(["test", update, "--target", target]);
  cli(["update", update, "--target", target]);
  assert.deepEqual(fs.readFileSync(update), updated);
  testUpdateRoundTrips({ cli, docs, target });
  testPassingNormalization({ cli, docs, target });
  assert(!fs.readdirSync(docs).some(name => name.startsWith(".mooncram-")));
}

function testPassingNormalization({ cli, docs, target }) {
  const lines = ["[INFO] ready", "$HOME", "inline `code`", "  leading", "", "```", "last"];
  fs.writeFileSync(join(docs, "normalize.txt"), lines.join("\n") + "\n");
  const commands = [
    `$ ${LOCAL_PACKAGE} read-file normalize.txt`,
    `$ ${LOCAL_PACKAGE} hello`,
  ];
  const original = "````````mooncram mooncram/integration\r\n" +
    commands[0] + "\r\n" +
    lines.map(line => JSON.stringify(line) + " (escaped)\r\n").join("") +
    "[000]\r\n\r\n" + commands[1] + "\r\nHello,* (glob)\r\n`````````";
  const wanted = "````mooncram mooncram/integration\r\n" + commands[0] + "\r\n" +
    lines.join("\r\n") + "\r\n\r\n" + commands[1] + "\r\nHello,* (glob)\r\n````";
  const document = writeDocument(docs, "normalize.md", original);
  cli(["test", document, "--target", target]);
  const dry = cli(["update", document, "--dry-run", "--target", target]);
  assert(dry.stdout.includes("2 cases, would update 2, 0 errors"), dry.stdout);
  assert(dry.stdout.includes("(updated)"));
  assert(!dry.stdout.includes("FAIL"));
  assert.equal(fs.readFileSync(document, "utf8"), original);
  const update = cli(["update", document, "--target", target]);
  assert(update.stdout.includes("2 cases, updated 2, 0 errors"), update.stdout);
  assert.equal(fs.readFileSync(document, "utf8"), wanted);
  cli(["test", document, "--target", target]);
  const modified = fs.statSync(document, { bigint: true }).mtimeNs;
  const again = cli(["update", document, "--target", target]);
  assert(again.stdout.includes("updated 0"), again.stdout);
  assert.equal(fs.readFileSync(document, "utf8"), wanted);
  assert.equal(fs.statSync(document, { bigint: true }).mtimeNs, modified);
}

export function testUpdateErrors({ cli, docs, project, target }) {
  createErrorFixtures(project, docs);
  for (const { command, diagnostic } of UPDATE_ERROR_CASES) {
    const original = block(`$ ${LOCAL_PACKAGE} hello\nwrong\n\n$ ${command}\n`);
    const errorDoc = writeDocument(docs, "error.md", original);
    const result = cli(["update", errorDoc, "--target", target], { expected: EXIT_CODE.ERROR });
    assert.equal(fs.readFileSync(errorDoc, "utf8"), original);
    assert(result.stderr.includes("Not updating"));
    if (diagnostic) {
      assert(result.stderr.includes(diagnostic));
    }
  }
  for (const dry of [[], ["--dry-run"]]) {
    for (const badCase of ["$ ./missing.mbtx\n", "@STDOUT\n"]) {
      const original = block(`$ ${LOCAL_PACKAGE} hello\n"Hello, Moon Bit!" (escaped)\n[0]\n\n${badCase}`);
      const document = writeDocument(docs, "normalize-error.md", original);
      const result = cli(["update", document, "--target", target, ...dry], { expected: EXIT_CODE.ERROR });
      assert.equal(fs.readFileSync(document, "utf8"), original);
      assert(result.stdout.includes(dry.length ? "would update 0" : "updated 0"), result.stdout);
      assert(!result.stdout.includes("(updated)"));
      assert(!result.stdout.includes("FAIL"));
    }
  }
}

export function testConcurrentEdit({ cli, docs, target }) {
  const mutate = writeDocument(docs, "mutate.md", block(`$ ${LOCAL_PACKAGE} mutate\nwrong\n`));
  const result = cli(["update", mutate, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("source changed"));
  assert.equal(fs.readFileSync(mutate, "utf8"), "changed by command\n");
}
