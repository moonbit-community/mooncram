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
  assert(text.startsWith("😀 Intro\r\n\r\n> - ```mooncram mooncram/integration\r\n"));
  assert(updated.includes("Hello,* (glob)\r\n") && updated.includes("o* (glob)\r\n"));
  assert(updated.includes("(escaped)") && updated.includes("(no-eol)"));
  assert(text.endsWith("Unchanged tail"));
  assert(!text.replaceAll(CRLF, "").includes("\n"));
}

export function testUpdates({ cli, docs, target }) {
  const original = updateDocument();
  const update = writeDocument(docs, "update.md", original);
  const result = cli(["update", update, "--dry-run", "--target", target]);
  assert(result.stdout.includes("would update 2") && result.stdout.includes("(updated)"));
  assert.deepEqual(fs.readFileSync(update), original);
  cli(["update", update, "--target", target]);
  const updated = fs.readFileSync(update);
  assertUpdatedDocument(updated);
  cli(["test", update, "--target", target]);
  cli(["update", update, "--target", target]);
  assert.deepEqual(fs.readFileSync(update), updated);
  assert(!fs.readdirSync(docs).some(name => name.startsWith(".mooncram-")));
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
}

export function testConcurrentEdit({ cli, docs, target }) {
  const mutate = writeDocument(docs, "mutate.md", block(`$ ${LOCAL_PACKAGE} mutate\nwrong\n`));
  const result = cli(["update", mutate, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("source changed"));
  assert.equal(fs.readFileSync(mutate, "utf8"), "changed by command\n");
}
