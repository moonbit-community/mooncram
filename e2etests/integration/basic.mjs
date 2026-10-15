import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import { delimiter, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const BUILD_DIRECTORY = join(ROOT, "_build");
export const PROGRAM = fs.readFileSync(join(ROOT, "e2etests/fixtures/program.mbt"), "utf8");
export const TARGETS = ["wasm", "native"];
export const EXIT_CODE = { SUCCESS: 0, FAILURE: 1, ERROR: 2 };
const COMMAND_TIMEOUT_MS = 120_000;
export const CANCELLATION_LIMIT_MS = 4000;
export const ANSI_ESCAPE = "\x1b";
export const CRLF = "\r\n";
export const DIRECTORY_LINK_TYPE = process.platform === "win32" ? "junction" : "dir";
export const EXECUTABLE_SUFFIX = process.platform === "win32" ? ".exe" : "";
export const TOOL_DIRECTORIES = (process.env.PATH ?? "").split(delimiter);
export const CLEANUP_OPTIONS = { recursive: true, force: true, maxRetries: 3, retryDelay: 100 };
// Keep these dependency versions in sync with moon.mod.
const ASYNC_VERSION = "0.22.4";
const X_VERSION = "0.5.5";
const ASYNC_DEPENDENCY = `moonbitlang/async@${ASYNC_VERSION}`;
const X_DEPENDENCY = `moonbitlang/x@${X_VERSION}`;
export const IMPORTS = [
  "moonbitlang/async",
  "moonbitlang/async/fs",
  "moonbitlang/async/stdio",
  "moonbitlang/core/env",
  "moonbitlang/core/string",
  "moonbitlang/x/sys",
];
const PACKAGE_IMPORTS = formatImports(IMPORTS);
const SCRIPT_IMPORTS = PACKAGE_IMPORTS
  .replaceAll("moonbitlang/async", ASYNC_DEPENDENCY)
  .replaceAll("moonbitlang/x/sys", `${X_DEPENDENCY}/sys`);
const MODULE_CONFIG = 'name = "mooncram/integration"\n' +
  `import { "${ASYNC_DEPENDENCY}", "${X_DEPENDENCY}" }\n`;
export const MAIN_PACKAGE_CONFIG = 'options("is-main": true)\n';
export const INVALID_PROGRAM = "fn main { nonexistent_function() }\n";
export const LIBRARY_PROGRAM = "pub fn value() -> Int { 1 }\n";
export const SCRIPT_FILENAME = "program with space.mbtx";
export const SCRIPT_COMMAND = `moonx ${quoteArgument(`./${SCRIPT_FILENAME}`)}`;
export const LOCAL_PACKAGE_NAME = "mooncram/integration/cmd";
export const LOCAL_PACKAGE = `moonx ${LOCAL_PACKAGE_NAME}`;

export function run(command, {
  cwd = ROOT,
  env = process.env,
  expected = EXIT_CODE.SUCCESS,
  timeout = COMMAND_TIMEOUT_MS,
} = {}) {
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

export function formatImports(imports) {
  return "import {\n" + imports.map(item => `  "${item}",\n`).join("") + "}\n";
}

export function block(body, module = "mooncram/integration") {
  return "```mooncram" + (module ? ` ${module}` : "") + "\n" + body + "```\n";
}

// Mooncram treats backslashes as escapes inside double-quoted arguments.
export function quoteArgument(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("$", "\\$")}"`;
}

export function buildExecutable(target) {
  const artifact = JSON.parse(run([
    "moon", "run", "--build-only", "--target", target, ".",
  ]).stdout).artifacts_path[0];
  return target === "wasm" ? ["moonrun", artifact, "--"] : [artifact];
}

export function findTool(name) {
  const source = TOOL_DIRECTORIES.map(path => resolve(path, name + EXECUTABLE_SUFFIX))
    .find(path => fs.existsSync(path));
  assert(source, `missing ${name}`);
  return source;
}

export function copyExecutable(source, directory, name) {
  const destination = join(directory, name + EXECUTABLE_SUFFIX);
  fs.copyFileSync(source, destination);
  fs.chmodSync(destination, 0o755);
  return destination;
}

export function copyTool(name, directory, destinationName = name) {
  return copyExecutable(findTool(name), directory, destinationName);
}

export function isolatedExecutable(executable, target, runner) {
  return target === "wasm" ? [runner, ...executable.slice(1)] : executable;
}

export function createEnvironment() {
  return {
    ...process.env,
    MODE: "parent",
    MOONCRAM_INHERITED: "yes",
    // Keep standalone fixture builds local, including in read-only-home CI.
    MOON_DEP_CACHE: "off",
    MOON_BUILD_CACHE: "off",
  };
}

export function createCli(executable, project) {
  const env = createEnvironment();
  return (args, options = {}) => run([...executable, ...args], { cwd: project, env, ...options });
}

export function createTemporaryDirectory(target) {
  fs.mkdirSync(BUILD_DIRECTORY, { recursive: true });
  return fs.mkdtempSync(join(BUILD_DIRECTORY, `integration-${target}-`));
}

export function writePackage(directory, config, source, filename = "main.mbt") {
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(join(directory, "moon.pkg"), config);
  fs.writeFileSync(join(directory, filename), source);
}

function createProject(project) {
  fs.mkdirSync(project, { recursive: true });
  fs.writeFileSync(join(project, "moon.mod"), MODULE_CONFIG);
  // Moon may prune dependencies unused by this fixture module. A symlink here
  // would let fixture builds remove packages from the repository's cache.
  fs.cpSync(join(ROOT, ".mooncakes"), join(project, ".mooncakes"), { recursive: true });
  const packageDir = join(project, "cmd");
  writePackage(packageDir, PACKAGE_IMPORTS + MAIN_PACKAGE_CONFIG, PROGRAM);
  return packageDir;
}

export function createDocuments(docs) {
  fs.mkdirSync(docs);
  fs.writeFileSync(join(docs, SCRIPT_FILENAME), SCRIPT_IMPORTS + PROGRAM);
  fs.writeFileSync(join(docs, "relative.txt"), "cwd contents\n");
}

export function createFixtures(directory) {
  const docs = join(directory, "docs");
  createDocuments(docs);
  const project = join(directory, "project");
  const packageDir = createProject(project);
  return { directory, docs, project, packageDir };
}

export function writeDocument(directory, filename, content) {
  const path = join(directory, filename);
  fs.writeFileSync(path, content);
  return path;
}

export function contextCase(program) {
  return block(
    `$ ${program} context\nparent\nyes\ncwd contents\n\n` +
      `$ ${program} context\nparent\nyes\ncwd contents\n`,
  );
}

export function quotedListItem(content) {
  return content.replace(/\n+$/, "").split("\n")
    .map((line, i) => (i === 0 ? "> - " : ">   ") + line).join("\n");
}
