#!/usr/bin/env node
/**
 * Exercise both CLI backends with real MoonBit scripts and packages.
 *
 * Run from any directory: node tests/integration.mjs [--target wasm|native]
 * Requires Node.js, moon, moonx, moonrun, and the native C toolchain.
 */

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const ROOT = fileURLToPath(new URL("../", import.meta.url));
const PROGRAM = fs.readFileSync(join(ROOT, "tests/fixtures/program.mbt"), "utf8");
const DIRECTORY_LINK_TYPE = process.platform === "win32" ? "junction" : "dir";
const IMPORTS = [
  "moonbitlang/async",
  "moonbitlang/async/fs",
  "moonbitlang/async/stdio",
  "moonbitlang/core/env",
  "moonbitlang/x/sys",
];

function run(command, { cwd = ROOT, env = process.env, expected = 0, timeout = 120_000 } = {}) {
  const [program, ...args] = command.map(String);
  const result = spawnSync(program, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: ["inherit", "pipe", "pipe"],
    timeout,
    killSignal: "SIGKILL",
    maxBuffer: Infinity,
    windowsHide: true,
  });
  if (result.error) throw result.error;
  assert.equal(
    result.status,
    expected,
    `${JSON.stringify(command)}: expected exit ${expected}, got ${result.status}` +
      `\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
  return result;
}

function block(body, config = {}) {
  const info = Object.keys(config).length ? " " + JSON.stringify(config) : "";
  return "```mooncram" + info + "\n" + body + "```\n";
}

// Mooncram treats backslashes as escapes inside double-quoted arguments.
function quoteArgument(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function exercise(target) {
  const artifact = JSON.parse(run([
    "moon", "run", "--build-only", "--target", target, ".",
  ]).stdout).artifacts_path[0];
  const executable = target === "wasm" ? ["moonrun", artifact, "--"] : [artifact];
  const env = {
    ...process.env,
    MODE: "parent",
    MOONCRAM_INHERITED: "yes",
    // Keep standalone fixture builds local, including in read-only-home CI.
    MOON_DEP_CACHE: "off",
    MOON_BUILD_CACHE: "off",
  };
  fs.mkdirSync(join(ROOT, "_build"), { recursive: true });
  const directory = fs.mkdtempSync(join(ROOT, "_build", `integration-${target}-`));
  try {
    const docs = join(directory, "docs");
    fs.mkdirSync(docs);
    const project = join(directory, "project");
    const packageDir = join(project, "cmd");
    fs.mkdirSync(packageDir, { recursive: true });
    fs.writeFileSync(
      join(project, "moon.mod"),
      'name = "mooncram/integration"\n' +
        'import { "moonbitlang/async@0.22.4", "moonbitlang/x@0.5.5" }\n',
    );
    fs.symlinkSync(join(ROOT, ".mooncakes"), join(project, ".mooncakes"), DIRECTORY_LINK_TYPE);
    const imports = "import {\n" + IMPORTS.map(item => `  "${item}",\n`).join("") + "}\n";
    fs.writeFileSync(join(packageDir, "moon.pkg"), imports + 'options("is-main": true)\n');
    fs.writeFileSync(join(packageDir, "main.mbt"), PROGRAM);
    const scriptImports = imports
      .replaceAll("moonbitlang/async", "moonbitlang/async@0.22.4")
      .replaceAll("moonbitlang/x/sys", "moonbitlang/x@0.5.5/sys");
    fs.writeFileSync(join(docs, "program with space.mbtx"), scriptImports + PROGRAM);
    fs.writeFileSync(join(docs, "input.txt"), "stdin contents\n");
    fs.writeFileSync(join(docs, "relative.txt"), "cwd contents\n");
    const script = '"./program with space.mbtx"';
    const local = "../project/cmd";

    function cli(args, options = {}) {
      return run([...executable, ...args], { cwd: docs, env, ...options });
    }

    assert(cli(["--help"]).stdout.includes("Usage: mooncram"));
    assert(cli(["update", "--help"]).stdout.includes("dry-run"));
    assert(cli(["--version"]).stdout.includes("0.0.1"));
    cli(["test", "--timeout-ms", "0"], { expected: 2 });
    cli(["test", "--target", "js"], { expected: 2 });
    cli(["test", "--color", "invalid"], { expected: 2 });
    cli(["test", "--dry-run"], { expected: 2 });
    cli(["test", "missing.md"], { expected: 2 });
    const empty = join(docs, "empty.md");
    fs.writeFileSync(empty, "No test blocks.\n");
    assert(cli(["test", empty], { expected: 2 }).stderr.includes("no mooncram cases"));

    const good = join(docs, "pass.md");
    let content = block(`$ ${script} hello\nHello, Moon Bit!\n`);
    for (const program of [script, local]) {
      content += block(
        `$ ${program} args 'Moon Bit' "a'b" '' '$HOME' '*' '|' --version\n` +
          '["Moon Bit","a\'b","","$HOME","*","|","--version"] (equal)\n',
      );
      const pathArguments = [String.raw`C:\Moon Bit\file.txt`, String.raw`\\server\share\file.txt`, 'a"b\\c'];
      content += block(
        `$ ${program} args ${pathArguments.map(quoteArgument).join(" ")}\n` +
          `${JSON.stringify(pathArguments)} (equal)\n`,
      );
      content += block(
        `$ ${program} context\ntest\nyes\ncwd contents\nstdin contents\n\n` +
          `$ ${program} context\ntest\nyes\ncwd contents\nstdin contents\n`,
        { stdin: "./input.txt", env: { MODE: "test" } },
      );
      content += block(`$ ${program} echo\n`);
      content += block(`$ ${program} setup\n\n$ ${program} read\nside effect preserved\n`);
      content += block(`$ ${program} crlf\none\ntwo\n`);
      content += block(`$ ${program} streams\none\nthree\n[2]\n`);
      content += block(`$ ${program} streams\ntwo\n[2]\n`, { stream: "stderr" });
      content += block(`$ ${program} streams\none\ntwo\nthree\n[2]\n`, { stream: "merged" });
    }
    content += block(`$ ${local} hello\nHello, Moon Bit!\n`, {
      target: target === "native" ? "wasm" : "native",
    });
    content += block(`$ ${local} large\no* (glob)\n`);
    content += block(`$ ${local} large\ne* (glob)\n`, { stream: "stderr" });
    fs.writeFileSync(good, content);
    let result = cli(["test", good, "--target", target, "--color", "never"]);
    assert(result.stdout.includes("0 failed, 0 errors"));
    assert(!result.stdout.includes("\x1b"));
    console.log(`${target}: scripts, packages, args, cwd, env, stdin, streams, large output passed`);

    const failed = join(docs, "failure.md");
    fs.writeFileSync(failed, block(`$ ${local} streams\nwrong\n`));
    result = cli(["test", failed, "--target", target], { expected: 1 });
    assert(result.stdout.includes("failure.md:2"));
    assert(result.stdout.includes("-wrong") && result.stdout.includes("+one"));
    assert(result.stdout.includes("expected 0, actual 2"));
    assert(result.stdout.includes("diagnostic stderr\ntwo"));
    assert(cli(["test", failed, "--color", "always"], { expected: 1 }).stdout.includes("\x1b"));

    const update = join(docs, "update.md");
    const nested = block(`$ ${script} special\nold\n\n$ ${script} hello\nHello,* (glob)\n`);
    const source = "😀 Intro\n\n" + nested.replace(/\n+$/, "").split("\n")
      .map((line, i) => (i === 0 ? "> - " : ">   ") + line).join("\n") +
      "\n\n" + block(`$ ${local} crlf\no* (glob)\nwrong\n`) + "Unchanged tail";
    const original = Buffer.from(source.replaceAll("\n", "\r\n"));
    fs.writeFileSync(update, original);
    result = cli(["update", update, "--dry-run", "--target", target]);
    assert(result.stdout.includes("would update 2") && result.stdout.includes("(updated)"));
    assert.deepEqual(fs.readFileSync(update), original);
    cli(["update", update, "--target", target]);
    const updated = fs.readFileSync(update);
    const updatedText = updated.toString("utf8");
    assert(updatedText.startsWith("😀 Intro\r\n\r\n> - ```mooncram\r\n"));
    assert(updated.includes("Hello,* (glob)\r\n") && updated.includes("o* (glob)\r\n"));
    assert(updated.includes("(escaped)") && updated.includes("(no-eol)"));
    assert(updatedText.endsWith("Unchanged tail"));
    assert(!updatedText.replaceAll("\r\n", "").includes("\n"));
    cli(["test", update, "--target", target]);
    cli(["update", update, "--target", target]);
    assert.deepEqual(fs.readFileSync(update), updated);
    assert(!fs.readdirSync(docs).some(name => name.startsWith(".mooncram-")));
    console.log(`${target}: diagnostics, dry-run, local updates, escaping, pattern preservation passed`);

    const badPackage = join(project, "bad");
    fs.mkdirSync(badPackage);
    fs.writeFileSync(join(badPackage, "moon.pkg"), 'options("is-main": true)\n');
    fs.writeFileSync(join(badPackage, "main.mbt"), "fn main { nonexistent_function() }\n");
    fs.writeFileSync(join(docs, "bad.mbtx"), "fn main { nonexistent_function() }\n");
    const library = join(project, "library");
    fs.mkdirSync(library);
    fs.writeFileSync(join(library, "moon.pkg"), "");
    fs.writeFileSync(join(library, "lib.mbt"), "pub fn value() -> Int { 1 }\n");
    const errorDoc = join(docs, "error.md");
    for (const badCase of [
      "$ ../project/bad\n",
      "$ ./bad.mbtx\n",
      "$ ../project/library\n",
      "$ ./missing.mbtx\n",
      `$ ${quoteArgument(process.execPath)} hello\n`,
      `$ ${local} invalid-utf8\n`,
    ]) {
      const originalError = block(`$ ${local} hello\nwrong\n\n` + badCase);
      fs.writeFileSync(errorDoc, originalError);
      result = cli(["update", errorDoc, "--target", target], { expected: 2 });
      assert.equal(fs.readFileSync(errorDoc, "utf8"), originalError);
      assert(result.stderr.includes("Not updating"));
      if (badCase.includes("bad")) {
        assert(result.stderr.includes("build failed"));
      }
    }
    fs.writeFileSync(errorDoc, block(`$ ${local} hello\nwrong\n\n$ ${local} hello | cat\n`));
    const before = fs.readFileSync(errorDoc);
    assert(cli(["update", errorDoc], { expected: 2 }).stderr.includes("shell operator"));
    assert.deepEqual(fs.readFileSync(errorDoc), before);

    // A deadline covers the build and executable together. Both managed
    // native artifacts and moonrun processes must be cancelled promptly.
    const slow = join(docs, "slow.md");
    for (const backend of ["wasm", "native"]) {
      fs.writeFileSync(slow, block(`$ ${local} slow\n`, { target: backend, timeout_ms: 350 }));
      const start = performance.now();
      result = cli(["test", slow], { expected: 2 });
      assert(performance.now() - start < 4000);
      assert(result.stderr.includes("timed out after 350 ms"));
    }
    assert(!fs.existsSync(join(docs, "slow-finished.txt")));

    const mutate = join(docs, "mutate.md");
    fs.writeFileSync(mutate, block(`$ ${local} mutate\nwrong\n`));
    result = cli(["update", mutate, "--target", target], { expected: 2 });
    assert(result.stderr.includes("source changed"));
    assert.equal(fs.readFileSync(mutate, "utf8"), "changed by command\n");

    const scan = join(directory, "scan");
    fs.mkdirSync(scan);
    for (const ignored of [".hidden", "_build", "target"]) {
      const child = join(scan, ignored);
      fs.mkdirSync(child);
      fs.writeFileSync(join(child, "ignored.md"), "```mooncram\ninvalid\n```\n");
    }
    fs.writeFileSync(join(scan, ".hidden.md"), "```mooncram\ninvalid\n```\n");
    fs.symlinkSync(scan, join(scan, "cycle"), DIRECTORY_LINK_TYPE);
    fs.writeFileSync(join(scan, "a.md"), block(`$ ${quoteArgument(packageDir)} setup\n`));
    fs.writeFileSync(join(scan, "z.md"), block(`$ ${quoteArgument(packageDir)} read\nside effect preserved\n`));
    result = cli(["test", scan, join(scan, "a.md"), "--target", target]);
    assert(result.stdout.includes("2 cases"));
    result = cli(["test", "--target", target], { cwd: scan });
    assert(result.stdout.includes("2 cases"));
    // Other work gives cancelled processes time to reveal stray side effects.
    assert(!fs.existsSync(join(docs, "slow-finished.txt")));
    console.log(`${target}: error isolation, timeout, concurrent edit, scan order and symlink checks passed`);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
  }
}

function main() {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        help: { type: "boolean", short: "h" },
        target: { type: "string", multiple: true },
      },
    }));
    for (const target of values.target ?? []) {
      if (target !== "wasm" && target !== "native") {
        throw new Error(`invalid target ${JSON.stringify(target)}: choose wasm or native`);
      }
    }
  } catch (error) {
    console.error(`integration.mjs: ${error.message}`);
    process.exitCode = 2;
    return;
  }
  if (values.help) {
    console.log(`Usage: node tests/integration.mjs [--target wasm|native]

Exercise both CLI backends with real MoonBit scripts and packages.
Requires Node.js, moon, moonx, moonrun, and the native C toolchain.

Options:
  -h, --help            Show this help message and exit.
  --target wasm|native  Run one backend; repeat to select multiple (default: both).`);
    return;
  }
  for (const target of values.target ?? ["wasm", "native"]) {
    exercise(target);
  }
  console.log("All CLI integration checks passed.");
}

main();
