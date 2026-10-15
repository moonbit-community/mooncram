import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import {
  TARGETS,
  EXIT_CODE,
  CANCELLATION_LIMIT_MS,
  LOCAL_PACKAGE,
  block,
  writeDocument,
} from "./basic.mjs";

const CASE_TIMEOUT_MS = 350;
const SLOW_SIDE_EFFECT_FILENAME = "slow-finished.txt";

export function assertNoSlowSideEffect(docs) {
  assert(!fs.existsSync(join(docs, SLOW_SIDE_EFFECT_FILENAME)));
  assert(!fs.existsSync(join(docs, "dual-slow.txt")));
  assert(!fs.existsSync(join(docs, "build-timeout-finished.txt")));
  for (const segment of ["first", "middle", "last", "spawn", "capture"]) {
    assert(!fs.existsSync(join(docs, `slow-${segment}.txt`)));
  }
}

export function testTimeouts({ cli, docs }) {
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
  assertNoSlowSideEffect(docs);
}
