#!/usr/bin/env node
/**
 * Exercise both CLI backends with real MoonBit scripts and packages.
 *
 * Run from any directory: node e2etests/integration.mjs [--target wasm|native]
 * Requires Node.js, moon, moonx, moonrun, and the native C toolchain.
 */

import * as fs from "node:fs";
import { performance } from "node:perf_hooks";
import { parseArgs } from "node:util";
import {
  TARGETS,
  EXIT_CODE,
  CLEANUP_OPTIONS,
  buildExecutable,
  createCli,
  createTemporaryDirectory,
  createFixtures,
} from "./integration/basic.mjs";
import { testBuildDiagnostics } from "./integration/diagnostics.spec.mjs";
import { testCliArguments, testModuleResolution, testDirectoryScanning } from "./integration/cli.spec.mjs";
import { testDocs } from "./integration/docs.spec.mjs";
import { testDocExamples } from "./integration/doc-examples.spec.mjs";
import { testPassingCases, testScriptsWithoutMoonx } from "./integration/execution.spec.mjs";
import { testCheck, testGeneratedTargets } from "./integration/check.spec.mjs";
import {
  testExportRejection,
  testCommandEnvironment,
  testCommandEnvironmentCasing,
  testWorkingDirectories,
  testBuildEnvironment,
} from "./integration/environment.spec.mjs";
import { testRemotePackages } from "./integration/remote.spec.mjs";
import { testDualStreams, testDiagnostics, testEqualLiteral } from "./integration/output.spec.mjs";
import { testUpdates, testUpdateErrors, testConcurrentEdit } from "./integration/update.spec.mjs";
import {
  testPipelines,
  testRedirectionRejection,
  testPipelinePreflight,
  testPipelineStartupFailure,
  testPipelineCaptureFailure,
  testShellOperatorRejection,
} from "./integration/pipelines.spec.mjs";
import { assertNoSlowSideEffect, testTimeouts } from "./integration/timeouts.spec.mjs";

const ARGUMENT_OPTIONS = {
  help: { type: "boolean", short: "h" },
  target: { type: "string", multiple: true },
};
const HELP_TEXT = `Usage: node e2etests/integration.mjs [--target wasm|native]

Exercise both CLI backends with real MoonBit scripts and packages.
Requires Node.js, moon, moonx, moonrun, and the native C toolchain.

Options:
  -h, --help            Show this help message and exit.
  --target wasm|native  Run one backend; repeat to select multiple (default: both).`;

async function runIntegrationTests(target) {
  const executable = buildExecutable(target);
  const directory = createTemporaryDirectory(target);
  try {
    const fixtures = createFixtures(directory);
    const context = { ...fixtures, target, executable, cli: createCli(executable, fixtures.project) };

    testCliArguments(context);
    testDocs(context);
    testDocExamples(context);
    testCheck(context);
    testGeneratedTargets(context);
    console.log(`${target}: embedded docs, runnable doc examples, check validation, tool isolation and generated target timing passed`);
    testModuleResolution(context);
    testPassingCases(context);
    testScriptsWithoutMoonx(context);
    testExportRejection(context);
    testCommandEnvironmentCasing(context);
    testCommandEnvironment(context);
    testWorkingDirectories(context);
    testBuildEnvironment(context);
    testBuildDiagnostics(context);
    console.log(`${target}: scripts, packages, args, temporary environments, build env, cwd, stdin EOF, stdout and large dual-stream output passed`);

    testDualStreams(context);
    testDiagnostics(context);
    testUpdates(context);
    testEqualLiteral(context);
    console.log(`${target}: diagnostics, dry-run, local updates, escaping, pattern preservation passed`);

    testUpdateErrors(context);
    await testRemotePackages(context);
    testPipelines(context);
    testRedirectionRejection(context);
    testPipelinePreflight(context);
    testPipelineStartupFailure(context);
    testPipelineCaptureFailure(context);
    console.log(`${target}: mixed pipelines, raw bytes, large output, early exit, stderr order, pipefail, redirection rejection and updates passed`);
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
    await runIntegrationTests(target);
  }
  console.log("All CLI integration checks passed.");
}

await main();
