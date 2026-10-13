import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import {
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

const CLI_VERSION = "0.0.4";
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
  fs.writeFileSync(join(sub, "moon.pkg"), executable);
  invoke("$ foo\nchild\n");
  fs.writeFileSync(join(sub, "moon.pkg"), 'options("is-main": false)\n');
  assert(invoke("$ foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("no executable package"));
  fs.writeFileSync(join(sub, "moon.pkg"), 'pkgtype(kind: true)\n');
  assert(invoke("$ foo\n", { expected: EXIT_CODE.ERROR }).stderr.includes("invalid configuration"));
  fs.writeFileSync(join(sub, "moon.pkg"), executable);

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

export function testDirectoryScanning({ cli, directory, target }) {
  const scan = createScanFixtures(directory);
  const explicit = cli(["test", scan, join(scan, "a.md"), "--target", target]);
  assert(explicit.stdout.includes("2 cases"));
  const implicit = cli(["test", "--target", target], { cwd: scan, expected: EXIT_CODE.ERROR });
  assert(implicit.stderr.includes("requires moon.mod in startup cwd"));
  const fromModule = cli(["test", scan, "--target", target]);
  assert(fromModule.stdout.includes("2 cases"));
}
