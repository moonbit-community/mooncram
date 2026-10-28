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
  IMPORTS,
  MAIN_PACKAGE_CONFIG,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  run,
  formatImports,
  block,
  findTool,
  copyExecutable,
  copyTool,
  createToolchain,
  isolatedExecutable,
  createEnvironment,
  createCli,
  writePackage,
  writeDocument,
  quotedListItem,
} from "./basic.mjs";

export async function testRemotePackages({ executable, docs, project, directory, target }) {
  // Substitute a native fixture for moonx, so no remote registry/cache or
  // network is touched. Real local packages still build and run normally.
  const tools = createToolchain(join(directory, "remote-tools"), ["moon", "moonc"]);
  const runner = copyTool("moonrun", tools);
  const cli = createCli(isolatedExecutable(executable, target, runner), project);
  const stub = join(project, "moonx-double");
  const helper = fs.readFileSync(join(ROOT, "e2etests/fixtures/moonx.mbt"), "utf8");
  writePackage(stub, formatImports([...IMPORTS, "moonbitlang/core/async/process"]) +
    MAIN_PACKAGE_CONFIG, helper + PROGRAM.replace("let args = @env.args()", "let args = remote_args()"));
  const artifact = JSON.parse(run([
    "moon", "-C", project, "run", "--build-only", "--target", "native", stub,
  ]).stdout).artifacts_path[0];
  const double = copyExecutable(artifact, tools, "moonx");
  const env = { ...createEnvironment(), PATH: tools + delimiter + process.env.PATH,
    MOONCRAM_TEST_REAL_MOONX: findTool("moonx"),
    MOONCRAM_TEST_NODE: process.execPath };
  const invoke = (args, options = {}) => cli(args, { env, ...options });
  const write = (name, source) => writeDocument(docs, `remote-${name}.md`, source);
  const passing = write("passing", [
    block("$ moonx fixture/tool@1.2.3 hello\nHello, Moon Bit!\n", ""),
    block('$ moonx fixture/tool@1.2.3 args -- --target native\n["--","--target","native"]\n', ""),
    block('#cwd(../cwd fixture)\n' +
      '$ moonx fixture/tool@1.2.3 context\nparent\nyes\nconfigured contents\n' +
      `$ moonx fixture/tool@1.2.3 read-file relative.txt|${SCRIPT_COMMAND} check-file-echo 'configured contents'|${LOCAL_PACKAGE} check-file-echo 'configured contents'|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 check-file-echo 'configured contents'\nconfigured contents\n`),
    block('$ moonx fixture/tool@1.2.3 args "${MODE}" \'a|b\' \'\' --target native\n' +
      '["${MODE}","a|b","","--target","native"]\n' +
      '$ MODE=remote moonx fixture/tool@1.2.3 context\nremote\nyes\ncwd contents\n', ""),
    block("$ MODE=${MODE}-temporary moonx fixture/tool@1.2.3 check-env MODE '${MODE}-temporary'\n${MODE}-temporary\n" +
      '$ moonx fixture/tool@1.2.3 check-env MODE parent\nparent\n', ""),
    block(`$ MODE=first moonx fixture/tool@1.2.3 check-env MODE first|${LOCAL_PACKAGE} check-env-echo parent|MODE=last moonx fixture/tool/cmd@2.0.0-rc.1+build.007 check-env-echo last|${SCRIPT_COMMAND} check-env-echo parent\nfirst\n`),
    block(`$ ${LOCAL_PACKAGE} check-env MODE parent|MODE=middle moonx fixture/tool@1.2.3 check-env-echo middle|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 check-env-echo parent\nparent\n`),
    block("$ moonx fixture/tool/cmd@2.0.0-rc.1+build.007 invocation --version\n" +
      '["--target","wasm","fixture/tool/cmd@2.0.0-rc.1+build.007","--","invocation","--version"]\n'),
    block(`$ moonx fixture/tool@1.2.3 hello|${LOCAL_PACKAGE} echo|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 echo\nHello, Moon Bit!\n`),
    block(`$ ${LOCAL_PACKAGE} hello|moonx fixture/tool@1.2.3 echo\nHello, Moon Bit!\n`),
    block(`$ moonx fixture/tool@1.2.3 streams|${LOCAL_PACKAGE} relay middle|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 relay-tail last\n` +
      "@STDOUT\none\nthree\n@STDERR\ntwo\nmiddle\nlast (no-eol)\n[2]\n"),
    block("$ moonx fixture/tool@1.2.3 dual-tail\n@STDERR\nerr (no-eol)\n@STDOUT\nout (no-eol)\n", ""),
    block("$ moonx fixture/tool@1.2.3 status 3\n[3]\n$ moonx fixture/tool@1.2.3 status 3|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 hello\nHello, Moon Bit!\n[3]\n", ""),
    block(`$ ${LOCAL_PACKAGE} streams|moonx fixture/tool@1.2.3 echo\none\nthree\n[2]\n`),
    block("$ moonx fixture/tool@1.2.3 status 3 600|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 status 2 0|moonx fixture/tool@1.2.3 status 0\n[2]\n", ""),
    block("$ moonx fixture/tool@1.2.3 status 2 0|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 status 3 600|moonx fixture/tool@1.2.3 status 0\n[3]\n", ""),
  ].join("\n"));
  // Both remote coordinates remain wasm even when local packages use native.
  for (const backend of TARGETS) invoke(["test", passing, "--target", backend]);

  // Coordinates are usable across documents without any declaration.
  const another = write("another", block("$ moonx fixture/tool@1.2.3 hello\nHello, Moon Bit!\n", ""));
  invoke(["test", passing, another, "--target", target]);
  const sideEffect = join(docs, "side-effect.txt");
  const localConfig = join(project, "cmd", "moon.pkg");
  const savedConfig = fs.readFileSync(localConfig, "utf8");
  fs.writeFileSync(localConfig, 'pkgtype(kind: false)\n');
  const sameModule = write("same-module", block("$ moonx mooncram/integration/cmd@1.2.3 hello\nHello, Moon Bit!\n"));
  invoke(["test", sameModule]);
  fs.writeFileSync(localConfig, savedConfig);
  const legacy = write("legacy", "```mooncram-import invalid settings\ninvalid declaration\n```\n" +
    block("$ moonx fixture/tool@1.2.3 hello\nHello, Moon Bit!\n", ""));
  invoke(["test", legacy]);

  // Successful updates preserve the source command and CRLF quote/list layout.
  const command = '$ MODE="${MODE}-temporary" moonx fixture/tool@1.2.3 args "${MODE}"';
  const before = (quotedListItem(block(
    command + "\nwrong\n", "")) + "\nTail").replaceAll("\n", CRLF);
  const update = write("update", before);
  const expectedUpdate = before.replace("wrong", '["${MODE}"]');
  const dryRun = invoke(["update", update, "--dry-run"]);
  assert(dryRun.stdout.includes("would update 1"));
  assert.equal(fs.readFileSync(update, "utf8"), before);
  invoke(["update", update]);
  assert.equal(fs.readFileSync(update, "utf8"), expectedUpdate);
  invoke(["test", update]);

  const dualUpdate = write("dual-update", block("$ moonx fixture/tool@1.2.3 dual-special\n@STDERR (empty)\n@STDOUT (ignore)\n", ""));
  invoke(["update", dualUpdate]);
  assert(fs.readFileSync(dualUpdate, "utf8").includes('@STDERR\n"@STDOUT" (escaped)\n@STDOUT (ignore)'));
  invoke(["test", dualUpdate]);

  const cancelled = [];
  const failures = [
    ["moonx fixture/tool@1.2.3 status 255", 1],
    ["moonx fixture/tool@1.2.3 reserved-output 255", 1],
    ["moonx fixture/tool@1.2.3 status 255|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 hello", 1], // final success cannot mask failure
    ["moonx fixture/tool@1.2.3 hello|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 status 255|moonx fixture/tool@1.2.3 hello", 2],
    ["moonx fixture/tool@1.2.3 hello|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 status 255", 2],
  ];
  for (const [slowFirst, remoteSlow] of [[true, true], [false, true], [true, false], [false, false]]) {
    const filename = `remote-cancel-${slowFirst}-${remoteSlow}.txt`;
    cancelled.push(filename);
    const slow = `${remoteSlow ? "moonx fixture/tool/cmd@2.0.0-rc.1+build.007" : LOCAL_PACKAGE} slow ${filename}`;
    const fail = `moonx fixture/tool@1.2.3 reserved-after 255 ${filename}`;
    failures.push([slowFirst ? `${slow}|${fail}` : `${fail}|${slow}`, slowFirst ? 2 : 1, 255, filename]);
  }
  if (process.platform !== "win32") {
    failures.push(["moonx fixture/tool@1.2.3 signal", 1, -1],
      ["moonx fixture/tool@1.2.3 signal|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 hello", 1, -1],
      ["moonx fixture/tool@1.2.3 hello|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 signal|moonx fixture/tool@1.2.3 hello", 2, -1],
      ["moonx fixture/tool@1.2.3 hello|moonx fixture/tool/cmd@2.0.0-rc.1+build.007 signal", 2, -1]);
    for (const slowFirst of [true, false]) {
      const filename = `remote-signal-${slowFirst}.txt`;
      cancelled.push(filename);
      const slow = `moonx fixture/tool/cmd@2.0.0-rc.1+build.007 slow ${filename}`;
      const fail = `moonx fixture/tool@1.2.3 signal-after ${filename}`;
      failures.push([slowFirst ? `${slow}|${fail}` : `${fail}|${slow}`, slowFirst ? 2 : 1, -1, filename]);
    }
  }
  const good = write("z-other", block("$ moonx fixture/tool@1.2.3 hello\nwrong\n", ""));
  for (const [pipeline, segment, status = 255, slowFilename] of failures) {
    for (const dry of [false, true]) {
      if (slowFilename) fs.rmSync(join(docs, slowFilename + ".started"), { force: true });
      const original = block(`$ moonx fixture/tool@1.2.3 hello\nwrong\n\n$ ${pipeline}\n[${status}]\n`, "mooncram/integration");
      const bad = write("failure", original);
      const start = performance.now();
      const result = invoke(["update", bad, good, "--target", target, "--timeout-ms", "8000", ...(dry ? ["--dry-run"] : [])],
        { expected: EXIT_CODE.ERROR });
      assert(performance.now() - start < CANCELLATION_LIMIT_MS, result.stderr);
      assert(result.stderr.includes(`pipeline segment ${segment}: reserved execution status ${status}`), result.stderr);
      const coordinate = pipeline.split("|")[segment - 1].trim().split(" ")[1];
      assert(result.stderr.includes(`remote '${coordinate}'`), result.stderr);
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
      assert.equal(fs.readFileSync(good, "utf8"), block("$ moonx fixture/tool@1.2.3 hello\nHello, Moon Bit!\n", ""));
      if (slowFilename) assert(fs.existsSync(join(docs, slowFilename + ".started")), "cancellation must exercise a running segment");
    }
  }
  for (const filename of cancelled) {
    assert(fs.existsSync(join(docs, filename + ".started")), "cancellation must exercise a running segment");
  }

  // An unmanaged descendant can hold a stream open after its parent exits.
  // Preserve the partial log without extending the case deadline or hanging.
  for (const mode of ["held-stderr", "held-success"]) {
    const before = block(`$ moonx fixture/tool@1.2.3 ${mode}\n`, "");
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
  invoke(["test", write("local-status", block("$ moonx mooncram/integration/local-status\n[255]\n$ moonx mooncram/integration/local-status|moonx fixture/tool@1.2.3 hello\nHello, Moon Bit!\n[255]\n")), "--target", target]);

  for (const [operation, diagnostic] of [["slow remote-timeout.txt", "timed out"], ["invalid-utf8", ""], ["invalid-stderr", ""]]) {
    const original = block(`$ moonx fixture/tool@1.2.3 hello\nwrong\n$ moonx fixture/tool@1.2.3 ${operation}\n@STDOUT (ignore)\n@STDERR (ignore)\n`, "");
    const bad = write("error", original);
    for (const dry of [false, true]) {
      const result = invoke(["update", bad, "--timeout-ms", "350", ...(dry ? ["--dry-run"] : [])], { expected: EXIT_CODE.ERROR });
      assert(result.stderr.includes(diagnostic));
      assert(result.stderr.includes("Not updating"));
      assert.equal(fs.readFileSync(bad, "utf8"), original);
    }
  }
  // A malformed command prevents an earlier side effect in the same document.
  fs.rmSync(sideEffect, { force: true });
  const parseError = block(`$ ${LOCAL_PACKAGE} setup\nwrong\n$ remote\n`);
  const invalid = write("parse-error", parseError);
  invoke(["update", invalid], { expected: EXIT_CODE.ERROR });
  assert.equal(fs.readFileSync(invalid, "utf8"), parseError);
  assert(!fs.existsSync(sideEffect));
  // No local segment starts when a later local build preflight fails.
  const preflight = write("preflight", block("$ moonx fixture/tool@1.2.3 setup|moonx ./bad.mbtx\n"));
  invoke(["test", preflight], { expected: EXIT_CODE.ERROR });
  assert(!fs.existsSync(sideEffect));
  // A missing moonx executable is a startup error with document protection.
  fs.renameSync(double, double + ".disabled");
  const noMoonxEnv = { ...env, PATH: tools }; // keep lookup wholly isolated
  const startup = block("$ moonx fixture/tool@1.2.3 hello\nwrong\n", "");
  const missing = write("startup", startup);
  const startupResult = invoke(["update", missing], { env: noMoonxEnv, expected: EXIT_CODE.ERROR });
  assert(startupResult.stderr.includes(`failed to start '${double}'`), startupResult.stderr);
  assert(startupResult.stderr.includes("phase: start"));
  assert(startupResult.stderr.includes("segment: 1/1 (fixture/tool@1.2.3)"));
  assert(startupResult.stderr.includes(`tool: ${double}`), startupResult.stderr);
  assert(!startupResult.stderr.includes("available on PATH"), startupResult.stderr);
  assert.equal(fs.readFileSync(missing, "utf8"), startup);
  await new Promise(resolve => setTimeout(resolve, 5500));
  for (const filename of [...cancelled, "remote-timeout.txt"]) {
    assert(!fs.existsSync(join(docs, filename)), `uncancelled process wrote ${filename}`);
  }
  console.log(`${target}: offline remote coordinates, wasm selection, pipelines, reserved statuses, cancellation and updates passed`);
}
