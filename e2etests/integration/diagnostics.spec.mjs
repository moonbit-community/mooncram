import assert from "node:assert/strict";
import * as fs from "node:fs";
import { delimiter, join } from "node:path";
import { performance } from "node:perf_hooks";
import {
  ROOT, EXIT_CODE, CANCELLATION_LIMIT_MS, IMPORTS, MAIN_PACKAGE_CONFIG,
  LOCAL_PACKAGE, SCRIPT_COMMAND, SCRIPT_FILENAME, run, formatImports, createEnvironment, copyExecutable,
  copyTool, createToolchain, createCli, isolatedExecutable, writePackage, writeDocument, block,
} from "./basic.mjs";

export function testBuildDiagnostics({ executable, docs, project, directory, target }) {
  const helper = join(project, "build-double");
  writePackage(helper, formatImports(IMPORTS) + MAIN_PACKAGE_CONFIG,
    fs.readFileSync(join(ROOT, "e2etests/fixtures/moon.mbt"), "utf8"));
  const artifact = JSON.parse(run([
    "moon", "-C", project, "run", "--build-only", "--target", "native", helper,
  ], { env: createEnvironment() }).stdout).artifacts_path[0];
  const tools = createToolchain(join(directory, "build-diagnostic-tools"), ["moonc"]);
  const moon = copyExecutable(artifact, tools, "moon");
  // Keep the CLI launcher separate from the tool entries under test, including
  // when the selected installation has no moonrun on Windows.
  const runner = copyTool("moonrun", tools, "mooncram-test-runner");
  const cli = createCli(isolatedExecutable(executable, target, runner), project);
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  for (const [program, label] of [[LOCAL_PACKAGE, LOCAL_PACKAGE.slice(6)], [SCRIPT_COMMAND, `./${SCRIPT_FILENAME}`]]) {
    // Even an assertion matching the compiler's status cannot turn a build
    // failure into a program result. Invalid artifacts must never run setup.
    const original = block(`$ ${program} setup\n[9]\n`);
    const doc = writeDocument(docs, "build-diagnostic.md", original);
    for (const mode of ["fail", "invalid", "slow"]) {
      const env = { ...createEnvironment(), MOONCRAM_TEST_BUILD_MODE: mode };
      env.PATH = tools + delimiter + env.PATH;
      const args = ["update", doc, "--target", target];
      if (mode === "slow") args.push("--timeout-ms", "500");
      const start = performance.now();
      const result = cli(args, { env, expected: EXIT_CODE.ERROR });
      assert(performance.now() - start < CANCELLATION_LIMIT_MS, result.stderr);
      assert(result.stderr.startsWith(`ERROR ${fs.realpathSync(doc)}:2: `), result.stderr);
      assert(result.stderr.includes("phase: build"), result.stderr);
      assert(result.stderr.includes(`segment: 1/1 (${label})`), result.stderr);
      assert(result.stderr.includes(`tool: ${moon}`), result.stderr);
      assert.equal(fs.readFileSync(doc, "utf8"), original);
      assert(!fs.existsSync(sideEffect), "program ran despite a failed build preflight");
      if (mode === "fail") {
        assert(result.stderr.includes("build failed (exit 9)"), result.stderr);
        assert.equal(result.stderr.split("build stdout detail").length, 2);
        assert.equal(result.stderr.split("compiler stderr detail").length, 2);
      } else if (mode === "invalid") {
        assert(result.stderr.includes("invalid build artifact JSON"), result.stderr);
        assert.equal(result.stderr.split("not build JSON").length, 2);
        assert.equal(result.stderr.split("artifact stderr detail").length, 2);
      } else {
        assert(result.stderr.includes("timed out after 500 ms"), result.stderr);
        assert(result.stderr.includes("build started"), result.stderr);
        assert(result.stderr.includes("partial"), result.stderr);
      }
    }
  }
  console.log(`${target}: build errors, invalid artifacts, logs and build-stage timeouts passed`);
}
