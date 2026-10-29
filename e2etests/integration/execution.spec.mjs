import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import {
  ANSI_ESCAPE,
  SCRIPT_FILENAME,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  block,
  copyTool,
  createToolchain,
  isolatedExecutable,
  createCli,
  createEnvironment,
  quoteArgument,
  writeDocument,
  contextCase,
} from "./basic.mjs";

const PATH_ARGUMENTS = [
  String.raw`C:\Moon Bit\file.txt`,
  String.raw`\\server\share\file.txt`,
  'a"b\\c',
];

function argumentCases(program) {
  return block(
    `$ ${program} args 'Moon Bit' "a'b" '' '$HOME' '*' '|' --version\n` +
      '["Moon Bit","a\'b","","$HOME","*","|","--version"]\n',
  ) + block(
    `$ ${program} args ${PATH_ARGUMENTS.map(quoteArgument).join(" ")}\n` +
      `${JSON.stringify(PATH_ARGUMENTS)}\n`,
  ) + block(`$ ${program} args -- --target native\n["--","--target","native"]\n`);
}

function streamCases(program) {
  return block(`$ ${program} streams\none\nthree\n[2]\n`);
}

function programCases(program) {
  return [
    argumentCases(program),
    contextCase(program),
    block(`$ ${program} echo\n`),
    block(`$ ${program} check-eof\nEOF\n`),
    block(`$ ${program} setup\n\n$ ${program} read\nside effect preserved\n`),
    block(`$ ${program} crlf\none\ntwo\n`),
    streamCases(program),
    block(`$ ${program} split-utf8\n😀 (no-eol)\n`),
  ].join("");
}

function passingDocument() {
  return [
    block(`$ ${SCRIPT_COMMAND} hello\nHello, Moon Bit!\n`),
    ...[SCRIPT_COMMAND, LOCAL_PACKAGE].map(programCases),
    block(`$ ${LOCAL_PACKAGE} large\no* (glob)\n`),
  ].join("");
}

export function testPassingCases({ cli, docs, target }) {
  const good = writeDocument(docs, "pass.md", passingDocument());
  const result = cli(["test", good, "--target", target, "--color", "never"]);
  assert(result.stdout.includes("0 failed, 0 errors"));
  assert(!result.stdout.includes(ANSI_ESCAPE));
}

export function testScriptsWithoutMoonx({ executable, docs, directory, project, target }) {
  const tools = createToolchain(join(directory, "script-tools"), ["moon", "moonc"]);
  const runner = copyTool("moonrun", tools);
  const cli = createCli(isolatedExecutable(executable, target, runner), project);
  // The isolated PATH has no moonx or native compiler. Scripts must stay on
  // Wasm even when --target native is selected, for either CLI backend.
  const env = { ...createEnvironment(), PATH: tools };
  const workspace = join(directory, "script workspace");
  fs.mkdirSync(workspace);
  fs.copyFileSync(join(docs, SCRIPT_FILENAME), join(workspace, SCRIPT_FILENAME));
  fs.writeFileSync(join(workspace, "relative.txt"), "script cwd contents\n");
  const rewrittenLines = ['import { "moonbitlang/core/builtin" }', '', 'fn main { println("rebuilt after edit") }'];
  const rewritten = rewrittenLines.join("\n");
  const document = writeDocument(docs, "scripts-without-moonx.md", block(
    `#cwd(../script workspace)\n` +
    `$ ${SCRIPT_COMMAND} args '' -- 'with space'\n["","--","with space"]\n` +
    `$ MODE=script-temp ${SCRIPT_COMMAND} context\nscript-temp\nyes\nscript cwd contents\n` +
    `$ ${SCRIPT_COMMAND} context\nparent\nyes\nscript cwd contents\n` +
    `$ MODE=upstream ${SCRIPT_COMMAND} check-env MODE upstream | MODE=downstream ${SCRIPT_COMMAND} check-env-echo downstream\nupstream\n` +
    `$ ${SCRIPT_COMMAND} status 255 0\n[255]\n` +
    `$ ${SCRIPT_COMMAND} hello\nHello, Moon Bit!\n` +
    `$ ${SCRIPT_COMMAND} write-lines ${quoteArgument(SCRIPT_FILENAME)} ${rewrittenLines.map(quoteArgument).join(" ")}\n` +
    `$ ${SCRIPT_COMMAND}\nrebuilt after edit\n`,
  ));
  const result = cli(["test", document, "--target", "native"], { env });
  assert(result.stdout.includes("8 cases, 0 failed, 0 errors"), result.stdout);
  assert.equal(fs.readFileSync(join(workspace, SCRIPT_FILENAME), "utf8"), rewritten);
}
