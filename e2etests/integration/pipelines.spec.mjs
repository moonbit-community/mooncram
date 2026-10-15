import assert from "node:assert/strict";
import * as fs from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { performance } from "node:perf_hooks";
import {
  EXIT_CODE,
  CANCELLATION_LIMIT_MS,
  EXECUTABLE_SUFFIX,
  TOOL_DIRECTORIES,
  SCRIPT_FILENAME,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  run,
  block,
  findTool,
  copyTool,
  isolatedExecutable,
  createEnvironment,
  createCli,
  writeDocument,
} from "./basic.mjs";

export function testPipelines({ cli, docs, target }) {
  const commands = [
    [`${SCRIPT_COMMAND} hello|${LOCAL_PACKAGE} echo|${SCRIPT_COMMAND} echo`, "Hello, Moon Bit!\n"],
    [`${LOCAL_PACKAGE} context | ${SCRIPT_COMMAND} echo`, "parent\nyes\ncwd contents\n"],
    [`${LOCAL_PACKAGE} streams | ${LOCAL_PACKAGE} echo`, "one\nthree\n[2]\n"],
    [`${LOCAL_PACKAGE} hello | ${LOCAL_PACKAGE} streams`, "one\nthree\n[2]\n"],
    [`${SCRIPT_COMMAND} raw | ${LOCAL_PACKAGE} echo | ${LOCAL_PACKAGE} check-raw`, "raw bytes preserved\n"],
    [`${LOCAL_PACKAGE} binary | ${SCRIPT_COMMAND} noisy-echo | ${LOCAL_PACKAGE} check-binary`, "all bytes preserved\n"],
  ];
  // Change completion order while keeping pipeline positions fixed. The chosen
  // status is the rightmost failure, not the largest or the last to finish.
  for (const statuses of [[0, 0, 0], [2, 0, 0], [0, 3, 0], [0, 0, 4],
    [3, 2, 0], [2, 3, 0], [2, 3, 4]]) {
    const expected = statuses.findLast(status => status !== 0) ?? 0;
    for (const delays of [[600, 300, 0], [0, 300, 600]]) {
      const command = statuses.map((status, i) =>
        `${i === 1 ? SCRIPT_COMMAND : LOCAL_PACKAGE} status ${status} ${delays[i]}`).join("|");
      commands.push([command, expected === 0 ? "" : `[${expected}]\n`]);
    }
  }
  const passing = writeDocument(docs, "pipeline.md",
    commands.map(([command, output]) => block(`$ ${command}\n${output}`)).join("\n"));
  cli(["test", passing, "--target", target]);

  // A missing status assertion fails the case, while later cases still run.
  fs.rmSync(join(docs, "side-effect.txt"), { force: true });
  const missingStatus = writeDocument(docs, "pipeline-missing-status.md", block(
    `$ ${LOCAL_PACKAGE} streams|${LOCAL_PACKAGE} echo\none\nthree\n$ ${LOCAL_PACKAGE} setup\n`,
  ));
  const missing = cli(["test", missingStatus, "--target", target], { expected: EXIT_CODE.FAILURE });
  assert(missing.stdout.includes("exit: expected 0, actual 2"));
  assert(missing.stdout.includes("2 cases, 1 failed, 0 errors"));
  assert.equal(fs.readFileSync(join(docs, "side-effect.txt"), "utf8"), "side effect preserved\n");

  const diagnostic = writeDocument(docs, "pipeline-diagnostic.md", block(
    `$ ${LOCAL_PACKAGE} streams | ${SCRIPT_COMMAND} relay middle | ${LOCAL_PACKAGE} relay last\nwrong\n`,
  ));
  const result = cli(["test", diagnostic, "--target", target], { expected: EXIT_CODE.FAILURE });
  assert(result.stdout.includes("diagnostic stderr\ntwo\nmiddle\nlast\n"));
  assert(result.stdout.includes("expected 0, actual 2"));

  const command = `$ ${SCRIPT_COMMAND} streams|${LOCAL_PACKAGE} echo`;
  const original = block(`${command}\nwrong\n`);
  const update = writeDocument(docs, "pipeline-update.md", original);
  const dryRun = cli(["update", update, "--target", target, "--dry-run"]);
  assert(dryRun.stdout.includes(command));
  assert(dryRun.stdout.includes("[2]"));
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), block(`${command}\none\nthree\n[2]\n`));
  cli(["test", update, "--target", target]);

  // The consumer closes early and a large upstream write fails. The reported
  // status depends on the platform and runner, so only require nonzero.
  for (const command of [
    `${LOCAL_PACKAGE} binary | ${LOCAL_PACKAGE} hello`,
    `${LOCAL_PACKAGE} binary 2>&1 | ${LOCAL_PACKAGE} hello`,
    `${LOCAL_PACKAGE} binary 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} hello`,
  ]) {
    const early = writeDocument(docs, "pipeline-early-close.md", block(`$ ${command}\nHello, Moon Bit!\n`));
    const result = cli(["test", early, "--target", target], { expected: EXIT_CODE.FAILURE });
    const status = result.stdout.match(/exit: expected 0, actual (-?\d+)/);
    assert(status, result.stdout);
    assert.notEqual(Number(status[1]), 0);
    assert(result.stdout.includes("1 cases, 1 failed, 0 errors"));
  }
}

export function testRedirections({ cli, docs, target }) {
  const cases = [
    [`${LOCAL_PACKAGE} streams 2>&1 | ${LOCAL_PACKAGE} echo`, "one\ntwo\nthree\n[2]\n"],
    [`${SCRIPT_COMMAND} streams 1>/dev/null | ${LOCAL_PACKAGE} echo`, "[2]\n"],
    [`${LOCAL_PACKAGE} streams 2>&1 1>/dev/null | ${LOCAL_PACKAGE} echo`, "two\n[2]\n"],
    [`${SCRIPT_COMMAND} streams 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo`, "two\n[2]\n"],
    [`${LOCAL_PACKAGE} streams 2>&1|${SCRIPT_COMMAND} echo`, "one\ntwo\nthree\n[2]\n"],
    [`${LOCAL_PACKAGE} hello | ${SCRIPT_COMMAND} relay middle 2>&1|${LOCAL_PACKAGE} echo`, "middle\nHello, Moon Bit!\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} streams 2>&1 | ${LOCAL_PACKAGE} echo`, "one\ntwo\nthree\n[2]\n"],
    [`${LOCAL_PACKAGE} streams 1>/dev/null | ${SCRIPT_COMMAND} check-eof`, "EOF\n[2]\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} relay middle 1>/dev/null | ${SCRIPT_COMMAND} check-eof`, "EOF\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} streams 1>/dev/null | ${LOCAL_PACKAGE} echo`, "[2]\n"],
    [`${LOCAL_PACKAGE} streams 1>/dev/null 2>&1 | ${SCRIPT_COMMAND} echo`, "two\n[2]\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} relay middle 2>&1 1>/dev/null | ${SCRIPT_COMMAND} echo`, "middle\n"],
    [`${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} streams 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo`, "two\n[2]\n"],
    [`${LOCAL_PACKAGE} invalid-utf8 1>/dev/null | ${LOCAL_PACKAGE} echo`, ""],
    [`${SCRIPT_COMMAND} raw 1>/dev/null | ${LOCAL_PACKAGE} check-eof`, "EOF\n"],
    [`${LOCAL_PACKAGE} raw-stderr 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} check-raw`, "raw bytes preserved\n"],
    [`${SCRIPT_COMMAND} raw-stderr 2>&1 1>/dev/null | ${LOCAL_PACKAGE} echo | ${LOCAL_PACKAGE} check-raw`, "raw bytes preserved\n"],
    [`${LOCAL_PACKAGE} binary 1>/dev/null | ${LOCAL_PACKAGE} check-eof`, "EOF\n"],
    [`${LOCAL_PACKAGE} large 2>&1 | ${SCRIPT_COMMAND} check-large-merged`, "large streams merged\n"],
    [`${SCRIPT_COMMAND} large 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} check-large-stderr`, "large stderr preserved\n"],
    [`${LOCAL_PACKAGE} large 2>&1 1>/dev/null | ${SCRIPT_COMMAND} check-large-stderr`, "large stderr preserved\n"],
    [`${LOCAL_PACKAGE} wait-downstream 1>/dev/null | ${LOCAL_PACKAGE} signal-eof`, "EOF\n"],
  ];
  for (const program of [LOCAL_PACKAGE, SCRIPT_COMMAND]) {
    cases.push([`${program} args '2>&1' "1>/dev/null" 2\\>\\&1 1\\>/dev/null`,
      '["2>&1","1>/dev/null","2>&1","1>/dev/null"]\n']);
  }
  fs.rmSync(join(docs, "downstream-eof.txt"), { force: true });
  const passing = writeDocument(docs, "redirections.md",
    block("$ export MARKER='2>&1'\n") +
    cases.map(([command, output]) => block(`$ ${command}\n${output}`)).join("\n") +
    block(`$ ${LOCAL_PACKAGE} args \${MARKER} "\${MARKER}" after\n["2>&1","2>&1","after"]\n`));
  cli(["test", passing, "--target", target]);

  // Only unredirected stderr belongs to diagnostics, in segment order.
  for (const [command, output, diagnostic] of [
    [`${LOCAL_PACKAGE} streams 2>&1 | ${SCRIPT_COMMAND} relay middle | ${LOCAL_PACKAGE} relay last`,
      "one\ntwo\nthree\n[2]\n", "middle\nlast\n"],
    [`${LOCAL_PACKAGE} streams 1>/dev/null | ${SCRIPT_COMMAND} relay middle | ${LOCAL_PACKAGE} relay last 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo`,
      "last\n[2]\n", "two\nmiddle\n"],
    [`${LOCAL_PACKAGE} streams 2>&1 1>/dev/null | ${LOCAL_PACKAGE} echo`, "two\n[2]\n", ""],
  ]) {
    const document = writeDocument(docs, "redirect-diagnostic.md", block(`$ ${command}\nwrong\n`));
    const result = cli(["test", document, "--target", target], { expected: EXIT_CODE.FAILURE });
    if (diagnostic) assert(result.stdout.includes(`diagnostic stderr\n${diagnostic}`));
    else assert(!result.stdout.includes("diagnostic stderr"));
    cli(["update", document, "--target", target]);
    assert.equal(fs.readFileSync(document, "utf8"), block(`$ ${command}\n${output}`));
  }

  const command = `$ ${SCRIPT_COMMAND} streams\t1>/dev/null 2>&1|${LOCAL_PACKAGE} echo`;
  const original = block(`${command}\nwrong\n`);
  const update = writeDocument(docs, "redirect-update.md", original);
  assert(cli(["update", update, "--target", target, "--dry-run"]).stdout.includes(command));
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), block(`${command}\ntwo\n[2]\n`));
  cli(["test", update, "--target", target]);

  for (const invalid of ["2>&1", `${LOCAL_PACKAGE} 1>/dev/null 1>/dev/null`,
    `${LOCAL_PACKAGE} 2> &1`, `${LOCAL_PACKAGE} 1>/dev/null arg`,
    "export A=x 2>&1", `${LOCAL_PACKAGE} stderr>/stdout`,
    `${LOCAL_PACKAGE} stdout>/null`, `${LOCAL_PACKAGE} 2>&1 2>&1`,
    `${LOCAL_PACKAGE} 1> /dev/null`, `${LOCAL_PACKAGE} hello2>&1`,
    `${LOCAL_PACKAGE} hello1>/dev/null`, `${LOCAL_PACKAGE} 2\\>&1`,
    `${LOCAL_PACKAGE} 2>\\&1`, `${LOCAL_PACKAGE} >/dev/null | ${LOCAL_PACKAGE} echo`,
    `${LOCAL_PACKAGE} 2>/dev/null | ${LOCAL_PACKAGE} echo`]) {
    const original = block(`$ ${invalid}\n`);
    const document = writeDocument(docs, "redirect-invalid.md", original);
    const result = cli(["update", document, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(result.stderr.includes("redirect-invalid.md:2:"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
  }
}

export function testFinalRedirectionRejection({ cli, docs, target }) {
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  for (const prefix of ["", `${LOCAL_PACKAGE} hello|`, `${LOCAL_PACKAGE} hello|${SCRIPT_COMMAND} echo|`]) {
    for (const suffix of ["2>&1", "1>/dev/null", "2>&1 1>/dev/null", "1>/dev/null 2>&1"]) {
      const command = prefix + `${LOCAL_PACKAGE} streams ` + suffix;
      const original = block(
        `$ ${LOCAL_PACKAGE} setup\n$ ${LOCAL_PACKAGE} hello\nwrong\n$ ` + command + "\n",
      );
      const document = writeDocument(docs, "final-redirect-invalid.md", original);
      for (const args of [["test"], ["update"], ["update", "--dry-run"]]) {
        const result = cli([...args, document, "--target", target], { expected: EXIT_CODE.ERROR });
        assert(result.stderr.includes(
          "final-redirect-invalid.md:5: redirection is not allowed in the final pipeline segment",
        ), result.stderr);
        assert.equal(fs.readFileSync(document, "utf8"), original);
        assert(!fs.existsSync(sideEffect), "a document with invalid final redirection must not execute");
      }
    }
  }
}

export function testPipelinePreflight({ cli, docs, target }) {
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  for (const downstream of ["bad", "./bad.mbtx", "./missing.mbtx"]) {
    const document = writeDocument(docs, "preflight.md", block(
      `$ ${LOCAL_PACKAGE} setup 1>/dev/null 2>&1 | ${downstream}\n`,
    ));
    cli(["test", document, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(!fs.existsSync(sideEffect), "upstream ran before all builds succeeded");
  }
}

export function testPipelineStartupFailure({ executable, docs, directory, project, packageDir, target }) {
  // Remove moonx from PATH while keeping the build tools. The first package
  // starts successfully, then starting the script must fail and cancel it.
  const tools = join(directory, "tools");
  fs.mkdirSync(tools);
  for (const name of ["moon", "moonc", "moonrun"]) {
    copyTool(name, tools);
  }
  const runner = join(tools, "moonrun" + EXECUTABLE_SUFFIX);
  const cli = createCli(isolatedExecutable(executable, target, runner), project);
  const env = createEnvironment();
  env.PATH = [tools, ...TOOL_DIRECTORIES.filter(path => !fs.existsSync(join(path, "moonx" + EXECUTABLE_SUFFIX)))].join(delimiter);
  // Copied build tools must still load resources from the original toolchain.
  env.MOON_TOOLCHAIN_ROOT ??= dirname(dirname(fs.realpathSync(findTool("moonc"))));
  // Changing the tool paths can invalidate native build commands. Warm both
  // artifacts with this environment before measuring startup-failure cleanup.
  run([
    "moon", "-C", project, "run", "--build-only", "--target", target, packageDir,
  ], { cwd: docs, env });
  run([
    "moon", "run", "--build-only", "--target", "wasm", join(docs, SCRIPT_FILENAME),
  ], { cwd: docs, env });
  for (const suffix of ["", " 2>&1", " 1>/dev/null", " 1>/dev/null 2>&1"]) {
    const downstream = `${SCRIPT_COMMAND} echo` + suffix +
      (suffix ? ` | ${LOCAL_PACKAGE} echo` : "");
    const original = block(
      `$ ${LOCAL_PACKAGE} hello\nwrong\n\n` +
      `$ ${LOCAL_PACKAGE} slow slow-spawn.txt 1>/dev/null 2>&1 | ${downstream}\n`,
    );
    const document = writeDocument(docs, "startup-error.md", original);
    const start = performance.now();
    const result = cli(["update", document, "--target", target], { env, expected: EXIT_CODE.ERROR });
    const elapsed = performance.now() - start;
    const diagnostic = `${target}: pipeline startup failure took ${elapsed.toFixed(0)} ms` +
      `\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`;
    assert(result.stderr.includes("failed to start 'moonx'"), diagnostic);
    assert(result.stderr.includes("phase: start"), diagnostic);
    assert(result.stderr.includes("segment: 2/"), diagnostic);
    assert(result.stderr.includes("startup-error.md:5:"));
    assert(result.stdout.includes("+Hello, Moon Bit!"));
    assert(result.stderr.includes("Not updating"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
    assert(!fs.existsSync(join(docs, "slow-spawn.txt")), diagnostic);
    assert(elapsed < CANCELLATION_LIMIT_MS, diagnostic);
  }
}

export function testPipelineCaptureFailure({ cli, docs, target }) {
  // Warm the package with the same build environment before timing cancellation.
  const warm = writeDocument(docs, "capture-warm.md", block(`$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n`));
  cli(["test", warm, "--target", target]);
  for (const suffix of ["", " 2>&1"]) {
    const downstream = `${LOCAL_PACKAGE} invalid-stderr` + suffix +
      (suffix ? ` | ${LOCAL_PACKAGE} echo` : "");
    const original = block(
      `$ ${LOCAL_PACKAGE} hello\nwrong\n\n` +
      `$ ${LOCAL_PACKAGE} slow slow-capture.txt 1>/dev/null | ${downstream}\n`,
    );
    const document = writeDocument(docs, "capture-error.md", original);
    const start = performance.now();
    const result = cli(["update", document, "--target", target], { expected: EXIT_CODE.ERROR });
    const elapsed = performance.now() - start;
    const diagnostic = `${target}: pipeline capture failure with suffix ${JSON.stringify(suffix)} took ${elapsed.toFixed(0)} ms` +
      `\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`;
    assert(elapsed < CANCELLATION_LIMIT_MS, diagnostic);
    assert(result.stderr.includes("Not updating"));
    assert.equal(fs.readFileSync(document, "utf8"), original);
  }
}

export function testShellOperatorRejection({ cli, docs }) {
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
