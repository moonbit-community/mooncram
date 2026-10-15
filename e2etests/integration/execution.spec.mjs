import assert from "node:assert/strict";
import {
  ANSI_ESCAPE,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  block,
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
  );
}

function streamCases(program) {
  return block(`$ ${program} streams\none\nthree\n[2]\n`);
}

function programCases(program) {
  return [
    argumentCases(program),
    contextCase(program),
    block(`$ ${program} echo\n`),
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
