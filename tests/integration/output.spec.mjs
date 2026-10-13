import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import {
  EXIT_CODE,
  CANCELLATION_LIMIT_MS,
  ANSI_ESCAPE,
  CRLF,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  block,
  writeDocument,
  quotedListItem,
} from "./basic.mjs";

export function testDualStreams({ cli, docs, target }) {
  const cases = [SCRIPT_COMMAND, LOCAL_PACKAGE].flatMap(program => [
    [`${program} streams`, "@STDOUT\none\nthree\n@STDERR\ntwo\n[2]\n"],
    [`${program} dual-tail`, "@STDERR\nerr (no-eol)\n\n@STDOUT\nout (no-eol)\n"],
    [`${program} hello`, "@STDOUT\nHello,* (glob)\n@STDERR (empty)\n"],
    [`${program} streams 1>/dev/null | ${LOCAL_PACKAGE} echo`, "@STDOUT (empty)\n@STDERR\ntwo\n[2]\n"],
    [`${program} streams 2>&1 | ${LOCAL_PACKAGE} echo`, "@STDOUT\none\ntwo\nthree\n@STDERR (empty)\n[2]\n"],
    [`${program} streams 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo`, "@STDERR (empty)\n@STDOUT\ntwo\n[2]\n"],
    [`${program} dual-special`, '@STDOUT\n"@STDERR (ignore)" (escaped)\n@STDERR\n"@STDOUT" (escaped)\n'],
    [`${program} large`, "@STDOUT (ignore)\n@STDERR\ne+ (regex)\n"],
  ]);
  cases.push(
    [`${LOCAL_PACKAGE} streams|${SCRIPT_COMMAND} relay middle|${LOCAL_PACKAGE} relay last`,
      "@STDOUT\none\nthree\n@STDERR\ntwo\nmiddle\nlast\n[2]\n"],
    [`${LOCAL_PACKAGE} hello|${SCRIPT_COMMAND} relay-tail middle|${LOCAL_PACKAGE} relay-tail last`,
      "@STDOUT\nHello, Moon Bit!\n@STDERR\nmiddlelast (no-eol)\n"],
    [`${LOCAL_PACKAGE} streams 2>&1|${SCRIPT_COMMAND} relay middle|${LOCAL_PACKAGE} relay last 1>/dev/null 2>&1 | ${LOCAL_PACKAGE} echo`,
      "@STDOUT\nlast\n@STDERR\nmiddle\n[2]\n"],
    [`${LOCAL_PACKAGE} large`, "@STDOUT\no* (glob)\n@STDERR\ne* (glob)\n"],
  );
  const passing = writeDocument(docs, "dual-pass.md",
    cases.map(([command, body]) => block(`$ ${command}\n${body}`)).join("\n"));
  cli(["test", passing, "--target", target]);

  // Detect either stream independently, even when the other matches.
  for (const stream of ["STDOUT", "STDERR"]) {
    const body = stream === "STDOUT" ? "@STDOUT\nwrong\n@STDERR\ntwo\n[2]\n" :
      "@STDOUT\none\nthree\n@STDERR\nwrong\n[2]\n";
    const failed = writeDocument(docs, "dual-failure.md", block(`$ ${LOCAL_PACKAGE} streams\n${body}`));
    const report = cli(["test", failed, "--target", target], { expected: EXIT_CODE.FAILURE }).stdout;
    assert(report.includes(`expected @${stream}`) && report.includes("-wrong"), report);
    if (stream === "STDERR") assert(!report.includes("diagnostic stderr"), report);
    else assert(report.includes("diagnostic stderr\ntwo"), report);
  }

  const original = (quotedListItem(block(
    `$ ${SCRIPT_COMMAND} streams\n@STDERR (ignore)\n\n@STDOUT (empty)\n`)) + "\n\n" +
    block(`$ ${LOCAL_PACKAGE} dual-special\n@STDOUT (empty)\n@STDERR (empty)\n`) +
    block(`$ ${LOCAL_PACKAGE} streams\n@STDOUT\no* (glob)\nthree\n@STDERR\ntwo\n`)).replaceAll("\n", CRLF);
  const update = writeDocument(docs, "dual-update.md", original);
  const dry = cli(["update", update, "--dry-run", "--target", target]);
  assert(dry.stdout.includes("would update 3"), dry.stdout);
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  const updated = fs.readFileSync(update, "utf8");
  assert(updated.includes('@STDOUT\r\n"@STDERR (ignore)" (escaped)\r\n@STDERR\r\n"@STDOUT" (escaped)'));
  assert(updated.includes("@STDERR (ignore)\r\n>   \r\n>   @STDOUT\r\n>   one\r\n>   three\r\n>   [2]"));
  assert(updated.includes("o* (glob)\r\nthree\r\n@STDERR\r\ntwo\r\n[2]"));
  assert(!updated.replaceAll(CRLF, "").includes("\n"));
  cli(["test", update, "--target", target]);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), updated);

  // Ignoring content still captures and validates UTF-8, and keeps deadlines.
  const paired = "@STDOUT (ignore)\n@STDERR (ignore)\n";
  for (const mode of ["invalid-utf8", "invalid-stderr", "slow dual-slow.txt"]) {
    const before = block(`$ ${LOCAL_PACKAGE} hello\n@STDOUT\nwrong\n@STDERR (empty)\n` +
      `$ ${LOCAL_PACKAGE} ${mode}\n${paired}`);
    const error = writeDocument(docs, "dual-error.md", before);
    const args = ["update", error, "--target", target];
    if (mode.startsWith("slow")) args.push("--timeout-ms", "1000");
    const start = performance.now();
    const result = cli(args, { expected: EXIT_CODE.ERROR });
    assert(performance.now() - start < CANCELLATION_LIMIT_MS, result.stderr);
    assert(result.stderr.includes("Not updating"), result.stderr);
    if (mode.startsWith("slow")) assert(result.stderr.includes("timed out"), result.stderr);
    assert.equal(fs.readFileSync(error, "utf8"), before);
    const dry = cli([...args, "--dry-run"], { expected: EXIT_CODE.ERROR });
    assert(!dry.stdout.includes(`${error} (updated)`));
  }
  // Validate paired syntax for the entire document before running any case.
  const sideEffect = join(docs, "side-effect.txt");
  fs.rmSync(sideEffect, { force: true });
  const malformed = block(`$ ${LOCAL_PACKAGE} setup\n$ ${LOCAL_PACKAGE} hello\n@STDOUT\n`);
  const parseError = writeDocument(docs, "dual-parse-error.md", malformed);
  const result = cli(["update", parseError, "--target", target], { expected: EXIT_CODE.ERROR });
  assert(result.stderr.includes("dual-parse-error.md:4:"), result.stderr);
  assert(!fs.existsSync(sideEffect));
  assert.equal(fs.readFileSync(parseError, "utf8"), malformed);
  console.log(`${target}: paired stdout/stderr assertions, routing, updates, ignored capture and timeout checks passed`);
}

export function testDiagnostics({ cli, docs, target }) {
  const failed = writeDocument(docs, "failure.md", block(`$ ${LOCAL_PACKAGE} streams\nwrong\n`));
  const result = cli(["test", failed, "--target", target], { expected: EXIT_CODE.FAILURE });
  assert(result.stdout.includes("failure.md:2"));
  assert(result.stdout.includes("-wrong") && result.stdout.includes("+one"));
  assert(result.stdout.includes("expected 0, actual 2"));
  assert(result.stdout.includes("diagnostic stderr\ntwo"));
  assert(cli(["test", failed, "--color", "always"], { expected: EXIT_CODE.FAILURE }).stdout.includes(ANSI_ESCAPE));
}

export function testEqualLiteral({ cli, docs, target }) {
  const line = "hello (equal)";
  fs.writeFileSync(join(docs, "equal-line.txt"), line + "\n");
  fs.writeFileSync(join(docs, "equal-tail.txt"), line);
  const cases = [SCRIPT_COMMAND, LOCAL_PACKAGE].flatMap(program => [
    [`${program} read-file equal-line.txt`, line],
    [`${program} read-file equal-tail.txt`, line + " (no-eol)"],
  ]);
  const source = expectation => block(cases.map(([command, output]) =>
    `$ ${command}\n${expectation(output)}\n`).join(""));
  const document = writeDocument(docs, "equal-literal.md", source(output => output));
  cli(["test", document, "--target", target]);

  fs.writeFileSync(document, source(output => output.replace(" (equal)", "")));
  const failure = cli(["test", document, "--target", target], { expected: EXIT_CODE.FAILURE });
  assert(failure.stdout.includes("4 cases, 4 failed, 0 errors"));
  cli(["update", document, "--target", target]);
  const updated = fs.readFileSync(document, "utf8");
  assert.equal(updated, source(output => output));
  cli(["test", document, "--target", target]);
  cli(["update", document, "--target", target]);
  assert.equal(fs.readFileSync(document, "utf8"), updated);

  const removedSuffix = writeDocument(docs, "equal-suffix.md",
    block(`$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit! (equal)\n`));
  cli(["test", removedSuffix, "--target", target], { expected: EXIT_CODE.FAILURE });
}
