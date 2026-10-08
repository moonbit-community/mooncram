#!/usr/bin/env node
/**
 * Exercise both CLI backends with real MoonBit scripts and packages.
 *
 * Run from any directory: node tests/integration.mjs [--target wasm|native]
 * Requires Node.js, moon, moonx, moonrun, and the native C toolchain.
 */

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const ROOT = fileURLToPath(new URL("../", import.meta.url));
const BUILD_DIRECTORY = join(ROOT, "_build");
const PROGRAM = fs.readFileSync(join(ROOT, "tests/fixtures/program.mbt"), "utf8");
const TARGETS = ["wasm", "native"];
const CLI_VERSION = "0.0.1";
const EXIT_CODE = { SUCCESS: 0, FAILURE: 1, ERROR: 2 };
const COMMAND_TIMEOUT_MS = 120_000;
const CASE_TIMEOUT_MS = 350;
const CANCELLATION_LIMIT_MS = 4000;
const ANSI_ESCAPE = "\x1b";
const CRLF = "\r\n";
const DIRECTORY_LINK_TYPE = process.platform === "win32" ? "junction" : "dir";
const CLEANUP_OPTIONS = { recursive: true, force: true, maxRetries: 3, retryDelay: 100 };
// Keep these dependency versions in sync with moon.mod.
const ASYNC_VERSION = "0.22.4";
const X_VERSION = "0.5.5";
const ASYNC_DEPENDENCY = `moonbitlang/async@${ASYNC_VERSION}`;
const X_DEPENDENCY = `moonbitlang/x@${X_VERSION}`;
const IMPORTS = [
  "moonbitlang/async",
  "moonbitlang/async/fs",
  "moonbitlang/async/stdio",
  "moonbitlang/core/env",
  "moonbitlang/x/sys",
];
const PACKAGE_IMPORTS = formatImports(IMPORTS);
const SCRIPT_IMPORTS = PACKAGE_IMPORTS
  .replaceAll("moonbitlang/async", ASYNC_DEPENDENCY)
  .replaceAll("moonbitlang/x/sys", `${X_DEPENDENCY}/sys`);
const MODULE_CONFIG = 'name = "mooncram/integration"\n' +
  `import { "${ASYNC_DEPENDENCY}", "${X_DEPENDENCY}" }\n`;
const MAIN_PACKAGE_CONFIG = 'options("is-main": true)\n';
const INVALID_PROGRAM = "fn main { nonexistent_function() }\n";
const LIBRARY_PROGRAM = "pub fn value() -> Int { 1 }\n";
const SCRIPT_FILENAME = "program with space.mbtx";
const SCRIPT_COMMAND = quoteArgument(`./${SCRIPT_FILENAME}`);
const LOCAL_PACKAGE = "../project/cmd";
const PATH_ARGUMENTS = [
  String.raw`C:\Moon Bit\file.txt`,
  String.raw`\\server\share\file.txt`,
  'a"b\\c',
];
const INVALID_CLI_ARGUMENTS = [
  ["test", "--timeout-ms", "0"],
  ["test", "--target", "js"],
  ["test", "--color", "invalid"],
  ["test", "--dry-run"],
  ["test", "missing.md"],
];
const UPDATE_ERROR_CASES = [
  { command: "../project/bad", diagnostic: "build failed" },
  { command: "./bad.mbtx", diagnostic: "build failed" },
  { command: "../project/library" },
  { command: "./missing.mbtx" },
  { command: `${quoteArgument(process.execPath)} hello` },
  { command: `${LOCAL_PACKAGE} invalid-utf8` },
];
const IGNORED_SCAN_DIRECTORIES = [".hidden", "_build", "target"];
const SLOW_SIDE_EFFECT_FILENAME = "slow-finished.txt";
const ARGUMENT_OPTIONS = {
  help: { type: "boolean", short: "h" },
  target: { type: "string", multiple: true },
};
const HELP_TEXT = `Usage: node tests/integration.mjs [--target wasm|native]

Exercise both CLI backends with real MoonBit scripts and packages.
Requires Node.js, moon, moonx, moonrun, and the native C toolchain.

Options:
  -h, --help            Show this help message and exit.
  --target wasm|native  Run one backend; repeat to select multiple (default: both).`;

function run(command, {
  cwd = ROOT,
  env = process.env,
  expected = EXIT_CODE.SUCCESS,
  timeout = COMMAND_TIMEOUT_MS,
} = {}) {
  const [program, ...args] = command.map(String);
  const result = spawnSync(program, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: ["inherit", "pipe", "pipe"],
    timeout,
    killSignal: "SIGKILL",
    maxBuffer: Infinity,
    windowsHide: true,
  });
  if (result.error) throw result.error;
  assert.equal(
    result.status,
    expected,
    `${JSON.stringify(command)}: expected exit ${expected}, got ${result.status}` +
      `\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
  return result;
}

function formatImports(imports) {
  return "import {\n" + imports.map(item => `  "${item}",\n`).join("") + "}\n";
}

function block(body, config = {}) {
  const info = Object.keys(config).length ? " " + JSON.stringify(config) : "";
  return "```mooncram" + info + "\n" + body + "```\n";
}

// Mooncram treats backslashes as escapes inside double-quoted arguments.
function quoteArgument(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function buildExecutable(target) {
  const artifact = JSON.parse(run([
    "moon", "run", "--build-only", "--target", target, ".",
  ]).stdout).artifacts_path[0];
  return target === "wasm" ? ["moonrun", artifact, "--"] : [artifact];
}

function createEnvironment() {
  return {
    ...process.env,
    MODE: "parent",
    MOONCRAM_INHERITED: "yes",
    // Keep standalone fixture builds local, including in read-only-home CI.
    MOON_DEP_CACHE: "off",
    MOON_BUILD_CACHE: "off",
  };
}

function createCli(executable, docs) {
  const env = createEnvironment();
  return (args, options = {}) => run([...executable, ...args], { cwd: docs, env, ...options });
}

function createTemporaryDirectory(target) {
  fs.mkdirSync(BUILD_DIRECTORY, { recursive: true });
  return fs.mkdtempSync(join(BUILD_DIRECTORY, `integration-${target}-`));
}

function writePackage(directory, config, source, filename = "main.mbt") {
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(join(directory, "moon.pkg"), config);
  fs.writeFileSync(join(directory, filename), source);
}

function createProject(project) {
  fs.mkdirSync(project, { recursive: true });
  fs.writeFileSync(join(project, "moon.mod"), MODULE_CONFIG);
  fs.symlinkSync(join(ROOT, ".mooncakes"), join(project, ".mooncakes"), DIRECTORY_LINK_TYPE);
  const packageDir = join(project, "cmd");
  writePackage(packageDir, PACKAGE_IMPORTS + MAIN_PACKAGE_CONFIG, PROGRAM);
  return packageDir;
}

function createDocuments(docs) {
  fs.mkdirSync(docs);
  fs.writeFileSync(join(docs, SCRIPT_FILENAME), SCRIPT_IMPORTS + PROGRAM);
  fs.writeFileSync(join(docs, "input.txt"), "stdin contents\n");
  fs.writeFileSync(join(docs, "relative.txt"), "cwd contents\n");
}

function createFixtures(directory) {
  const docs = join(directory, "docs");
  createDocuments(docs);
  const project = join(directory, "project");
  const packageDir = createProject(project);
  return { directory, docs, project, packageDir };
}

function writeDocument(directory, filename, content) {
  const path = join(directory, filename);
  fs.writeFileSync(path, content);
  return path;
}

function argumentCases(program) {
  return block(
    `$ ${program} args 'Moon Bit' "a'b" '' '$HOME' '*' '|' --version\n` +
      '["Moon Bit","a\'b","","$HOME","*","|","--version"] (equal)\n',
  ) + block(
    `$ ${program} args ${PATH_ARGUMENTS.map(quoteArgument).join(" ")}\n` +
      `${JSON.stringify(PATH_ARGUMENTS)} (equal)\n`,
  );
}

function contextCase(program) {
  return block(
    `$ ${program} context\ntest\nyes\ncwd contents\nstdin contents\n\n` +
      `$ ${program} context\ntest\nyes\ncwd contents\nstdin contents\n`,
    { stdin: "./input.txt", env: { MODE: "test" } },
  );
}

function streamCases(program) {
  return [
    block(`$ ${program} streams\none\nthree\n[2]\n`),
    block(`$ ${program} streams\ntwo\n[2]\n`, { stream: "stderr" }),
    block(`$ ${program} streams\none\ntwo\nthree\n[2]\n`, { stream: "merged" }),
  ].join("");
}

function programCases(program) {
  return [
    argumentCases(program),
    contextCase(program),
    block(`$ ${program} echo\n`),
    block(`$ ${program} setup\n\n$ ${program} read\nside effect preserved\n`),
    block(`$ ${program} crlf\none\ntwo\n`),
    streamCases(program),
  ].join("");
}

function passingDocument(target) {
  return [
    block(`$ ${SCRIPT_COMMAND} hello\nHello, Moon Bit!\n`),
    ...[SCRIPT_COMMAND, LOCAL_PACKAGE].map(programCases),
    block(`$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n`, {
      target: target === "native" ? "wasm" : "native",
    }),
    block(`$ ${LOCAL_PACKAGE} large\no* (glob)\n`),
    block(`$ ${LOCAL_PACKAGE} large\ne* (glob)\n`, { stream: "stderr" }),
  ].join("");
}

function quotedListItem(content) {
  return content.replace(/\n+$/, "").split("\n")
    .map((line, i) => (i === 0 ? "> - " : ">   ") + line).join("\n");
}

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

function createScanFixtures(directory, packageDir) {
  const scan = join(directory, "scan");
  fs.mkdirSync(scan);
  const invalid = block("invalid\n");
  for (const ignored of IGNORED_SCAN_DIRECTORIES) {
    const child = join(scan, ignored);
    fs.mkdirSync(child);
    writeDocument(child, "ignored.md", invalid);
  }
  writeDocument(scan, ".hidden.md", invalid);
  fs.symlinkSync(scan, join(scan, "cycle"), DIRECTORY_LINK_TYPE);
  writeDocument(scan, "a.md", block(`$ ${quoteArgument(packageDir)} setup\n`));
  writeDocument(scan, "z.md", block(`$ ${quoteArgument(packageDir)} read\nside effect preserved\n`));
  return scan;
}

function testCliArguments({ cli, docs }) {
  assert(cli(["--help"]).stdout.includes("Usage: mooncram"));
  assert(cli(["update", "--help"]).stdout.includes("dry-run"));
  assert(cli(["--version"]).stdout.includes(CLI_VERSION));
  for (const args of INVALID_CLI_ARGUMENTS) {
    cli(args, { expected: EXIT_CODE.ERROR });
  }
  const empty = writeDocument(docs, "empty.md", "No test blocks.\n");
  assert(cli(["test", empty], { expected: EXIT_CODE.ERROR }).stderr.includes("no mooncram cases"));
}

function testPassingCases({ cli, docs, target }) {
  const good = writeDocument(docs, "pass.md", passingDocument(target));
  const result = cli(["test", good, "--target", target, "--color", "never"]);
  assert(result.stdout.includes("0 failed, 0 errors"));
  assert(!result.stdout.includes(ANSI_ESCAPE));
}

function testDiagnostics({ cli, docs, target }) {
  const failed = writeDocument(docs, "failure.md", block(`$ ${LOCAL_PACKAGE} streams\nwrong\n`));
  const result = cli(["test", failed, "--target", target], { expected: EXIT_CODE.FAILURE });
  assert(result.stdout.includes("failure.md:2"));
  assert(result.stdout.includes("-wrong") && result.stdout.includes("+one"));
  assert(result.stdout.includes("expected 0, actual 2"));
  assert(result.stdout.includes("diagnostic stderr\ntwo"));
  assert(cli(["test", failed, "--color", "always"], { expected: EXIT_CODE.FAILURE }).stdout.includes(ANSI_ESCAPE));
}

function assertUpdatedDocument(updated) {
  const text = updated.toString("utf8");
  assert(text.startsWith("😀 Intro\r\n\r\n> - ```mooncram\r\n"));
  assert(updated.includes("Hello,* (glob)\r\n") && updated.includes("o* (glob)\r\n"));
  assert(updated.includes("(escaped)") && updated.includes("(no-eol)"));
  assert(text.endsWith("Unchanged tail"));
  assert(!text.replaceAll(CRLF, "").includes("\n"));
}

function testUpdates({ cli, docs, target }) {
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

function testUpdateErrors({ cli, docs, project, target }) {
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

function testShellOperatorRejection({ cli, docs }) {
  const errorDoc = writeDocument(
    docs,
    "error.md",
    block(`$ ${LOCAL_PACKAGE} hello\nwrong\n\n$ ${LOCAL_PACKAGE} hello | cat\n`),
  );
  const before = fs.readFileSync(errorDoc);
  assert(cli(["update", errorDoc], { expected: EXIT_CODE.ERROR }).stderr.includes("shell operator"));
  assert.deepEqual(fs.readFileSync(errorDoc), before);
}

function assertNoSlowSideEffect(docs) {
  assert(!fs.existsSync(join(docs, SLOW_SIDE_EFFECT_FILENAME)));
}

function testTimeouts({ cli, docs }) {
  // A deadline covers the build and executable together. Both managed
  // native artifacts and moonrun processes must be cancelled promptly.
  for (const backend of TARGETS) {
    const slow = writeDocument(docs, "slow.md", block(`$ ${LOCAL_PACKAGE} slow\n`, {
      target: backend,
      timeout_ms: CASE_TIMEOUT_MS,
    }));
    const start = performance.now();
    const result = cli(["test", slow], { expected: EXIT_CODE.ERROR });
    assert(performance.now() - start < CANCELLATION_LIMIT_MS);
    assert(result.stderr.includes(`timed out after ${CASE_TIMEOUT_MS} ms`));
  }
  assertNoSlowSideEffect(docs);
}

function testConcurrentEdit({ cli, docs, target }) {
  const mutate = writeDocument(docs, "mutate.md", block(`$ ${LOCAL_PACKAGE} mutate\nwrong\n`));
  const result = cli(["update", mutate, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("source changed"));
  assert.equal(fs.readFileSync(mutate, "utf8"), "changed by command\n");
}

function testDirectoryScanning({ cli, directory, packageDir, target }) {
  const scan = createScanFixtures(directory, packageDir);
  const explicit = cli(["test", scan, join(scan, "a.md"), "--target", target]);
  assert(explicit.stdout.includes("2 cases"));
  const implicit = cli(["test", "--target", target], { cwd: scan });
  assert(implicit.stdout.includes("2 cases"));
}

function exercise(target) {
  const executable = buildExecutable(target);
  const directory = createTemporaryDirectory(target);
  try {
    const fixtures = createFixtures(directory);
    const context = { ...fixtures, target, cli: createCli(executable, fixtures.docs) };

    testCliArguments(context);
    testPassingCases(context);
    console.log(`${target}: scripts, packages, args, cwd, env, stdin, streams, large output passed`);

    testDiagnostics(context);
    testUpdates(context);
    console.log(`${target}: diagnostics, dry-run, local updates, escaping, pattern preservation passed`);

    testUpdateErrors(context);
    testShellOperatorRejection(context);
    testTimeouts(context);
    testConcurrentEdit(context);
    testDirectoryScanning(context);
    // Other work gives cancelled processes time to reveal stray side effects.
    assertNoSlowSideEffect(fixtures.docs);
    console.log(`${target}: error isolation, timeout, concurrent edit, scan order and symlink checks passed`);
  } finally {
    fs.rmSync(directory, CLEANUP_OPTIONS);
  }
}

function parseOptions() {
  const { values } = parseArgs({ options: ARGUMENT_OPTIONS });
  for (const target of values.target ?? []) {
    if (!TARGETS.includes(target)) {
      throw new Error(`invalid target ${JSON.stringify(target)}: choose wasm or native`);
    }
  }
  return values;
}

function main() {
  let values;
  try {
    values = parseOptions();
  } catch (error) {
    console.error(`integration.mjs: ${error.message}`);
    process.exitCode = EXIT_CODE.ERROR;
    return;
  }
  if (values.help) {
    console.log(HELP_TEXT);
    return;
  }
  for (const target of values.target ?? TARGETS) {
    exercise(target);
  }
  console.log("All CLI integration checks passed.");
}

main();
