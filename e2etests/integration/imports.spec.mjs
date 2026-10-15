import assert from "node:assert/strict";
import * as fs from "node:fs";
import { delimiter, join } from "node:path";
import { performance } from "node:perf_hooks";
import {
  ROOT,
  PROGRAM,
  TARGETS,
  EXIT_CODE,
  CANCELLATION_LIMIT_MS,
  CRLF,
  CLEANUP_OPTIONS,
  IMPORTS,
  MAIN_PACKAGE_CONFIG,
  LIBRARY_PROGRAM,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  run,
  formatImports,
  block,
  findTool,
  copyExecutable,
  copyTool,
  isolatedExecutable,
  createEnvironment,
  createCli,
  writePackage,
  writeDocument,
  quotedListItem,
} from "./basic.mjs";

export async function testImports({ executable, docs, project, directory, target }) {
  // Substitute a native fixture for moonx, so no remote registry/cache or
  // network is touched. Real local packages still build and run normally.
  const tools = join(directory, "import-tools");
  fs.mkdirSync(tools);
  const runner = copyTool("moonrun", tools);
  const cli = createCli(isolatedExecutable(executable, target, runner), project);
  const stub = join(project, "moonx-double");
  const helper = fs.readFileSync(join(ROOT, "e2etests/fixtures/moonx.mbt"), "utf8");
  writePackage(stub, formatImports([...IMPORTS, "moonbitlang/async/process"]) +
    MAIN_PACKAGE_CONFIG, helper + PROGRAM.replace("let args = @env.args()", "let args = imported_args()"));
  const artifact = JSON.parse(run([
    "moon", "-C", project, "run", "--build-only", "--target", "native", stub,
  ]).stdout).artifacts_path[0];
  const double = copyExecutable(artifact, tools, "moonx");
  const env = { ...createEnvironment(), PATH: tools + delimiter + process.env.PATH,
    MOONCRAM_TEST_REAL_MOONX: findTool("moonx"),
    MOONCRAM_TEST_NODE: process.execPath };
  const invoke = (args, options = {}) => cli(args, { env, ...options });
  const imports = "```mooncram-import\nremote : fixture/tool@1.2.3\n" +
    "Remote : fixture/tool/cmd@2.0.0-rc.1+build.007\n```\n";
  const write = (name, source) => writeDocument(docs, `imports-${name}.md`, source);
  const passing = write("passing", [
    block("$ remote hello\nHello, Moon Bit!\n", ""), // import declared later
    block('$ set-current-working-directory "../cwd fixture"\n' +
      '$ remote context\nparent\nyes\nconfigured contents\n' +
      `$ remote read-file relative.txt|${SCRIPT_COMMAND} check-file-echo 'configured contents'|${LOCAL_PACKAGE} check-file-echo 'configured contents'|Remote check-file-echo 'configured contents'\nconfigured contents\n`),
    imports,
    block('$ export MODE=imported\n$ remote args "${MODE}" \'a|b\' \'\' --target native\n' +
      '["imported","a|b","","--target","native"]\n' +
      '$ remote context\nimported\nyes\ncwd contents\n', ""),
    block('$ MODE=${MODE}-temporary remote check-env MODE "${MODE}"\nimported-temporary\n' +
      '$ remote check-env MODE ${MODE}\nimported\n', ""),
    block(`$ MODE=first remote check-env MODE \${MODE}|${LOCAL_PACKAGE} check-env-echo \${MODE}|MODE=last Remote check-env-echo \${MODE}|${SCRIPT_COMMAND} check-env-echo \${MODE}\nfirst\n`),
    block(`$ ${LOCAL_PACKAGE} check-env MODE \${MODE}|MODE=middle remote check-env-echo \${MODE}|Remote check-env-echo \${MODE}\nimported\n`),
    block("$ Remote invocation --version\n" +
      '["--target","wasm","fixture/tool/cmd@2.0.0-rc.1+build.007","--","invocation","--version"]\n'),
    block(`$ remote hello|${LOCAL_PACKAGE} echo|Remote echo\nHello, Moon Bit!\n`),
    block(`$ ${LOCAL_PACKAGE} hello|remote echo\nHello, Moon Bit!\n`),
    block(`$ remote streams 1>/dev/null 2>&1|${LOCAL_PACKAGE} echo\ntwo\n[2]\n`),
    block(`$ remote streams 2>&1|Remote echo\none\ntwo\nthree\n[2]\n`, ""),
    block(`$ remote streams|${LOCAL_PACKAGE} relay middle|Remote relay-tail last\n` +
      "@STDOUT\none\nthree\n@STDERR\ntwo\nmiddle\nlast (no-eol)\n[2]\n"),
    block("$ remote dual-tail\n@STDERR\nerr (no-eol)\n@STDOUT\nout (no-eol)\n", ""),
    block(`$ remote streams 1>/dev/null 2>&1|Remote echo\n@STDOUT\ntwo\n@STDERR (empty)\n[2]\n`, ""),
    block("$ remote status 3\n[3]\n$ remote status 3|Remote hello\nHello, Moon Bit!\n[3]\n", ""),
    block(`$ ${LOCAL_PACKAGE} streams|remote echo\none\nthree\n[2]\n`),
    block("$ remote status 3 600|Remote status 2 0|remote status 0\n[2]\n", ""),
    block("$ remote status 2 0|Remote status 3 600|remote status 0\n[3]\n", ""),
  ].join("\n"));
  // Both tool aliases remain wasm even when local packages use native.
  for (const backend of TARGETS) invoke(["test", passing, "--target", backend]);

  const isolated = write("isolated", block("$ remote hello\n", ""));
  const isolation = invoke(["test", passing, isolated, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(isolation.stderr.includes("command requires a .mbtx file"));
  const caseSensitive = write("case", imports + block("$ REMOTE hello\n", ""));
  assert(invoke(["test", caseSensitive], { expected: EXIT_CODE.ERROR }).stderr.includes("command requires"));

  // Executable local collisions error before any pipeline program starts.
  const collision = "```mooncram-import\ncmd : fixture/tool@1.2.3\n```\n";
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  const ambiguous = write("ambiguous", collision + block("$ cmd setup|cmd hello\n"));
  assert(invoke(["test", ambiguous], { expected: EXIT_CODE.ERROR }).stderr.includes("ambiguous import alias 'cmd'"));
  assert(!fs.existsSync(sideEffect));
  // Ordinary fences do not probe the module, and non-executable candidates
  // do not collide. Malformed candidate configs must propagate their error.
  invoke(["test", write("ordinary", collision + block("$ cmd hello\nHello, Moon Bit!\n", ""))]);
  const candidate = join(project, "remote");
  writePackage(candidate, 'pkgtype(kind: "library")\n', LIBRARY_PROGRAM);
  invoke(["test", passing, "--target", target]);
  fs.writeFileSync(join(candidate, "moon.pkg"), 'pkgtype(kind: true)\n');
  const configError = write("config", imports + block("$ remote hello\n"));
  assert(invoke(["update", configError], { expected: EXIT_CODE.ERROR }).stderr.includes("invalid configuration"));
  fs.rmSync(candidate, CLEANUP_OPTIONS);

  // Root short-name candidates also collide, including a callable same-name
  // subpackage when the root is a library.
  const resolutionRoot = join(directory, "import-resolution");
  fs.mkdirSync(resolutionRoot);
  fs.writeFileSync(join(resolutionRoot, "moon.mod"), 'name = "fixture/remote"\nsource = "src"\n');
  for (const rootMain of [true, false]) {
    const source = join(resolutionRoot, "src");
    writePackage(source, rootMain ? MAIN_PACKAGE_CONFIG : "", rootMain ? "fn main {}\n" : LIBRARY_PROGRAM);
    writePackage(join(source, "remote"), MAIN_PACKAGE_CONFIG, "fn main {}\n");
    const doc = write("root-collision", imports + block("$ remote hello\n", "fixture/remote"));
    assert(invoke(["test", doc], { cwd: resolutionRoot, expected: EXIT_CODE.ERROR }).stderr.includes("ambiguous import alias"));
  }

  // Successful updates preserve declarations, source command and CRLF quote/list layout.
  const command = '$ MODE="${MODE}-temporary" remote args "${MODE}"';
  const before = (quotedListItem(imports) + "\n\n" + quotedListItem(block(
    "$ export MODE='Moon Bit'\n" + command + "\nwrong\n", "")) + "\nTail").replaceAll("\n", CRLF);
  const update = write("update", before);
  const expectedUpdate = before.replace("wrong", '["Moon Bit-temporary"]');
  const dryRun = invoke(["update", update, "--dry-run"]);
  assert(dryRun.stdout.includes("would update 1"));
  assert.equal(fs.readFileSync(update, "utf8"), before);
  invoke(["update", update]);
  assert.equal(fs.readFileSync(update, "utf8"), expectedUpdate);
  invoke(["test", update]);

  const dualUpdate = write("dual-update", imports + block("$ remote dual-special\n@STDERR (empty)\n@STDOUT (ignore)\n", ""));
  invoke(["update", dualUpdate]);
  assert(fs.readFileSync(dualUpdate, "utf8").includes('@STDERR\n"@STDOUT" (escaped)\n@STDOUT (ignore)'));
  invoke(["test", dualUpdate]);

  const cancelled = [];
  const failures = [
    ["remote status 255", 1],
    ["remote reserved-output 255", 1],
    ["remote status 255|Remote hello", 1], // final success cannot mask failure
    ["remote hello|Remote status 255|remote hello", 2],
    ["remote hello|Remote status 255", 2],
  ];
  for (const [slowFirst, importedSlow] of [[true, true], [false, true], [true, false], [false, false]]) {
    const filename = `import-cancel-${slowFirst}-${importedSlow}.txt`;
    cancelled.push(filename);
    const slow = `${importedSlow ? "Remote" : LOCAL_PACKAGE} slow ${filename}`;
    const fail = `remote reserved-after 255 ${filename}`;
    failures.push([slowFirst ? `${slow}|${fail}` : `${fail}|${slow}`, slowFirst ? 2 : 1, 255, filename]);
  }
  if (process.platform !== "win32") {
    failures.push(["remote signal", 1, -1],
      ["remote signal|Remote hello", 1, -1],
      ["remote hello|Remote signal|remote hello", 2, -1],
      ["remote hello|Remote signal", 2, -1]);
    for (const slowFirst of [true, false]) {
      const filename = `import-signal-${slowFirst}.txt`;
      cancelled.push(filename);
      const slow = `Remote slow ${filename}`;
      const fail = `remote signal-after ${filename}`;
      failures.push([slowFirst ? `${slow}|${fail}` : `${fail}|${slow}`, slowFirst ? 2 : 1, -1, filename]);
    }
  }
  const good = write("z-other", imports + block("$ remote hello\nwrong\n", ""));
  for (const [pipeline, segment, status = 255, slowFilename] of failures) {
    for (const dry of [false, true]) {
      if (slowFilename) fs.rmSync(join(docs, slowFilename + ".started"), { force: true });
      const original = imports + block(`$ remote hello\nwrong\n\n$ ${pipeline}\n[${status}]\n`, "mooncram/integration");
      const bad = write("failure", original);
      const start = performance.now();
      const result = invoke(["update", bad, good, "--target", target, "--timeout-ms", "8000", ...(dry ? ["--dry-run"] : [])],
        { expected: EXIT_CODE.ERROR });
      assert(performance.now() - start < CANCELLATION_LIMIT_MS, result.stderr);
      assert(result.stderr.includes(`pipeline segment ${segment}: reserved execution status ${status}`), result.stderr);
      const failedAlias = pipeline.split("|")[segment - 1].split(" ")[0];
      const coordinate = failedAlias === "Remote" ? "fixture/tool/cmd@2.0.0-rc.1+build.007" : "fixture/tool@1.2.3";
      assert(result.stderr.includes(`import '${failedAlias}' (${coordinate})`), result.stderr);
      assert(result.stderr.includes("Not updating"));
      assert(result.stderr.includes(`segment: ${segment}/${pipeline.split("|").length}`));
      if (pipeline.includes("reserved-output")) {
        assert(result.stderr.includes("stderr-begin\n" + "e".repeat(70000) + "\nstderr-end\n"));
        assert.equal(result.stderr.split("stderr-begin").length, 2);
        assert.equal(result.stderr.split("stdout before failure").length, 2);
      }
      if (slowFilename && status === 255) assert(result.stderr.includes("failure after sibling started"));
      if (status === -1) assert(result.stderr.includes("stderr before signal"));
      assert(!result.stdout.includes(`${bad} (updated)`));
      assert.equal(fs.readFileSync(bad, "utf8"), original);
      assert.equal(fs.readFileSync(good, "utf8"), imports + block("$ remote hello\nHello, Moon Bit!\n", ""));
      if (slowFilename) assert(fs.existsSync(join(docs, slowFilename + ".started")), "cancellation must exercise a running segment");
    }
  }
  for (const filename of cancelled) {
    assert(fs.existsSync(join(docs, filename + ".started")), "cancellation must exercise a running segment");
  }

  // An unmanaged descendant can hold a stream open after its parent exits.
  // Preserve the partial log without extending the case deadline or hanging.
  for (const mode of ["held-stderr", "held-success"]) {
    const before = imports + block(`$ remote ${mode}\n`, "");
    const document = write(mode, before);
    const start = performance.now();
    const result = invoke(["update", document, "--timeout-ms", "1000"], { expected: EXIT_CODE.ERROR });
    const pid = result.stderr.match(/held-pid=(\d+)/)?.[1];
    try {
      assert(pid, result.stderr);
      assert(performance.now() - start < CANCELLATION_LIMIT_MS, result.stderr);
      assert(result.stderr.includes("held diagnostic"), result.stderr);
      assert(result.stderr.includes("partial"), result.stderr);
      if (mode === "held-success") {
        assert(result.stderr.includes("timed out after 1000 ms"), result.stderr);
        assert(result.stderr.includes("phase: capture"), result.stderr);
      } else {
        assert(result.stderr.includes("reserved execution status 255"), result.stderr);
        assert(!result.stderr.includes("timed out"), result.stderr);
      }
      assert.equal(fs.readFileSync(document, "utf8"), before);
    } finally {
      if (pid) {
        try { process.kill(Number(pid)); } catch (error) {
          if (error.code !== "ESRCH") throw error;
        }
      }
    }
  }

  // Local programs returning 255 remain assertable, including upstream.
  const localStatus = join(project, "local-status");
  writePackage(localStatus, formatImports(["moonbitlang/x/sys"]) + MAIN_PACKAGE_CONFIG, "fn main { @sys.exit(255) }\n");
  invoke(["test", write("local-status", imports + block("$ local-status\n[255]\n$ local-status|remote hello\nHello, Moon Bit!\n[255]\n")), "--target", target]);

  for (const [operation, diagnostic] of [["slow import-timeout.txt", "timed out"], ["invalid-utf8", ""], ["invalid-stderr", ""]]) {
    const original = imports + block(`$ remote hello\nwrong\n$ remote ${operation}\n@STDOUT (ignore)\n@STDERR (ignore)\n`, "");
    const bad = write("error", original);
    for (const dry of [false, true]) {
      const result = invoke(["update", bad, "--timeout-ms", "350", ...(dry ? ["--dry-run"] : [])], { expected: EXIT_CODE.ERROR });
      assert(result.stderr.includes(diagnostic));
      assert(result.stderr.includes("Not updating"));
      assert.equal(fs.readFileSync(bad, "utf8"), original);
    }
  }
  // Parsing imports precedes all execution, including an earlier side effect.
  fs.rmSync(sideEffect, { force: true });
  const parseError = block(`$ ${LOCAL_PACKAGE} setup\nwrong\n`) + imports + imports;
  const invalid = write("parse-error", parseError);
  invoke(["update", invalid], { expected: EXIT_CODE.ERROR });
  assert.equal(fs.readFileSync(invalid, "utf8"), parseError);
  assert(!fs.existsSync(sideEffect));
  // No local segment starts when a later local build preflight fails.
  const preflight = write("preflight", imports + block("$ remote setup|./bad.mbtx\n"));
  invoke(["test", preflight], { expected: EXIT_CODE.ERROR });
  assert(!fs.existsSync(sideEffect));
  // A missing moonx executable is a startup error with document protection.
  fs.renameSync(double, double + ".disabled");
  const noMoonxEnv = { ...env, PATH: tools }; // keep lookup wholly isolated
  const startup = imports + block("$ remote hello\nwrong\n", "");
  const missing = write("startup", startup);
  const startupResult = invoke(["update", missing], { env: noMoonxEnv, expected: EXIT_CODE.ERROR });
  assert(startupResult.stderr.includes("failed to start 'moonx'"));
  assert(startupResult.stderr.includes("phase: start"));
  assert(startupResult.stderr.includes("segment: 1/1 (remote)"));
  assert(startupResult.stderr.includes("hint: check that 'moonx' is available on PATH"));
  assert.equal(fs.readFileSync(missing, "utf8"), startup);
  await new Promise(resolve => setTimeout(resolve, 5500));
  for (const filename of [...cancelled, "import-timeout.txt"]) {
    assert(!fs.existsSync(join(docs, filename)), `uncancelled process wrote ${filename}`);
  }
  console.log(`${target}: offline file imports, ambiguity, wasm selection, pipelines, reserved statuses, cancellation and updates passed`);
}
