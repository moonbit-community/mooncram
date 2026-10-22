import assert from "node:assert/strict";
import * as fs from "node:fs";
import { delimiter, join, relative } from "node:path";
import {
  ROOT, EXIT_CODE, EXECUTABLE_SUFFIX, IMPORTS, MAIN_PACKAGE_CONFIG,
  SCRIPT_COMMAND, LOCAL_PACKAGE, block, copyExecutable, createCli,
  createEnvironment, createToolchain, findTool, formatImports,
  isolatedExecutable, quoteArgument, run, writeDocument, writePackage,
} from "./basic.mjs";

export function testToolchainSelection({ executable, target, directory, docs, project }) {
  const stub = join(project, "toolchain-double");
  writePackage(stub, formatImports([...IMPORTS, "moonbitlang/x/path"]) + MAIN_PACKAGE_CONFIG,
    fs.readFileSync(join(ROOT, "e2etests/fixtures/toolchain.mbt"), "utf8"));
  const artifact = JSON.parse(run([
    "moon", "-C", project, "run", "--build-only", "--target", "native", stub,
  ], { env: createEnvironment() }).stdout).artifacts_path[0];
  const a = createToolchain(join(directory, "toolchain A with spaces"), []);
  const b = createToolchain(join(directory, "toolchain B"), []);
  for (const bin of [a, b]) {
    for (const name of ["moon", "moonc", "moonrun", "moonx", "program"]) {
      copyExecutable(artifact, bin, name);
    }
  }
  const tool = (bin, name) => join(bin, name + EXECUTABLE_SUFFIX);
  // An absolute launcher permits a wholly isolated PATH, even for the Wasm CLI.
  const cli = createCli(isolatedExecutable(executable, target, findTool("moonrun")), project);
  const log = join(directory, "toolchain-calls.jsonl");
  const environment = path => {
    const env = createEnvironment();
    for (const key of Object.keys(env)) if (key.toUpperCase() === "PATH") delete env[key];
    return { ...env, PATH: path, MOONCRAM_TOOLCHAIN_LOG: log };
  };
  const calls = () => fs.existsSync(log)
    ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
  const invoke = (args, path = [a, b].join(delimiter), options = {}) => {
    fs.rmSync(log, { force: true });
    return cli(args, { env: environment(path), ...options });
  };
  const write = (name, body, module = "") => writeDocument(docs, `toolchain-${name}.md`, block(body, module));
  const script = write("script", `$ ${SCRIPT_COMMAND}\nfixture output\n`);
  const remote = write("remote", "$ moonx fixture/tool@1.2.3\nfixture output\n");
  const both = write("both", `$ ${SCRIPT_COMMAND}\nfixture output\n$ moonx fixture/tool@1.2.3\nfixture output\n`);

  for (const [first, second] of [[a, b], [b, a]]) {
    invoke(["test", both], [first, second].join(delimiter));
    assert.deepEqual(calls().map(call => call.tool),
      [tool(first, "moon"), tool(first, "moonrun"), tool(first, "moonx")]);
  }

  // Segment PATH overrides reach both build and run, but tool selection remains
  // based on startup PATH across pipelines, cases, working dirs and documents.
  const overridden = write("overridden",
    `$ PATH=${quoteArgument(b)} ${SCRIPT_COMMAND}\nfixture output\n` +
    `$ PATH=${quoteArgument(b)} moonx fixture/tool@1.2.3\nfixture output\n` +
    `$ PATH=${quoteArgument(b)} ${SCRIPT_COMMAND}|PATH=${quoteArgument(b)} moonx fixture/tool@1.2.3\nfixture output\n` +
    "$ moonx fixture/tool@1.2.3\nfixture output\n");
  invoke(["test", overridden, both]);
  const assigned = calls().filter(call => call.path === b);
  assert.equal(assigned.length, 6);
  assert(assigned.every(call => call.tool.startsWith(a + "/") || call.tool.startsWith(a + "\\")));
  const inherited = calls().filter(call => call.path !== b);
  assert.deepEqual(inherited.map(call => call.path), Array(4).fill([a, b].join(delimiter)));
  assert(inherited.every(call => call.tool === tool(a, "moon") || call.tool === tool(a, "moonrun") || call.tool === tool(a, "moonx")));

  // If each document or case resolved again, removing A's anchor would switch
  // the next remote call to B. The selected moonx must keep running from A.
  const pinned = write("pinned", `$ moonx fixture/tool@1.2.3 remove-file ${quoteArgument(tool(a, "moon"))}\nfixture output\n`);
  try {
    invoke(["test", pinned, remote]);
    assert.deepEqual(calls().map(call => call.tool), Array(2).fill(tool(a, "moonx")));
  } finally {
    copyExecutable(artifact, a, "moon");
  }

  // Relative and empty entries refer to startup cwd even though the script's
  // working directory is the document directory.
  invoke(["test", both], [relative(project, a), b].join(delimiter));
  assert(calls().every(call => call.tool === tool(a, "moon") || call.tool === tool(a, "moonrun") || call.tool === tool(a, "moonx")));
  invoke(["test", both], delimiter + b, { cwd: a });
  assert.deepEqual(calls().map(call => call.tool), [tool(a, "moon"), tool(a, "moonrun"), tool(a, "moonx")]);
  assert(calls().every(call => call.cwd === fs.realpathSync(docs)));
  const changedCwd = write("cwd", `#cwd(${b})\n$ moonx fixture/tool@1.2.3\nfixture output\n`);
  invoke(["test", changedCwd]);
  assert.deepEqual(calls().map(call => [call.tool, call.cwd]), [[tool(a, "moonx"), b]]);

  const links = join(directory, "toolchain links with spaces");
  fs.mkdirSync(links);
  let linked = false;
  try {
    fs.symlinkSync(tool(a, "moon"), tool(links, "moon"), "file");
    linked = true;
  } catch (error) {
    if (process.platform !== "win32" || error.code !== "EPERM") throw error;
    console.log(`${target}: file symlink check skipped (Windows requires symlink privilege)`);
  }
  if (linked) {
    invoke(["test", both], links);
    assert.deepEqual(calls().map(call => call.tool), [tool(a, "moon"), tool(a, "moonrun"), tool(a, "moonx")]);
    const moonx = tool(a, "moonx");
    fs.renameSync(moonx, moonx + ".saved");
    try {
      fs.symlinkSync(tool(a, "moon"), moonx, "file");
      invoke(["test", remote], links);
      assert.deepEqual(calls().map(call => call.tool), [moonx]);
    } finally {
      fs.rmSync(moonx, { force: true });
      fs.renameSync(moonx + ".saved", moonx);
    }
  }

  for (const [name, document, expectedCalls] of [["moonrun", script, [tool(a, "moon")]], ["moonx", remote, []]]) {
    const missing = tool(a, name);
    fs.renameSync(missing, missing + ".disabled");
    try {
      const result = invoke(["test", document], [a, b].join(delimiter), { expected: EXIT_CODE.ERROR });
      assert(result.stderr.includes(`failed to start '${missing}'`), result.stderr);
      assert(result.stderr.includes(`tool: ${missing}`), result.stderr);
      assert(result.stderr.includes("phase: start"), result.stderr);
      assert(!result.stderr.includes("available on PATH"), result.stderr);
      assert.deepEqual(calls().map(call => call.tool), expectedCalls);
    } finally {
      fs.renameSync(missing + ".disabled", missing);
    }
  }

  // Native-only cases need neither companion, while scripts need no moonx and
  // remote-only cases need no moonrun. All still require a valid anchor.
  const native = write("native", `$ ${LOCAL_PACKAGE}\nfixture output\n`, "mooncram/integration");
  for (const names of [["moonx"], ["moonrun"], ["moonrun", "moonx"]]) {
    for (const name of names) fs.renameSync(tool(a, name), tool(a, name) + ".disabled");
    try {
      const document = names.length === 2 ? native : names[0] === "moonx" ? script : remote;
      invoke(["test", document, "--target", "native"]);
      const expected = document === native ? ["moon", "program"] : document === script ? ["moon", "moonrun"] : ["moonx"];
      assert.deepEqual(calls().map(call => call.tool), expected.map(name => tool(a, name)));
    } finally {
      for (const name of names) fs.renameSync(tool(a, name) + ".disabled", tool(a, name));
    }
  }

  // Reject the first executable's incomplete installation instead of trying B.
  for (const name of ["outside-bin", "include", "lib/core", "moonc"]) {
    const root = join(directory, `invalid-toolchain-${name.replaceAll("/", "-")}`);
    const bin = name === "outside-bin" ? root : join(root, "bin");
    fs.mkdirSync(bin, { recursive: true });
    const moon = copyExecutable(artifact, bin, "moon");
    if (name !== "include") fs.mkdirSync(join(root, "include"));
    if (name !== "lib/core") fs.mkdirSync(join(root, "lib/core"), { recursive: true });
    if (name !== "moonc") copyExecutable(artifact, bin, "moonc");
    const result = invoke(["test", remote], [bin, b].join(delimiter), { expected: EXIT_CODE.ERROR });
    assert(result.stderr.includes("failed to resolve MoonBit toolchain"), result.stderr);
    assert(result.stderr.includes(`tool: ${fs.realpathSync(moon)}`), result.stderr);
    assert(result.stderr.includes("phase: resolve"), result.stderr);
    if (name === "include" || name === "lib/core") {
      const required = join(fs.realpathSync(root), name);
      assert(result.stderr.includes(`cause: expected toolchain directory '${required}'`), result.stderr);
    }
    assert.deepEqual(calls(), []);
    // These commands must not even validate the installation's structure.
    for (const args of [["check", both], ["--help"], ["docs", "execution"]]) {
      invoke(args, bin);
      assert.deepEqual(calls(), []);
    }
  }

  // No implicit executable-directory search, including beside moonrun.exe.
  const empty = join(directory, "empty-toolchain-path");
  fs.mkdirSync(empty);
  for (const path of [empty, ""]) {
    const result = invoke(["test", remote], path, { expected: EXIT_CODE.ERROR });
    assert(result.stderr.includes("on startup PATH"), result.stderr);
    assert.deepEqual(calls(), []);
  }
  const noPath = environment(a);
  delete noPath.PATH;
  // Windows libuv fills in missing PATH from the parent process. Remove every
  // spelling from the parent during this synchronous launch, then restore it.
  const parentPaths = Object.entries(process.env).filter(([key]) => key.toUpperCase() === "PATH");
  try {
    for (const [key] of parentPaths) delete process.env[key];
    const missingPath = invoke(["test", remote], a, { env: noPath, expected: EXIT_CODE.ERROR });
    assert(missingPath.stderr.includes("on startup PATH"), missingPath.stderr);
    assert(missingPath.stderr.includes("phase: resolve"), missingPath.stderr);
    assert.deepEqual(calls(), []);
  } finally {
    for (const [key, value] of parentPaths) process.env[key] = value;
  }

  // A long unsuccessful search deterministically spends the deadline before
  // reaching A. Resolving the installation shares the first case's timeout.
  const slowPath = [...Array(1024).fill("absent"), a].join(delimiter);
  const timedOut = invoke(["test", remote, "--timeout-ms", "1"], slowPath, { expected: EXIT_CODE.ERROR });
  assert(timedOut.stderr.includes("timed out after 1 ms"), timedOut.stderr);
  assert(timedOut.stderr.includes("phase: resolve"), timedOut.stderr);
  assert.deepEqual(calls(), []);
  console.log(`${target}: fixed toolchain selection, PATH snapshots, companion isolation, lazy requirements and resolution deadline passed`);
}
