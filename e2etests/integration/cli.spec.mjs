import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import {
  ROOT,
  EXIT_CODE,
  DIRECTORY_LINK_TYPE,
  INVALID_PROGRAM,
  LIBRARY_PROGRAM,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  block,
  quoteArgument,
  writePackage,
  writeDocument,
} from "./basic.mjs";

const CLI_VERSION = fs.readFileSync(join(ROOT, "moon.mod"), "utf8")
  .match(/^version\s*=\s*"([^"]+)"/m)?.[1];
assert(CLI_VERSION, "moon.mod must declare a version");
const INVALID_CLI_ARGUMENTS = [
  ["test", "--timeout-ms", "0"],
  ["test", "--target", "js"],
  ["test", "--color", "invalid"],
  ["test", "--dry-run"],
  ["test", "missing.md"],
];
const IGNORED_SCAN_DIRECTORIES = [".hidden", "_build", "target"];

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

export function testCliArguments({ cli, docs }) {
  for (const args of [["--help"], ["-h"], ["help"], ["help", "--help"]]) {
    const result = cli(args);
    assert(result.stdout.includes("Usage: mooncram"), result.stdout);
    assert.equal(result.stderr, "");
    for (const option of ["--target", "--timeout-ms", "--color"]) {
      assert(!result.stdout.includes(option), result.stdout);
    }
  }
  const testHelp = cli(["test", "--help"]).stdout;
  const updateHelp = cli(["update", "--help"]).stdout;
  const checkHelp = cli(["check", "--help"]).stdout;
  for (const option of ["--target", "--timeout-ms", "--color"]) {
    assert(testHelp.includes(option), testHelp);
    assert(updateHelp.includes(option), updateHelp);
  }
  assert(checkHelp.includes("--color"), checkHelp);
  assert(!checkHelp.includes("--target"), checkHelp);
  assert(!checkHelp.includes("--timeout-ms"), checkHelp);
  for (const [option, value] of [["--target", "wasm"], ["--timeout-ms", "60000"], ["--color", "auto"]]) {
    for (const command of ["check", "test", "update", "help"]) {
      cli([option, value, command], { expected: EXIT_CODE.ERROR });
    }
    cli(["help", option, value], { expected: EXIT_CODE.ERROR });
  }
  assert(cli(["update", "--help"]).stdout.includes("dry-run"));
  assert.equal(cli(["--version"]).stdout.trimEnd(), CLI_VERSION);
  for (const args of INVALID_CLI_ARGUMENTS) {
    cli(args, { expected: EXIT_CODE.ERROR });
  }
  for (const [option, values] of [
    ["--timeout-ms", ["0", "-1", "1.5", "2147483648"]],
    ["--target", ["js"]],
    ["--color", ["invalid"]],
  ]) {
    for (const value of values) {
      const result = cli(["test", `${option}=${value}`], { expected: EXIT_CODE.ERROR });
      assert(result.stderr.includes(option) && result.stderr.includes(`'${value}'`), result.stderr);
    }
  }
  const parsePath = writeDocument(docs, "parse-location.md", block("$ moonx ./missing.mbtx '\n", ""));
  const parseResult = cli(["check", parsePath], { expected: EXIT_CODE.ERROR });
  assert(parseResult.stderr.startsWith(`ERROR ${fs.realpathSync(parsePath)}:2:24: unclosed quote`), parseResult.stderr);
  assert.equal(parseResult.stderr.split(fs.realpathSync(parsePath)).length, 2);
  const missingScript = writeDocument(docs, "missing-script.md", block("$ moonx ./missing.mbtx\n", ""));
  const missingResult = cli(["check", missingScript], { expected: EXIT_CODE.ERROR });
  assert(missingResult.stderr.includes("cannot access script './missing.mbtx'"), missingResult.stderr);
  assert(missingResult.stderr.includes("phase: resolve"), missingResult.stderr);
  assert(missingResult.stderr.includes("segment: 1/1 (./missing.mbtx)"), missingResult.stderr);
  for (const command of ["./missing.mbtx", "cmd", "mooncram/integration/cmd", "remote", "moonx", "moonx ''"]) {
    const old = writeDocument(docs, "old-syntax.md", block(`$ ${command}\n`));
    const result = cli(["check", old], { expected: EXIT_CODE.ERROR });
    assert(result.stderr.includes(command.startsWith("moonx") ? "requires a nonempty target" : "must start with moonx"), result.stderr);
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

export function testModuleResolution({ cli, docs, directory, target }) {
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
  invoke("$ moonx user/foo/cmd/deep/boo\ndeep\n");
  const selected = invoke("$ moonx user/foo\nroot\n$ moonx user/foo/foo\nchild\n");
  assert.equal(selected.stderr, "");
  const update = writeDocument(docs, "module-update.md", block("$ moonx user/foo/foo\nwrong\n", declaration));
  cli(["update", update, "--target", target], { cwd: moduleRoot });
  assert.equal(fs.readFileSync(update, "utf8"), block("$ moonx user/foo/foo\nchild\n", declaration));
  // Exact full names never fall back to another package.
  fs.writeFileSync(join(sourceRoot, "main.mbt"), INVALID_PROGRAM);
  assert(invoke("$ moonx user/foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("build failed"));
  invoke("$ moonx user/foo/foo\nchild\n");
  fs.writeFileSync(join(sourceRoot, "main.mbt"), print("root"));
  fs.writeFileSync(join(sourceRoot, "moon.pkg"), executable + 'supported_targets = "js"\n');
  assert(invoke("$ moonx user/foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("build failed"));
  writePackage(sourceRoot, 'pkgtype(kind: "library")\n', LIBRARY_PROGRAM);
  assert(invoke("$ moonx user/foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("no executable package"));
  invoke("$ moonx user/foo/foo\nchild\n");
  fs.writeFileSync(join(sub, "moon.pkg"), 'options("is-main": false)\n');
  assert(invoke("$ moonx user/foo/foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("no executable package"));
  fs.writeFileSync(join(sub, "moon.pkg"), 'pkgtype(kind: true)\n');
  assert(invoke("$ moonx user/foo/foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("invalid configuration"));
  fs.writeFileSync(join(sub, "moon.pkg"), executable);
  for (const name of ["foo", "cmd/deep/boo", "user/foobar", "other/foo"]) {
    assert(invoke(`$ moonx ${name}\n`, { expected: EXIT_CODE.ERROR }).stderr.includes("expected a full package name"));
  }
  for (const name of [quoteArgument(sub), "./foo", "../foo", "user/foo/cmd/../foo", "user/foo//foo", "user/foo/"]) {
    assert(invoke(`$ moonx ${name}\n`, { expected: EXIT_CODE.ERROR }).stderr.includes("invalid module package name"));
  }
  const nested = join(sourceRoot, "nested");
  writePackage(join(nested, "cmd"), executable, print("nested"));
  fs.writeFileSync(join(nested, "moon.mod"), 'name = "user/nested"\n');
  assert(invoke("$ moonx user/foo/nested/cmd\n", { expected: EXIT_CODE.ERROR }).stderr.includes("nested modules"));
  let result;

  // Validate the whole document before the first command, even configuration-only declarations.
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  const invalid = writeDocument(docs, "module-invalid.md",
    block(`$ ${SCRIPT_COMMAND} setup\n`, "") + block("#cwd(.)\n", "user/other"));
  const before = fs.readFileSync(invalid);
  result = cli(["update", invalid, "--target", target], { cwd: moduleRoot, expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("module-invalid.md:4: module declaration 'user/other' does not match 'user/foo'"));
  assert(!fs.existsSync(sideEffect));
  assert.deepEqual(fs.readFileSync(invalid), before);
  const declared = writeDocument(docs, "module-missing.md", block("#cwd(.)\n", declaration));
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
  const oldPath = writeDocument(docs, "module-old-path.md", block(`$ moonx ${quoteArgument(sub)}\n`, ""));
  assert(cli(["test", oldPath], { expected: EXIT_CODE.ERROR }).stderr.includes("command requires a .mbtx file"));
}

export function testDirectoryScanning({ cli, directory, target }) {
  const scan = createScanFixtures(directory);
  const explicit = cli(["test", scan, join(scan, "a.md"), "--target", target]);
  assert(explicit.stdout.includes("2 cases"));
  const implicit = cli(["test", "--target", target], { cwd: scan, expected: EXIT_CODE.ERROR });
  assert(implicit.stderr.includes("requires moon.mod in startup cwd"));
  const fromModule = cli(["test", scan, "--target", target]);
  assert(fromModule.stdout.includes("2 cases"));
}
