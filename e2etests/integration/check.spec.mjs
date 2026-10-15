import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import {
  EXIT_CODE, INVALID_PROGRAM, MAIN_PACKAGE_CONFIG, SCRIPT_COMMAND,
  block, copyExecutable, copyTool, createCli, createEnvironment,
  formatImports, isolatedExecutable, quoteArgument, run, writeDocument, writePackage,
} from "./basic.mjs";

export function testCheck({ executable, target, directory, docs, project }) {
  // Windows searches the runner's directory before PATH. Give the real runner
  // a separate name beside the doubles, so child moonrun calls are rejected too.
  const tools = join(directory, "check-tools");
  fs.mkdirSync(tools);
  const runner = copyTool("moonrun", tools, "mooncram-test-runner");
  const stub = join(project, "reject-tools");
  writePackage(stub, formatImports([
    "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/process",
    "moonbitlang/core/env", "moonbitlang/x/sys",
  ]) + MAIN_PACKAGE_CONFIG,
  'async fn main {\n' +
    '  let args = @env.args()\n' +
    '  if args.get(1) is Some("--probe-tool") {\n' +
    '    @sys.exit(@process.run(args[2], ["--mooncram-tool-probe", args[2]]))\n' +
    '  }\n' +
    '  @fs.write_file(@env.get_env_var("MOONCRAM_TOOL_CALL").unwrap(), args.join("\\n"))\n' +
    '  @sys.exit(99)\n}\n');
  const artifact = JSON.parse(run([
    "moon", "-C", project, "run", "--build-only", "--target", "native", stub,
  ]).stdout).artifacts_path[0];
  const probe = target === "wasm" ? [runner, JSON.parse(run([
    "moon", "-C", project, "run", "--build-only", "--target", "wasm", stub,
  ]).stdout).artifacts_path[0], "--"] : [artifact];
  for (const name of ["moon", "moonx", "moonrun"]) copyExecutable(artifact, tools, name);
  const calls = join(directory, "check-tool-call.txt");
  const cli = createCli(isolatedExecutable(executable, target, runner), project);
  const env = { ...createEnvironment(), PATH: tools, MOONCRAM_TOOL_CALL: calls };
  // Exercise the actual backend's child-process lookup before relying on the
  // absence of calls to prove that check never builds or executes anything.
  for (const name of ["moon", "moonx", "moonrun"]) {
    run([...probe, "--probe-tool", name], { cwd: project, env, expected: 99 });
    assert.deepEqual(fs.readFileSync(calls, "utf8").split("\n").slice(1),
      ["--mooncram-tool-probe", name]);
    fs.rmSync(calls);
  }
  const documents = new Map();
  const write = (name, source) => {
    const path = writeDocument(docs, `check-${name}.md`, source);
    documents.set(path, source);
    return path;
  };
  const invoke = (args, options = {}) => {
    const result = cli(args, { env, ...options });
    assert(!fs.existsSync(calls), "check invoked a build or execution tool");
    for (const [path, source] of documents) assert.equal(fs.readFileSync(path, "utf8"), source);
    return result;
  };
  assert(invoke(["check", "--help"]).stdout.includes("Validate examples"));
  assert(invoke(["--help"]).stdout.includes("test/update"));

  const badScript = join(docs, "check-invalid.mbtx");
  fs.writeFileSync(badScript, INVALID_PROGRAM);
  writePackage(join(project, "check-invalid"),
    'pkgtype(kind: "executable")\nsupported_targets = "js"\n', INVALID_PROGRAM);
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  const imports = "```mooncram-import\nremote : missing/nonexistent/cmd@1.2.3\n```\n";
  const passing = write("passing",
    block(`$ ${SCRIPT_COMMAND} setup\nincorrect output\n`, "") +
    block('$ ./check-invalid.mbtx | remote | check-invalid\nignored assertion\n') + imports +
    block('$ CHECK_ARG=value ./check-invalid.mbtx "${CHECK_ARG}"\n', ""));
  for (const args of [
    ["check", passing], ["--color", "always", "check", passing],
    ["check", passing, "--color", "never"],
  ]) assert.equal(invoke(args).stdout, "3 cases, 0 errors\n");
  assert(!fs.existsSync(sideEffect));
  assert.equal(fs.readFileSync(badScript, "utf8"), INVALID_PROGRAM);
  assert(!fs.existsSync(join(docs, "_build")), "check built a script");

  for (const args of [
    ["--target", "wasm", "check", passing], ["check", passing, "--target=native"],
    ["--timeout-ms=60000", "check", passing], ["check", "--timeout-ms", "42", passing],
    ["check", passing, "--dry-run"], ["--dry-run", "check", passing],
    ["check", passing, "--color", "invalid"],
  ]) invoke(args, { expected: EXIT_CODE.ERROR });
  invoke(["check", join(docs, "check-absent.md")], { expected: EXIT_CODE.ERROR });

  const empty = write("empty", "No examples.\n");
  assert(invoke(["check", empty], { expected: EXIT_CODE.ERROR }).stderr.includes("no mooncram cases"));
  const onlyConfig = write("config-only", block("$ export A=x\n"));
  assert(invoke(["check", onlyConfig], { expected: EXIT_CODE.ERROR }).stderr.includes("no mooncram cases"));
  const errors = write("targets", block(
    "$ ./missing.mbtx | nonexistent\n$ nonexistent\n$ check-invalid\n"));
  let result = invoke(["check", errors, passing], { expected: EXIT_CODE.ERROR });
  assert.equal(result.stdout, "6 cases, 2 errors\n");
  assert.equal(result.stderr.split("ERROR ").length - 1, 2);
  assert(result.stderr.includes("check-targets.md:2:"));
  assert(result.stderr.includes("check-targets.md:3:"));
  assert(!fs.existsSync(sideEffect));

  for (const [name, source, diagnostic] of [
    ["markdown", "```mooncram\n$ ./check-invalid.mbtx\n", "unclosed"],
    ["command", block("$ ./check-invalid.mbtx || remote\n", ""), "empty pipeline"],
    ["expectation", block("$ ./check-invalid.mbtx\n[ (regex)\n", ""), "invalid regex"],
    ["environment", block('$ ./check-invalid.mbtx ${MOONCRAM_CHECK_UNDEFINED}\n', ""), "undefined variable"],
    ["import", "```mooncram-import\nremote : invalid\n```\n", "invalid import coordinate"],
    ["module-config", block(`$ ${SCRIPT_COMMAND} setup\n`, "") + block("$ export A=x\n", "user/other"), "does not match"],
    ["directory-config", block(`$ ${SCRIPT_COMMAND} setup\n`, "") + block("$ set-current-working-directory missing-check-cwd\n", ""), "invalid working directory"],
  ]) {
    const path = write(name, source);
    result = invoke(["check", path, passing], { expected: EXIT_CODE.ERROR });
    assert.equal(result.stdout, "3 cases, 1 errors\n");
    assert.equal(result.stderr.split("ERROR ").length - 1, 1);
    assert(result.stderr.includes(diagnostic), result.stderr);
    assert(!fs.existsSync(sideEffect));
  }
  const inherited = write("inherited", block('$ ./check-invalid.mbtx "${MOONCRAM_CHECK_ARG}"\n', ""));
  assert.equal(invoke(["check", inherited], {
    env: { ...env, MOONCRAM_CHECK_ARG: "parent" },
  }).stdout, "1 cases, 0 errors\n");

  const work = join(directory, "check-work");
  fs.mkdirSync(work);
  fs.writeFileSync(join(work, "script.mbtx"), INVALID_PROGRAM);
  const cwd = write("cwd", block(
    `$ set-current-working-directory ${quoteArgument(work)}\n$ ./script.mbtx\n`, ""));
  assert.equal(invoke(["check", cwd]).stdout, "1 cases, 0 errors\n");
  const collision = write("collision", block("$ cmd | cmd\n") +
    "```mooncram-import\ncmd : missing/module@1.2.3\n```\n");
  result = invoke(["check", collision], { expected: EXIT_CODE.ERROR });
  assert.equal(result.stdout, "1 cases, 1 errors\n");
  assert.equal(result.stderr.split("ERROR ").length - 1, 1);
  assert(result.stderr.includes("ambiguous import alias 'cmd'"));

  // Exercise default discovery, path deduplication and -- for option-like paths.
  const scan = join(directory, "check-scan");
  fs.mkdirSync(scan);
  fs.writeFileSync(join(scan, "script.mbtx"), INVALID_PROGRAM);
  writeDocument(scan, "-example.md", block("$ ./script.mbtx\n", ""));
  assert.equal(invoke(["check"], { cwd: scan }).stdout, "1 cases, 0 errors\n");
  assert.equal(invoke(["check", "--", "-example.md"], { cwd: scan }).stdout, "1 cases, 0 errors\n");
  assert.equal(invoke(["check", scan, join(scan, "-example.md")]).stdout, "1 cases, 0 errors\n");

  // Root/subpackage warnings remain per segment and do not count as errors.
  const moduleRoot = join(directory, "check-module");
  fs.mkdirSync(moduleRoot);
  fs.writeFileSync(join(moduleRoot, "moon.mod"), 'name = "user/foo"\n');
  for (const path of [moduleRoot, join(moduleRoot, "foo")]) {
    writePackage(path, MAIN_PACKAGE_CONFIG, INVALID_PROGRAM);
  }
  const warning = write("warning", block("$ foo | foo\n", "user/foo"));
  result = invoke(["check", warning], { cwd: moduleRoot });
  assert.equal(result.stdout, "1 cases, 0 errors\n");
  assert.equal(result.stderr.split("WARNING ").length - 1, 2);
  fs.writeFileSync(join(moduleRoot, "moon.mod"), "name =");
  result = invoke(["check", warning], { cwd: moduleRoot, expected: EXIT_CODE.ERROR });
  assert.equal(result.stdout, "0 cases, 1 errors\n");
  assert(result.stderr.includes("invalid configuration"));
}

export function testGeneratedTargets({ cli, docs, project, target }) {
  const generated = join(docs, "generated-target.mbtx");
  const source = 'fn main { println("generated") }\n';
  writePackage(join(project, "generate-target"), formatImports([
    "moonbitlang/async", "moonbitlang/async/fs",
  ]) + MAIN_PACKAGE_CONFIG,
  `async fn main { @fs.write_file("generated-target.mbtx", ${JSON.stringify(source)}) }\n`);
  const correct = block("$ generate-target\n$ ./generated-target.mbtx\ngenerated\n");
  const path = writeDocument(docs, "generated-target.md", correct);
  for (const command of ["test", "update"]) {
    fs.rmSync(generated, { force: true });
    const before = command === "test" ? correct : correct.replace("\ngenerated\n", "\nwrong\n");
    fs.writeFileSync(path, before);
    const checked = cli(["check", path], { expected: EXIT_CODE.ERROR });
    assert.equal(checked.stdout, "2 cases, 1 errors\n");
    assert(checked.stderr.includes("generated-target.mbtx"));
    assert(!fs.existsSync(generated));
    assert.equal(fs.readFileSync(path, "utf8"), before);
    cli([command, path, "--target", target]);
    assert.equal(fs.readFileSync(generated, "utf8"), source);
    assert.equal(fs.readFileSync(path, "utf8"), correct);
    assert.equal(cli(["check", path]).stdout, "2 cases, 0 errors\n");
  }
}
