import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import {
  TARGETS,
  EXIT_CODE,
  CANCELLATION_LIMIT_MS,
  LOCAL_PACKAGE,
  SCRIPT_COMMAND,
  SCRIPT_FILENAME,
  block,
  writeDocument,
} from "./basic.mjs";

const CASE_TIMEOUT_MS = 350;
const SLOW_SIDE_EFFECT_FILENAME = "slow-finished.txt";

export function assertNoSlowSideEffect(docs) {
  assert(!fs.existsSync(join(docs, SLOW_SIDE_EFFECT_FILENAME)));
  assert(!fs.existsSync(join(docs, "dual-slow.txt")));
  assert(!fs.existsSync(join(docs, "build-timeout-finished.txt")));
  for (const segment of ["first", "middle", "last", "spawn", "capture",
    "script", "script-first", "script-middle", "script-last"]) {
    assert(!fs.existsSync(join(docs, `slow-${segment}.txt`)));
  }
}

export function testTimeouts({ cli, docs, target }) {
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
    assert(cancelled.stderr.includes("phase: run"));
    for (const index of [1, 2, 3]) assert(cancelled.stderr.includes(`${index}/3 (${LOCAL_PACKAGE.slice(6)})`));
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
  testScriptTimeouts({ cli, docs, target });
  assertNoSlowSideEffect(docs);
}

function testScriptTimeouts({ cli, docs, target }) {
  // Warm every artifact first, then require start markers so a build timeout
  // cannot pass as evidence that a running script was cancelled.
  const warm = writeDocument(docs, "script-timeout-warm.md", block(
    `$ ${SCRIPT_COMMAND} hello | ${LOCAL_PACKAGE} echo | ${SCRIPT_COMMAND} echo\nHello, Moon Bit!\n`,
  ));
  cli(["test", warm, "--target", "native"]);
  for (const segments of [
    [[SCRIPT_COMMAND, "script"]],
    [[SCRIPT_COMMAND, "script-first"], [LOCAL_PACKAGE, "script-middle"], [SCRIPT_COMMAND, "script-last"]],
  ]) {
    for (const [, name] of segments) {
      fs.rmSync(join(docs, `slow-${name}.txt.started`), { force: true });
    }
    const command = segments.map(([program, name]) => `${program} slow slow-${name}.txt`).join(" | ");
    const original = block(`$ ${SCRIPT_COMMAND} hello\nwrong\n\n$ ${command}\nwrong\n`);
    const document = writeDocument(docs, "script-timeout.md", original);
    const start = performance.now();
    const result = cli([
      "update", document, "--target", "native", "--timeout-ms", "1500",
    ], { expected: EXIT_CODE.ERROR });
    assert(performance.now() - start < CANCELLATION_LIMIT_MS, result.stderr);
    assert(result.stderr.includes("timed out after 1500 ms"), result.stderr);
    assert(result.stderr.includes("phase: run"), result.stderr);
    for (const [index, [program, name]] of segments.entries()) {
      const label = program === SCRIPT_COMMAND ? `./${SCRIPT_FILENAME}` : LOCAL_PACKAGE.slice(6);
      assert(result.stderr.includes(`${index + 1}/${segments.length} (${label})`), result.stderr);
      assert(fs.existsSync(join(docs, `slow-${name}.txt.started`)),
        `${target}: timeout must exercise a running ${name} segment`);
    }
    assert(result.stderr.includes("Not updating"), result.stderr);
    assert.equal(fs.readFileSync(document, "utf8"), original);
  }
}
