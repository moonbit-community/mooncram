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
import { delimiter, join } from "node:path";
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
  { command: `${LOCAL_PACKAGE} hello | ../project/bad`, diagnostic: "build failed" },
  { command: `${LOCAL_PACKAGE} hello | ./bad.mbtx`, diagnostic: "build failed" },
  { command: `${LOCAL_PACKAGE} hello | ./missing.mbtx` },
  { command: `${LOCAL_PACKAGE} hello | ${LOCAL_PACKAGE} invalid-utf8` },
  { command: `${LOCAL_PACKAGE} invalid-utf8 | ${LOCAL_PACKAGE} echo` },
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

function block(body) {
  return "```mooncram\n" + body + "```\n";
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
  // Moon may prune dependencies unused by this fixture module. A symlink here
  // would let fixture builds remove packages from the repository's cache.
  fs.cpSync(join(ROOT, ".mooncakes"), join(project, ".mooncakes"), { recursive: true });
  const packageDir = join(project, "cmd");
  writePackage(packageDir, PACKAGE_IMPORTS + MAIN_PACKAGE_CONFIG, PROGRAM);
  return packageDir;
}

function createDocuments(docs) {
  fs.mkdirSync(docs);
  fs.writeFileSync(join(docs, SCRIPT_FILENAME), SCRIPT_IMPORTS + PROGRAM);
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
    `$ ${program} context\nparent\nyes\ncwd contents\n\n` +
      `$ ${program} context\nparent\nyes\ncwd contents\n`,
  );
}

function streamCases(program) {
  return block(`$ ${program} streams\none\nthree\n[2]\n`);
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

function passingDocument() {
  return [
    block(`$ ${SCRIPT_COMMAND} hello\nHello, Moon Bit!\n`),
    ...[SCRIPT_COMMAND, LOCAL_PACKAGE].map(programCases),
    block(`$ ${LOCAL_PACKAGE} large\no* (glob)\n`),
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
  const legacy = writeDocument(
    docs,
    "legacy.md",
    '```mooncram {"target":"native"}\nnot a command\n```\n' +
      "```mooncram {\nnot a command\n```\n" +
      "```mooncram trailing text\nnot a command\n```\n",
  );
  assert(cli(["test", legacy], { expected: EXIT_CODE.ERROR }).stderr.includes("no mooncram cases"));
}

function testPassingCases({ cli, docs, target }) {
  const good = writeDocument(docs, "pass.md", passingDocument());
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
    block(`$ ${LOCAL_PACKAGE} setup\n\n$ ${LOCAL_PACKAGE} hello || cat\n`),
  );
  const before = fs.readFileSync(errorDoc);
  const result = cli(["update", errorDoc], { expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("error.md:4: empty pipeline segment"));
  assert.deepEqual(fs.readFileSync(errorDoc), before);
}

function testPipelines({ cli, docs, target }) {
  const commands = [
    [`${SCRIPT_COMMAND} hello|${LOCAL_PACKAGE} echo|${SCRIPT_COMMAND} echo`, "Hello, Moon Bit!\n"],
    [`${LOCAL_PACKAGE} context | ${SCRIPT_COMMAND} echo`, "parent\nyes\ncwd contents\n"],
    [`${LOCAL_PACKAGE} streams | ${LOCAL_PACKAGE} echo`, "one\nthree\n"],
    [`${LOCAL_PACKAGE} hello | ${LOCAL_PACKAGE} streams`, "one\nthree\n[2]\n"],
    [`${SCRIPT_COMMAND} raw | ${LOCAL_PACKAGE} echo | ${LOCAL_PACKAGE} check-raw`, "raw bytes preserved\n"],
    [`${LOCAL_PACKAGE} binary | ${SCRIPT_COMMAND} noisy-echo | ${LOCAL_PACKAGE} check-binary`, "all bytes preserved\n"],
    // The final segment exits without reading its input. Upstream status is ignored.
    [`${LOCAL_PACKAGE} binary | ${LOCAL_PACKAGE} hello`, "Hello, Moon Bit!\n"],
  ];
  const passing = writeDocument(docs, "pipeline.md",
    commands.map(([command, output]) => block(`$ ${command}\n${output}`)).join("\n"));
  cli(["test", passing, "--target", target]);

  const diagnostic = writeDocument(docs, "pipeline-diagnostic.md", block(
    `$ ${LOCAL_PACKAGE} streams | ${SCRIPT_COMMAND} relay middle | ${LOCAL_PACKAGE} relay last\nwrong\n`,
  ));
  const result = cli(["test", diagnostic, "--target", target], { expected: EXIT_CODE.FAILURE });
  assert(result.stdout.includes("diagnostic stderr\ntwo\nmiddle\nlast\n"));
  assert(result.stdout.includes("expected 0, actual 0"));

  const command = `$ ${SCRIPT_COMMAND} streams|${LOCAL_PACKAGE} echo`;
  const original = block(`${command}\nwrong\n`);
  const update = writeDocument(docs, "pipeline-update.md", original);
  const dryRun = cli(["update", update, "--target", target, "--dry-run"]);
  assert(dryRun.stdout.includes(command));
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), block(`${command}\none\nthree\n`));
  cli(["test", update, "--target", target]);
}

function testPipelinePreflight({ cli, docs, target }) {
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  for (const downstream of ["../project/bad", "./bad.mbtx", "./missing.mbtx"]) {
    const document = writeDocument(docs, "preflight.md", block(
      `$ ${LOCAL_PACKAGE} setup | ${downstream}\n`,
    ));
    cli(["test", document, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(!fs.existsSync(sideEffect), "upstream ran before all builds succeeded");
  }
}

function testPipelineStartupFailure({ cli, docs, directory, target }) {
  // Remove moonx from PATH while keeping the build tools. The first package
  // starts successfully, then starting the script must fail and cancel it.
  const toolDirectories = process.env.PATH.split(delimiter);
  const executableSuffix = process.platform === "win32" ? ".exe" : "";
  const tools = join(directory, "tools");
  fs.mkdirSync(tools);
  for (const name of ["moon", "moonc", "moonrun"]) {
    const filename = name + executableSuffix;
    const source = toolDirectories.map(path => join(path, filename)).find(path => fs.existsSync(path));
    assert(source, `missing ${name}`);
    fs.symlinkSync(source, join(tools, filename));
  }
  const env = createEnvironment();
  env.PATH = [tools, ...toolDirectories.filter(path => !fs.existsSync(join(path, "moonx" + executableSuffix)))].join(delimiter);
  const original = block(
    `$ ${LOCAL_PACKAGE} hello\nwrong\n\n` +
    `$ ${LOCAL_PACKAGE} slow slow-spawn.txt | ${SCRIPT_COMMAND} echo\n`,
  );
  const document = writeDocument(docs, "startup-error.md", original);
  const start = performance.now();
  const result = cli(["update", document, "--target", target], { env, expected: EXIT_CODE.ERROR });
  assert(performance.now() - start < CANCELLATION_LIMIT_MS);
  assert(result.stderr.includes("@process.spawn()"));
  assert(result.stderr.includes("startup-error.md:5:"));
  assert(result.stdout.includes("+Hello, Moon Bit!"));
  assert(result.stderr.includes("Not updating"));
  assert.equal(fs.readFileSync(document, "utf8"), original);
}

function testPipelineCaptureFailure({ cli, docs, target }) {
  const original = block(
    `$ ${LOCAL_PACKAGE} hello\nwrong\n\n` +
    `$ ${LOCAL_PACKAGE} slow slow-capture.txt | ${LOCAL_PACKAGE} invalid-stderr\n`,
  );
  const document = writeDocument(docs, "capture-error.md", original);
  const start = performance.now();
  const result = cli(["update", document, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(performance.now() - start < CANCELLATION_LIMIT_MS);
  assert(result.stderr.includes("Not updating"));
  assert.equal(fs.readFileSync(document, "utf8"), original);
}

function assertNoSlowSideEffect(docs) {
  assert(!fs.existsSync(join(docs, SLOW_SIDE_EFFECT_FILENAME)));
  for (const segment of ["first", "middle", "last", "spawn", "capture"]) {
    assert(!fs.existsSync(join(docs, `slow-${segment}.txt`)));
  }
}

function testTimeouts({ cli, docs }) {
  // A deadline covers the build and executable together. Both managed
  // native artifacts and moonrun processes must be cancelled promptly.
  for (const backend of TARGETS) {
    // Warm both package backends so these checks reach running processes rather
    // than timing out during a cold native build of the fixture's dependencies.
    const warm = writeDocument(docs, "warm.md", block(`$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n`));
    cli(["test", warm, "--target", backend]);
    const slow = writeDocument(docs, "slow.md", block(`$ ${LOCAL_PACKAGE} slow\n`));
    const start = performance.now();
    const result = cli([
      "test", slow, "--target", backend, "--timeout-ms", String(CASE_TIMEOUT_MS),
    ], { expected: EXIT_CODE.ERROR });
    assert(performance.now() - start < CANCELLATION_LIMIT_MS);
    assert(result.stderr.includes(`timed out after ${CASE_TIMEOUT_MS} ms`));
    for (const segment of ["first", "middle", "last"]) {
      fs.rmSync(join(docs, `slow-${segment}.txt.started`), { force: true });
    }
    const pipeline = writeDocument(docs, "slow-pipeline.md", block(
      `$ ${LOCAL_PACKAGE} slow slow-first.txt | ${LOCAL_PACKAGE} slow slow-middle.txt | ${LOCAL_PACKAGE} slow slow-last.txt\nwrong\n`,
    ));
    const original = fs.readFileSync(pipeline);
    const pipelineStart = performance.now();
    const cancelled = cli([
      "update", pipeline, "--target", backend, "--timeout-ms", "1500",
    ], { expected: EXIT_CODE.ERROR });
    assert(performance.now() - pipelineStart < CANCELLATION_LIMIT_MS);
    assert(cancelled.stderr.includes("timed out after 1500 ms"));
    assert.deepEqual(fs.readFileSync(pipeline), original);
    for (const segment of ["first", "middle", "last"]) {
      assert(fs.existsSync(join(docs, `slow-${segment}.txt.started`)),
        `${backend}: timeout must exercise a running ${segment} segment`);
    }
    // Even when the final segment has exited, upstream processes must be
    // awaited and cancelled when the shared deadline expires.
    const early = writeDocument(docs, "slow-upstream.md", block(
      `$ ${LOCAL_PACKAGE} slow slow-first.txt | ${LOCAL_PACKAGE} slow slow-middle.txt | ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n`,
    ));
    assert(cli([
      "test", early, "--target", backend, "--timeout-ms", "1500",
    ], { expected: EXIT_CODE.ERROR }).stderr.includes("timed out after 1500 ms"));
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

async function exercise(target) {
  const executable = buildExecutable(target);
  const directory = createTemporaryDirectory(target);
  try {
    const fixtures = createFixtures(directory);
    const context = { ...fixtures, target, cli: createCli(executable, fixtures.docs) };

    testCliArguments(context);
    testPassingCases(context);
    console.log(`${target}: scripts, packages, args, cwd, inherited env, stdin EOF, stdout and large dual-stream output passed`);

    testDiagnostics(context);
    testUpdates(context);
    console.log(`${target}: diagnostics, dry-run, local updates, escaping, pattern preservation passed`);

    testUpdateErrors(context);
    testPipelines(context);
    testPipelinePreflight(context);
    testPipelineStartupFailure(context);
    testPipelineCaptureFailure(context);
    console.log(`${target}: mixed pipelines, raw bytes, large output, early exit, stderr order, last status and updates passed`);
    testShellOperatorRejection(context);
    testTimeouts(context);
    const cancelledAt = performance.now();
    testConcurrentEdit(context);
    testDirectoryScanning(context);
    // Wait past the fixture's five-second delay to detect escaped processes.
    await new Promise(resolve => setTimeout(resolve, Math.max(0, 5500 - (performance.now() - cancelledAt))));
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

async function main() {
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
    await exercise(target);
  }
  console.log("All CLI integration checks passed.");
}

await main();
