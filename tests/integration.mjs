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
const LOCAL_PACKAGE = "cmd";
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
  { command: "bad", diagnostic: "build failed" },
  { command: "bad >/dev/null 2>&1", diagnostic: "build failed" },
  { command: "./bad.mbtx 2>&1 >/dev/null", diagnostic: "build failed" },
  { command: "./bad.mbtx", diagnostic: "build failed" },
  { command: "library" },
  { command: "./missing.mbtx" },
  { command: `${quoteArgument(process.execPath)} hello` },
  { command: `${LOCAL_PACKAGE} invalid-utf8` },
  { command: `${LOCAL_PACKAGE} invalid-stderr 2>&1` },
  { command: `${LOCAL_PACKAGE} invalid-stderr >/dev/null` },
  { command: `${LOCAL_PACKAGE} invalid-stderr >/dev/null 2>&1` },
  { command: `${LOCAL_PACKAGE} hello | bad`, diagnostic: "build failed" },
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

function block(body, module = "mooncram/integration") {
  return "```mooncram" + (module ? ` ${module}` : "") + "\n" + body + "```\n";
}

// Mooncram treats backslashes as escapes inside double-quoted arguments.
function quoteArgument(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("$", "\\$")}"`;
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

function createCli(executable, project) {
  const env = createEnvironment();
  return (args, options = {}) => run([...executable, ...args], { cwd: project, env, ...options });
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

function createScanFixtures(directory) {
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
  writeDocument(scan, "a.md", block(`$ ${LOCAL_PACKAGE} setup\n`));
  writeDocument(scan, "z.md", block(`$ ${LOCAL_PACKAGE} read\nside effect preserved\n`));
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
  assert(cli(["test", legacy], { expected: EXIT_CODE.ERROR }).stderr.includes("legacy.md:1: invalid mooncram module declaration"));
}

function testModuleResolution({ cli, docs, directory, target }) {
  const moduleRoot = join(directory, "module-resolution");
  fs.mkdirSync(moduleRoot);
  const configPath = join(moduleRoot, "moon.mod");
  const sourceRoot = join(moduleRoot, "src");
  const declaration = "user/foo";
  const invoke = (body, options = {}) => {
    const doc = writeDocument(docs, "module-resolution.md", block(body, declaration));
    return cli(["test", doc, "--target", target], { cwd: moduleRoot, ...options });
  };
  const executable = 'pkgtype(kind: "executable")\n';
  const print = text => `fn main { println(${JSON.stringify(text)}) }\n`;
  fs.writeFileSync(configPath, 'name = "user/foo"\nsource = "src"\n');
  // A module fence also accepts scripts resolved from the document directory.
  invoke(`$ ${SCRIPT_COMMAND} hello\nHello, Moon Bit!\n`);
  const sub = join(sourceRoot, "foo");
  writePackage(sourceRoot, executable, print("root"));
  writePackage(sub, 'options("is-main": true)\n', print("child"));
  writePackage(join(sourceRoot, "cmd", "deep", "boo"), executable, print("deep"));
  invoke("$ cmd/deep/boo\ndeep\n");
  let result = invoke("$ foo | foo\nroot\n");
  assert.equal(result.stderr.split("WARNING ").length - 1, 2);
  assert(result.stderr.includes("module-resolution.md:2:"));
  assert(result.stderr.includes("user/foo and user/foo/foo; selected user/foo"));
  assert(result.stdout.includes("1 cases, 0 failed, 0 errors"));

  const update = writeDocument(docs, "module-warning-update.md", block("$ foo\nwrong\n", declaration));
  result = cli(["update", update, "--target", target], { cwd: moduleRoot });
  assert.equal(result.stderr.split("WARNING ").length - 1, 1);
  assert.equal(fs.readFileSync(update, "utf8"), block("$ foo\nroot\n", declaration));

  // Root executable takes precedence even when its build or target fails.
  fs.writeFileSync(join(sourceRoot, "main.mbt"), INVALID_PROGRAM);
  assert(invoke("$ foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("build failed"));
  fs.writeFileSync(join(sourceRoot, "main.mbt"), print("root"));
  fs.writeFileSync(join(sourceRoot, "moon.pkg"), executable + 'supported_targets = "js"\n');
  assert(invoke("$ foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("build failed"));
  writePackage(sourceRoot, 'pkgtype(kind: "library")\n', LIBRARY_PROGRAM);
  assert.equal(invoke("$ foo\nchild\n").stderr, "");
  fs.unlinkSync(join(sub, "moon.pkg"));
  fs.writeFileSync(join(sub, "moon.pkg.json"), '{"is-main":true}\n');
  invoke("$ foo\nchild\n");
  fs.writeFileSync(join(sub, "moon.pkg.json"), '{}\n');
  assert(invoke("$ foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("no executable package"));
  fs.writeFileSync(join(sub, "moon.pkg.json"), '{"is-main":true}\n');
  fs.writeFileSync(join(sub, "moon.pkg"), 'pkgtype(kind: true)\n');
  assert(invoke("$ foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("invalid configuration"));
  fs.unlinkSync(join(sub, "moon.pkg"));

  for (const name of [quoteArgument(sub), "./foo", "../foo", "cmd/../foo"]) {
    assert(invoke(`$ ${name}\n`, { expected: EXIT_CODE.ERROR }).stderr.includes("invalid module package name"));
  }
  const nested = join(sourceRoot, "nested");
  writePackage(join(nested, "cmd"), executable, print("nested"));
  fs.writeFileSync(join(nested, "moon.mod"), 'name = "user/nested"\n');
  assert(invoke("$ nested/cmd\n", { expected: EXIT_CODE.ERROR }).stderr.includes("nested modules"));

  // Validate the whole document before the first command, even export-only declarations.
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  const invalid = writeDocument(docs, "module-invalid.md",
    block(`$ ${SCRIPT_COMMAND} setup\n`, "") + block("$ export A=x\n", "user/other"));
  const before = fs.readFileSync(invalid);
  result = cli(["update", invalid, "--target", target], { cwd: moduleRoot, expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("module-invalid.md:4: module declaration 'user/other' does not match 'user/foo'"));
  assert(!fs.existsSync(sideEffect));
  assert.deepEqual(fs.readFileSync(invalid), before);
  const declared = writeDocument(docs, "module-missing.md", block("$ export A=x\n", declaration));
  for (const cwd of [docs, sourceRoot]) {
    assert(cli(["test", declared], { cwd, expected: EXIT_CODE.ERROR }).stderr.includes("requires moon.mod in startup cwd"));
  }
  fs.writeFileSync(configPath, 'name =');
  assert(cli(["test", declared], { cwd: moduleRoot, expected: EXIT_CODE.ERROR }).stderr.includes("invalid configuration"));

  // Without a declaration only scripts are accepted, including mixed fences.
  const scoped = writeDocument(docs, "module-scope.md",
    block(`$ ${SCRIPT_COMMAND} hello\nHello, Moon Bit!\n`, "") +
    block(`$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n`) + block(`$ ${LOCAL_PACKAGE} hello\n`, ""));
  result = cli(["test", scoped, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(result.stdout.includes("3 cases, 0 failed, 1 errors"));
  assert(result.stderr.includes("module-scope.md:10:"));
  const oldPath = writeDocument(docs, "module-old-path.md", block(`$ ${quoteArgument(sub)}\n`, ""));
  assert(cli(["test", oldPath], { expected: EXIT_CODE.ERROR }).stderr.includes("command requires a .mbtx file"));
}

function testPassingCases({ cli, docs, target }) {
  const good = writeDocument(docs, "pass.md", passingDocument());
  const result = cli(["test", good, "--target", target, "--color", "never"]);
  assert(result.stdout.includes("0 failed, 0 errors"));
  assert(!result.stdout.includes(ANSI_ESCAPE));
}

function testExports({ cli, docs, target }) {
  const value = 'Moon Bit|\'"=value';
  const args = '${MODE} ${VALUE} ${EMPTY} pre${VALUE}post ${NESTED} \\${UNDEFINED} $MODE';
  const expected = JSON.stringify(["parent-doc", value, "", `pre${value}post`, "${UNDEFINED}", "${UNDEFINED}", "$MODE"]);
  const source = [
    block(`$ ${LOCAL_PACKAGE} args \${MODE}\n["parent"] (equal)\n`),
    block('$ export MODE=${MODE}-doc\n' +
      `$ export VALUE=${quoteArgument(value)}\n` +
      "$ export EMPTY=\n$ export FILE=relative.txt\n$ export NESTED='${UNDEFINED}'\n"),
    ...[SCRIPT_COMMAND, LOCAL_PACKAGE].map(program => block(
      `$ ${program} args ${args}\n${expected} (equal)\n` +
      `$ ${program} context\nparent-doc\nyes\ncwd contents\n` +
      `$ ${program} read-file \${FILE}\ncwd contents\n`,
    )),
    block(`$ ${SCRIPT_COMMAND} context|${LOCAL_PACKAGE} check-env-echo \${MODE}|${SCRIPT_COMMAND} check-env-echo \${MODE}\nparent-doc\nyes\ncwd contents\n`),
    block(`$ ${LOCAL_PACKAGE} context|${SCRIPT_COMMAND} check-env-echo \${MODE}|${LOCAL_PACKAGE} check-env-echo \${MODE}\nparent-doc\nyes\ncwd contents\n`),
    block('$ export MODE=\n' + [SCRIPT_COMMAND, LOCAL_PACKAGE].map(program =>
      `$ ${program} context\n\nyes\ncwd contents\n`).join("")),
    block(`$ export MODE=final\n$ ${LOCAL_PACKAGE} context\nfinal\nyes\ncwd contents\n`),
  ].join("\n");
  const document = writeDocument(docs, "exports-main.md", source);
  assert(cli(["test", document, "--target", target]).stdout.includes("12 cases, 0 failed, 0 errors"));

  const isolated = writeDocument(docs, "exports-z-isolated.md", contextCase(LOCAL_PACKAGE));
  assert(cli(["test", document, isolated, "--target", target]).stdout.includes("14 cases, 0 failed, 0 errors"));
  const onlyExports = writeDocument(docs, "exports-only.md", block("$ export MODE=only\n"));
  assert(cli(["test", onlyExports], { expected: EXIT_CODE.ERROR }).stderr.includes("no mooncram cases"));
  assert(cli(["test", onlyExports, isolated, "--target", target]).stdout.includes("2 cases, 0 failed, 0 errors"));

  const command = `$ ${SCRIPT_COMMAND} args \${MODE}`;
  const prefix = block('$ export MODE=${MODE}-updated\n');
  const original = prefix + block(`${command}\nwrong\n`);
  const update = writeDocument(docs, "exports-update.md", original);
  const dryRun = cli(["update", update, "--target", target, "--dry-run"]);
  assert(dryRun.stdout.includes(command));
  assert(dryRun.stdout.includes("1 cases, would update 1, 0 errors"));
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), prefix + block(`${command}\n${JSON.stringify('["parent-updated"]')} (escaped)\n`));
  cli(["test", update, "--target", target]);

  const sideEffect = join(docs, "side-effect.txt");
  for (const invalid of [
    "export INVALID", "export A=x B=y", "export 1A=x",
    `export A=x|${LOCAL_PACKAGE} hello`, `${LOCAL_PACKAGE} hello|export A=x`,
    `${LOCAL_PACKAGE} args \${UNDEFINED}`, `${LOCAL_PACKAGE} args \${}`,
    `${LOCAL_PACKAGE} args \${UNCLOSED`, `\${MODE}`, `${LOCAL_PACKAGE}|\${MODE}`,
    "export A=x\noutput", "export A=x\n[0]",
  ]) {
    fs.rmSync(sideEffect, { force: true });
    const bad = writeDocument(docs, "exports-error.md", block(`$ ${LOCAL_PACKAGE} setup\n$ ${invalid}\n`));
    const before = fs.readFileSync(bad);
    const result = cli(["update", bad, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(result.stderr.includes("exports-error.md:"));
    assert(!fs.existsSync(sideEffect), "a case ran before the complete document was parsed");
    assert.deepEqual(fs.readFileSync(bad), before);
  }
}

function testExportCasing({ cli, docs, target }) {
  const windows = process.platform === "win32";
  const checkBoth = (name, reference, value) => [SCRIPT_COMMAND, LOCAL_PACKAGE].map(program =>
    `$ ${program} check-env ${name} \${${reference}}\n${value || " (equal)"}\n`).join("");
  const modeKey = windows ? "MODE" : "mode";
  const newKey = windows ? "MOONCRAM_CASE_VALUE" : "Mooncram_Case_Value";
  const source = block(
    checkBoth("MODE", windows ? "mOdE" : "MODE", "parent") +
    "$ export MoDe=${MODE}-doc\n" +
    checkBoth(windows ? "MODE" : "MoDe", "MoDe", "parent-doc") +
    "$ export mode=${MoDe}-next\n" +
    checkBoth(modeKey, windows ? "mODE" : "mode", "parent-doc-next") +
    "$ export Mooncram_Case_Value=first\n" +
    checkBoth(newKey, "Mooncram_Case_Value", "first") +
    "$ export mooncram_case_value=second\n" +
    checkBoth(newKey, "Mooncram_Case_Value", windows ? "second" : "first") +
    checkBoth(windows ? newKey : "mooncram_case_value", "mooncram_case_value", "second") +
    [
      [SCRIPT_COMMAND, LOCAL_PACKAGE, SCRIPT_COMMAND],
      [LOCAL_PACKAGE, SCRIPT_COMMAND, LOCAL_PACKAGE],
    ].map(([first, second, third]) =>
      `$ ${first} check-env MODE \${MODE}|` +
      `${second} check-env-echo \${mode} ${modeKey}|` +
      `${third} check-env-echo \${Mooncram_Case_Value} ${newKey}\n` +
      `${windows ? "parent-doc-next" : "parent"}\n`).join("") +
    "$ export mode=\n" +
    checkBoth(modeKey, windows ? "Mode" : "mode", "") +
    (windows ? "" : checkBoth("MODE", "MODE", "parent")),
  );
  const document = writeDocument(docs, "exports-casing.md", source);
  const cases = windows ? 16 : 18;
  assert(cli(["test", document, "--target", target]).stdout.includes(`${cases} cases, 0 failed, 0 errors`));
}

function testBuildEnvironment({ cli, docs, directory, target }) {
  if (process.platform === "win32") return;
  const realMoon = process.env.PATH.split(delimiter).map(path => join(path, "moon"))
    .find(path => fs.existsSync(path));
  assert(realMoon);
  const tools = join(directory, "build-env-tools");
  fs.mkdirSync(tools);
  const log = join(directory, "build-env.jsonl");
  fs.writeFileSync(join(tools, "moon"), '#!/usr/bin/env node\n' +
    'const fs = require("node:fs");\n' +
    `fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify(process.env.MODE) + "\\n");\n` +
    `const result = require("node:child_process").spawnSync(${JSON.stringify(realMoon)}, process.argv.slice(2), { stdio: "inherit" });\n` +
    'process.exit(result.status ?? 2);\n', { mode: 0o755 });
  const document = writeDocument(docs, "exports-build.md", block(
    `$ export MODE=first\n$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n` +
    `$ export MODE=second\n$ ${SCRIPT_COMMAND} hello|${LOCAL_PACKAGE} echo\nHello, Moon Bit!\n`,
  ));
  const env = createEnvironment();
  env.PATH = [tools, env.PATH].join(delimiter);
  cli(["test", document, "--target", target], { env });
  const modes = fs.readFileSync(log, "utf8").trim().split("\n").map(line => JSON.parse(line));
  assert(modes.includes("first") && modes.includes("second"));
  assert(modes.every(mode => mode === "first" || mode === "second"));
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
  assert(text.startsWith("😀 Intro\r\n\r\n> - ```mooncram mooncram/integration\r\n"));
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

function testRedirections({ cli, docs, target }) {
  const cases = [
    [`${LOCAL_PACKAGE} streams 2>&1`, "one\ntwo\nthree\n[2]\n"],
    [`${SCRIPT_COMMAND} streams >/dev/null`, "[2]\n"],
    [`${LOCAL_PACKAGE} streams 2>&1 >/dev/null`, "two\n[2]\n"],
    [`${SCRIPT_COMMAND} streams >/dev/null 2>&1`, "two\n[2]\n"],
    [`${LOCAL_PACKAGE} streams 2>&1|${SCRIPT_COMMAND} echo`, "one\ntwo\nthree\n"],
    [`${LOCAL_PACKAGE} hello | ${SCRIPT_COMMAND} relay middle 2>&1|${LOCAL_PACKAGE} echo`, "middle\nHello, Moon Bit!\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} streams 2>&1`, "one\ntwo\nthree\n[2]\n"],
    [`${LOCAL_PACKAGE} streams >/dev/null | ${SCRIPT_COMMAND} check-eof`, "EOF\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} relay middle >/dev/null | ${SCRIPT_COMMAND} check-eof`, "EOF\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} streams >/dev/null`, "[2]\n"],
    [`${LOCAL_PACKAGE} streams >/dev/null 2>&1 | ${SCRIPT_COMMAND} echo`, "two\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} relay middle 2>&1 >/dev/null | ${SCRIPT_COMMAND} echo`, "middle\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} streams >/dev/null 2>&1`, "two\n[2]\n"],
    [`${LOCAL_PACKAGE} invalid-utf8 >/dev/null`, ""],
    [`${SCRIPT_COMMAND} raw >/dev/null | ${LOCAL_PACKAGE} check-eof`, "EOF\n"],
    [`${LOCAL_PACKAGE} raw-stderr >/dev/null 2>&1 | ${LOCAL_PACKAGE} check-raw`, "raw bytes preserved\n"],
    [`${SCRIPT_COMMAND} raw-stderr 2>&1 >/dev/null | ${LOCAL_PACKAGE} echo | ${LOCAL_PACKAGE} check-raw`, "raw bytes preserved\n"],
    [`${LOCAL_PACKAGE} binary >/dev/null | ${LOCAL_PACKAGE} check-eof`, "EOF\n"],
    [`${LOCAL_PACKAGE} large 2>&1 | ${SCRIPT_COMMAND} check-large-merged`, "large streams merged\n"],
    [`${SCRIPT_COMMAND} large >/dev/null 2>&1 | ${LOCAL_PACKAGE} check-large-stderr`, "large stderr preserved\n"],
    [`${LOCAL_PACKAGE} large 2>&1 >/dev/null | ${SCRIPT_COMMAND} check-large-stderr`, "large stderr preserved\n"],
    [`${LOCAL_PACKAGE} binary 2>&1 | ${LOCAL_PACKAGE} hello`, "Hello, Moon Bit!\n"],
    [`${LOCAL_PACKAGE} binary >/dev/null 2>&1 | ${LOCAL_PACKAGE} hello`, "Hello, Moon Bit!\n"],
    [`${LOCAL_PACKAGE} wait-downstream >/dev/null | ${LOCAL_PACKAGE} signal-eof`, "EOF\n"],
  ];
  for (const program of [LOCAL_PACKAGE, SCRIPT_COMMAND]) {
    cases.push([`${program} args '2>&1' ">/dev/null" 2\\>\\&1 \\>/dev/null`,
      '["2>&1",">/dev/null","2>&1",">/dev/null"] (equal)\n']);
  }
  fs.rmSync(join(docs, "downstream-eof.txt"), { force: true });
  const passing = writeDocument(docs, "redirections.md",
    block("$ export MARKER='2>&1'\n") +
    cases.map(([command, output]) => block(`$ ${command}\n${output}`)).join("\n") +
    block(`$ ${LOCAL_PACKAGE} args \${MARKER} "\${MARKER}" after\n["2>&1","2>&1","after"] (equal)\n`));
  cli(["test", passing, "--target", target]);

  // Only unredirected stderr belongs to diagnostics, in segment order.
  for (const [command, output, diagnostic] of [
    [`${LOCAL_PACKAGE} streams 2>&1 | ${SCRIPT_COMMAND} relay middle | ${LOCAL_PACKAGE} relay last`,
      "one\ntwo\nthree\n", "middle\nlast\n"],
    [`${LOCAL_PACKAGE} streams >/dev/null | ${SCRIPT_COMMAND} relay middle | ${LOCAL_PACKAGE} relay last >/dev/null 2>&1`,
      "last\n", "two\nmiddle\n"],
    [`${LOCAL_PACKAGE} streams 2>&1 >/dev/null`, "two\n[2]\n", ""],
  ]) {
    const document = writeDocument(docs, "redirect-diagnostic.md", block(`$ ${command}\nwrong\n`));
    const result = cli(["test", document, "--target", target], { expected: EXIT_CODE.FAILURE });
    if (diagnostic) assert(result.stdout.includes(`diagnostic stderr\n${diagnostic}`));
    else assert(!result.stdout.includes("diagnostic stderr"));
    cli(["update", document, "--target", target]);
    assert.equal(fs.readFileSync(document, "utf8"), block(`$ ${command}\n${output}`));
  }

  const command = `$ ${SCRIPT_COMMAND} streams\t>/dev/null 2>&1|${LOCAL_PACKAGE} echo 2>&1`;
  const original = block(`${command}\nwrong\n`);
  const update = writeDocument(docs, "redirect-update.md", original);
  assert(cli(["update", update, "--target", target, "--dry-run"]).stdout.includes(command));
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), block(`${command}\ntwo\n`));
  cli(["test", update, "--target", target]);

  for (const invalid of ["2>&1", `${LOCAL_PACKAGE} >/dev/null >/dev/null`,
    `${LOCAL_PACKAGE} 2> &1`, `${LOCAL_PACKAGE} >/dev/null arg`,
    "export A=x 2>&1", `${LOCAL_PACKAGE} stderr>/stdout`,
    `${LOCAL_PACKAGE} stdout>/null`, `${LOCAL_PACKAGE} 2>&1 2>&1`,
    `${LOCAL_PACKAGE} > /dev/null`, `${LOCAL_PACKAGE} hello2>&1`,
    `${LOCAL_PACKAGE} hello>/dev/null`, `${LOCAL_PACKAGE} 2\\>&1`,
    `${LOCAL_PACKAGE} 2>\\&1`]) {
    const original = block(`$ ${invalid}\n`);
    const document = writeDocument(docs, "redirect-invalid.md", original);
    const result = cli(["update", document, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(result.stderr.includes("redirect-invalid.md:2:"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
  }
}

function testPipelinePreflight({ cli, docs, target }) {
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  for (const downstream of ["bad", "./bad.mbtx", "./missing.mbtx"]) {
    const document = writeDocument(docs, "preflight.md", block(
      `$ ${LOCAL_PACKAGE} setup >/dev/null 2>&1 | ${downstream}\n`,
    ));
    cli(["test", document, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(!fs.existsSync(sideEffect), "upstream ran before all builds succeeded");
  }
}

function testPipelineStartupFailure({ cli, docs, directory, project, packageDir, target }) {
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
  // Changing the tool paths can invalidate native build commands. Warm both
  // artifacts with this environment before measuring startup-failure cleanup.
  run([
    "moon", "-C", project, "run", "--build-only", "--target", target, packageDir,
  ], { cwd: docs, env });
  run([
    "moon", "run", "--build-only", "--target", "wasm", join(docs, SCRIPT_FILENAME),
  ], { cwd: docs, env });
  for (const suffix of ["", " 2>&1", " >/dev/null", " >/dev/null 2>&1"]) {
    const original = block(
      `$ ${LOCAL_PACKAGE} hello\nwrong\n\n` +
      `$ ${LOCAL_PACKAGE} slow slow-spawn.txt >/dev/null 2>&1 | ${SCRIPT_COMMAND} echo${suffix}\n`,
    );
    const document = writeDocument(docs, "startup-error.md", original);
    const start = performance.now();
    const result = cli(["update", document, "--target", target], { env, expected: EXIT_CODE.ERROR });
    const elapsed = performance.now() - start;
    const diagnostic = `${target}: pipeline startup failure took ${elapsed.toFixed(0)} ms` +
      `\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`;
    assert(result.stderr.includes("@process.spawn()"), diagnostic);
    assert(result.stderr.includes("startup-error.md:5:"));
    assert(result.stdout.includes("+Hello, Moon Bit!"));
    assert(result.stderr.includes("Not updating"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
    assert(!fs.existsSync(join(docs, "slow-spawn.txt")), diagnostic);
    assert(elapsed < CANCELLATION_LIMIT_MS, diagnostic);
  }
}

function testPipelineCaptureFailure({ cli, docs, target }) {
  for (const suffix of ["", " 2>&1"]) {
    const original = block(
      `$ ${LOCAL_PACKAGE} hello\nwrong\n\n` +
      `$ ${LOCAL_PACKAGE} slow slow-capture.txt >/dev/null | ${LOCAL_PACKAGE} invalid-stderr${suffix}\n`,
    );
    const document = writeDocument(docs, "capture-error.md", original);
    const start = performance.now();
    const result = cli(["update", document, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(performance.now() - start < CANCELLATION_LIMIT_MS);
    assert(result.stderr.includes("Not updating"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
  }
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
      `$ ${LOCAL_PACKAGE} slow slow-first.txt 2>&1 | ${LOCAL_PACKAGE} slow slow-middle.txt >/dev/null 2>&1 | ${LOCAL_PACKAGE} slow slow-last.txt >/dev/null\nwrong\n`,
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
      `$ ${LOCAL_PACKAGE} slow slow-first.txt >/dev/null | ${LOCAL_PACKAGE} slow slow-middle.txt 2>&1 | ${LOCAL_PACKAGE} hello >/dev/null\nHello, Moon Bit!\n`,
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

function testDirectoryScanning({ cli, directory, target }) {
  const scan = createScanFixtures(directory);
  const explicit = cli(["test", scan, join(scan, "a.md"), "--target", target]);
  assert(explicit.stdout.includes("2 cases"));
  const implicit = cli(["test", "--target", target], { cwd: scan, expected: EXIT_CODE.ERROR });
  assert(implicit.stderr.includes("requires moon.mod in startup cwd"));
  const fromModule = cli(["test", scan, "--target", target]);
  assert(fromModule.stdout.includes("2 cases"));
}

async function exercise(target) {
  const executable = buildExecutable(target);
  const directory = createTemporaryDirectory(target);
  try {
    const fixtures = createFixtures(directory);
    const context = { ...fixtures, target, cli: createCli(executable, fixtures.project) };

    testCliArguments(context);
    testModuleResolution(context);
    testPassingCases(context);
    testExports(context);
    testExportCasing(context);
    testBuildEnvironment(context);
    console.log(`${target}: scripts, packages, args, document exports, build env, cwd, stdin EOF, stdout and large dual-stream output passed`);

    testDiagnostics(context);
    testUpdates(context);
    console.log(`${target}: diagnostics, dry-run, local updates, escaping, pattern preservation passed`);

    testUpdateErrors(context);
    testPipelines(context);
    testRedirections(context);
    testPipelinePreflight(context);
    testPipelineStartupFailure(context);
    testPipelineCaptureFailure(context);
    console.log(`${target}: mixed pipelines, raw bytes, large output, early exit, stderr order, last status, redirections and updates passed`);
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
