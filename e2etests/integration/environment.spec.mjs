import assert from "node:assert/strict";
import * as fs from "node:fs";
import { delimiter, join } from "node:path";
import {
  EXIT_CODE,
  CRLF,
  DIRECTORY_LINK_TYPE,
  SCRIPT_COMMAND,
  LOCAL_PACKAGE,
  block,
  quoteArgument,
  findTool,
  createEnvironment,
  createDocuments,
  writeDocument,
} from "./basic.mjs";

export function testExportRejection({ cli, docs, target }) {
  const sideEffect = join(docs, "side-effect.txt");
  for (const invalid of [
    "export", "export A=x", "export A=", "export A='Moon Bit'", "export A=x B=y",
    "A=x export B=y", `export A=x|${LOCAL_PACKAGE} hello`,
    `${LOCAL_PACKAGE} hello|export A=x`, `${LOCAL_PACKAGE} hello|export A=x|${LOCAL_PACKAGE} hello`,
    "export A=x\noutput", "export A=x\n[0]",
  ]) {
    for (const prefix of ["", block(`$ ${LOCAL_PACKAGE} setup\n`)]) {
      const source = prefix + block(`$ ${invalid}\n`);
      const line = prefix ? 5 : 2;
      const bad = writeDocument(docs, "export-error.md", source);
      for (const operation of [
        ["check"], ["test", "--target", target],
        ["update", "--target", target], ["update", "--target", target, "--dry-run"],
      ]) {
        fs.rmSync(sideEffect, { force: true });
        const result = cli([...operation, bad], { expected: EXIT_CODE.ERROR });
        assert(result.stderr.includes(`export-error.md:${line}: command must start with moonx: export`), result.stderr);
        assert(result.stdout.includes("0 cases"), result.stdout);
        assert(!fs.existsSync(sideEffect), "a case ran before document validation completed");
        assert.equal(fs.readFileSync(bad, "utf8"), source);
      }
    }
  }
}

export function testCommandEnvironment({ cli, docs, target }) {
  const source = block(
    `$ MODE=temporary ${LOCAL_PACKAGE} check-env MODE temporary\ntemporary\n` +
    `$ ${LOCAL_PACKAGE} check-env MODE parent\nparent\n` +
    [SCRIPT_COMMAND, LOCAL_PACKAGE].map(program =>
      `$ MODE=\${MODE}-first VALUE="\${MODE}" MODE=\${MODE}-last ${program} check-env MODE '\${MODE}-last'\n\${MODE}-last\n` +
      `$ MODE=temporary VALUE="\${MODE}" ${program} check-env VALUE '\${MODE}'\n\${MODE}\n` +
      `$ A=new B="\${A}" ${program} check-env B '\${A}'\n\${A}\n` +
      `$ A=\${B} B=later ${program} check-env A '\${B}'\n\${B}\n` +
      `$ MODE= ${program} check-env MODE ''\n"" (escaped)\n` +
      `$ VALUE='Moon Bit|x=y' NESTED='\${UNDEFINED}' ${program} args "\${VALUE}" \${NESTED} MODE=argument\n` +
      JSON.stringify(['${VALUE}', '${NESTED}', "MODE=argument"]) + '\n' +
      `$ ${program} check-env MODE parent\nparent\n` +
      `$ mOdE=mixed ${program} check-env ${process.platform === "win32" ? "MODE" : "mOdE"} mixed\nmixed\n`
    ).join("") +
    [
      [SCRIPT_COMMAND, LOCAL_PACKAGE, SCRIPT_COMMAND],
      [LOCAL_PACKAGE, SCRIPT_COMMAND, LOCAL_PACKAGE],
    ].map(([first, second, third]) =>
      `$ MODE=first ${first} check-env MODE first|${second} check-env-echo parent|MODE=\${MODE}-third ${third} check-env-echo '\${MODE}-third'\nfirst\n` +
      `$ ${first} check-env MODE parent|MODE=second ${second} check-env-echo second|${third} check-env-echo parent\nparent\n`
    ).join("") +
    `$ ${LOCAL_PACKAGE} check-env MODE parent\nparent\n`,
  );
  const document = writeDocument(docs, "command-env.md", source);
  cli(["test", document, "--target", target]);

  const command = `$ MODE='Moon Bit' VALUE="\${MODE}"\t${SCRIPT_COMMAND} check-env VALUE '\${MODE}'|MODE=last ${LOCAL_PACKAGE} check-env-echo last`;
  const original = block(`${command}\nwrong\n`);
  const update = writeDocument(docs, "command-env-update.md", original);
  const dry = cli(["update", update, "--target", target, "--dry-run"]);
  assert(dry.stdout.includes(command));
  assert.equal(fs.readFileSync(update, "utf8"), original);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), block(`${command}\n\${MODE}\n`));
  cli(["test", update, "--target", target]);

  // The same command text parses and runs identically with a defined or absent variable.
  const literal = writeDocument(docs, "command-env-literal.md", block(
    `$ ${LOCAL_PACKAGE} args \${MOONCRAM_LITERAL} "\${MOONCRAM_LITERAL}"\n["\${MOONCRAM_LITERAL}","\${MOONCRAM_LITERAL}"]\n`));
  for (const defined of [false, true]) {
    const env = createEnvironment();
    delete env.MOONCRAM_LITERAL;
    if (defined) env.MOONCRAM_LITERAL = 'different | "value"';
    cli(["check", literal], { env });
    cli(["test", literal, "--target", target], { env });
  }

  const sideEffect = join(docs, "side-effect.txt");
  for (const invalid of [
    "A=x", `A=x|${LOCAL_PACKAGE} hello`, `${LOCAL_PACKAGE} hello|A=x`,
    "A=x export B=y", "A=x set-current-working-directory .",
    `A=x ${LOCAL_PACKAGE} hello 2>&1`,
  ]) {
    const before = block(`$ ${LOCAL_PACKAGE} setup\n$ ${invalid}\n`);
    const bad = writeDocument(docs, "command-env-error.md", before);
    for (const operation of [["test"], ["update"], ["update", "--dry-run"]]) {
      fs.rmSync(sideEffect, { force: true });
      const result = cli([...operation, bad, "--target", target], { expected: EXIT_CODE.ERROR });
      assert(result.stderr.includes("command-env-error.md:3:"), result.stderr);
      assert(result.stdout.includes("0 cases"), result.stdout);
      assert(!fs.existsSync(sideEffect), "a case ran before document validation completed");
      assert.equal(fs.readFileSync(bad, "utf8"), before);
    }
  }
}

export function testCommandEnvironmentCasing({ cli, docs, target }) {
  const windows = process.platform === "win32";
  const source = [SCRIPT_COMMAND, LOCAL_PACKAGE].map(program => block(
    `$ MoDe=first mode=second ${program} check-env ${windows ? "MODE" : "MoDe"} ${windows ? "second" : "first"}\n${windows ? "second" : "first"}\n` +
    `$ MoDe=first mode= ${program} check-env ${windows ? "MODE" : "mode"} ''\n"" (escaped)\n` +
    `$ ${program} check-env MODE parent\nparent\n`,
  )).join("\n");
  const document = writeDocument(docs, "command-env-casing.md", source);
  cli(["test", document, "--target", target]);
}

export function testWorkingDirectories({ cli, docs, directory, target }) {
  const workspace = join(directory, "cwd fixture");
  createDocuments(workspace);
  fs.writeFileSync(join(workspace, "relative.txt"), "configured contents\n");
  // A same-named script in each directory distinguishes script lookup from cwd.
  const selected = "selected.mbtx";
  fs.writeFileSync(join(docs, selected), 'fn main { println("document script") }\n');
  fs.writeFileSync(join(workspace, selected), 'fn main { println("workspace script") }\n');
  const link = join(docs, "cwd-link");
  fs.symlinkSync(workspace, link, DIRECTORY_LINK_TYPE);
  const source = [
    block('$ set-current-working-directory "../cwd fixture"\n' +
      '$ moonx ./selected.mbtx\nworkspace script\n' +
      `$ ${SCRIPT_COMMAND} read-file relative.txt\nconfigured contents\n` +
      `$ ${LOCAL_PACKAGE} context\nparent\nyes\nconfigured contents\n` +
      `$ ${LOCAL_PACKAGE} read-file relative.txt|${SCRIPT_COMMAND} check-file-echo 'configured contents'|${LOCAL_PACKAGE} check-file-echo 'configured contents'\nconfigured contents\n`),
    block(`$ set-current-working-directory ${quoteArgument(workspace)}\n` +
      `$ ${SCRIPT_COMMAND} context|${LOCAL_PACKAGE} check-file-echo 'configured contents'|${SCRIPT_COMMAND} check-file-echo 'configured contents'\nparent\nyes\nconfigured contents\n`),
    block('$ set-current-working-directory cwd-link\n$ moonx ./selected.mbtx\nworkspace script\n'),
    block('$ set-current-working-directory "../cwd fixture"\n'),
    block('$ moonx ./selected.mbtx\ndocument script\n' +
      `$ ${LOCAL_PACKAGE} read-file relative.txt\ncwd contents\n`),
  ].join("\n");
  const document = writeDocument(docs, "cwd-main.md", source);
  cli(["test", document, "--target", target]);
  // Relative directories follow the target Markdown's parent, not its alias.
  const alias = join(directory, "cwd-document-alias.md");
  fs.symlinkSync(document, alias, "file");
  cli(["test", alias, "--target", target]);
  const only = writeDocument(docs, "cwd-only.md", block('$ set-current-working-directory cwd-link\n'));
  assert(cli(["test", only], { expected: EXIT_CODE.ERROR }).stderr.includes("no mooncram cases found"));

  // Both directory and executable names use their literal spelling on disk.
  const literalDirectory = join(docs, '${WORKSPACE}');
  fs.mkdirSync(literalDirectory);
  fs.writeFileSync(join(literalDirectory, '${SCRIPT}.mbtx'), 'fn main { println("literal path") }\n');
  const literalCommand = '$ moonx ./${SCRIPT}.mbtx';
  const literalPrefix = '$ set-current-working-directory "${WORKSPACE}"\n';
  const literalDocument = writeDocument(docs, "cwd-literal.md", block(literalPrefix + literalCommand + '\nwrong\n'));
  cli(["check", literalDocument]);
  cli(["update", literalDocument, "--target", target]);
  assert.equal(fs.readFileSync(literalDocument, "utf8"), block(literalPrefix + literalCommand + '\nliteral path\n'));
  cli(["test", literalDocument, "--target", target]);

  const directive = '$ set-current-working-directory "../cwd fixture"';
  const before = ("Intro\n\n> - ```mooncram\n>   " + directive +
    "\n>   $ moonx ./selected.mbtx\n>   wrong\n>   ```\n\nTail\n").replaceAll("\n", CRLF);
  const after = before.replace("wrong", "workspace script");
  const update = writeDocument(docs, "cwd-update.md", before);
  cli(["update", update, "--target", target, "--dry-run"]);
  assert.equal(fs.readFileSync(update, "utf8"), before);
  cli(["update", update, "--target", target]);
  assert.equal(fs.readFileSync(update, "utf8"), after);
  cli(["test", update, "--target", target]);

  const drySource = block('$ set-current-working-directory "../cwd fixture"\n' +
    `$ ${LOCAL_PACKAGE} setup\n$ moonx ./selected.mbtx\nwrong\n`);
  const dryDocument = writeDocument(docs, "cwd-dry-side-effects.md", drySource);
  const workspaceEffect = join(workspace, "side-effect.txt");
  fs.rmSync(workspaceEffect, { force: true });
  cli(["update", dryDocument, "--target", target, "--dry-run"]);
  assert.equal(fs.readFileSync(dryDocument, "utf8"), drySource);
  assert.equal(fs.readFileSync(workspaceEffect, "utf8"), "side effect preserved\n");

  const sideEffect = join(docs, "side-effect.txt");
  for (const name of ["cwd-missing", "relative.txt", "cwd-not-created-yet", "${UNDEFINED_CWD}"]) {
    const original = block(`$ ${LOCAL_PACKAGE} setup\n$ ${LOCAL_PACKAGE} hello\nwrong\n` +
      (name === "cwd-not-created-yet" ? `$ ${LOCAL_PACKAGE} make-directory ${name}\n` : "")) +
      block(`$ set-current-working-directory ${name}\n`);
    const invalid = writeDocument(docs, "cwd-invalid.md", original);
    const line = original.split("\n").findIndex(text => text.startsWith('$ set-current')) + 1;
    for (const operation of [["test"], ["update"], ["update", "--dry-run"]]) {
      fs.rmSync(sideEffect, { force: true });
      const result = cli([...operation, invalid, "--target", target], { expected: EXIT_CODE.ERROR });
      assert(result.stderr.includes(`cwd-invalid.md:${line}: invalid working directory`), result.stderr);
      assert(result.stderr.includes(join(docs, name)), result.stderr);
      assert(result.stdout.includes("0 cases"));
      assert(!fs.existsSync(sideEffect));
      assert(!fs.existsSync(join(docs, "cwd-not-created-yet")));
      assert.equal(fs.readFileSync(invalid, "utf8"), original);
    }
    const continuing = writeDocument(docs, "cwd-z-continue.md", block(`$ ${LOCAL_PACKAGE} setup\n`));
    const result = cli(["test", continuing, invalid, "--target", target], { expected: EXIT_CODE.ERROR });
    assert(result.stdout.includes("1 cases, 0 failed, 1 errors"));
    assert(fs.existsSync(sideEffect));
  }
  fs.rmSync(sideEffect, { force: true });
}

export function testBuildEnvironment({ cli, docs, directory, target }) {
  if (process.platform === "win32") return;
  const realMoon = findTool("moon");
  const tools = join(directory, "build-env-tools");
  fs.mkdirSync(tools);
  const log = join(directory, "build-env.jsonl");
  fs.writeFileSync(join(tools, "moon"), '#!/usr/bin/env node\n' +
    'const fs = require("node:fs");\n' +
    `fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify({ mode: process.env.MODE, cwd: process.cwd(), args: process.argv.slice(2) }) + "\\n");\n` +
    `const result = require("node:child_process").spawnSync(${JSON.stringify(realMoon)}, process.argv.slice(2), { encoding: "utf8" });\n` +
    'process.stderr.write(result.stderr);\n' +
    'let output = result.stdout;\n' +
    'if (result.status === 0) { const json = JSON.parse(output); json.artifacts_path = json.artifacts_path.map(p => require("node:path").relative(process.cwd(), p)); output = JSON.stringify(json); }\n' +
    'process.stdout.write(output);\n' +
    'process.exit(result.status ?? 2);\n', { mode: 0o755 });
  const document = writeDocument(docs, "command-env-build.md", block(
    `$ set-current-working-directory "../cwd fixture"\n$ ${LOCAL_PACKAGE} hello\nHello, Moon Bit!\n` +
    `$ ${SCRIPT_COMMAND} hello|${LOCAL_PACKAGE} echo\nHello, Moon Bit!\n` +
    `$ MODE=package-temp ${LOCAL_PACKAGE} check-env MODE package-temp\npackage-temp\n` +
    `$ MODE=script-temp ${SCRIPT_COMMAND} check-env MODE script-temp|MODE=pipeline-temp ${LOCAL_PACKAGE} check-env-echo pipeline-temp\nscript-temp\n` +
    `$ ${LOCAL_PACKAGE} check-env MODE parent\nparent\n`,
  ));
  const env = createEnvironment();
  env.PATH = [tools, env.PATH].join(delimiter);
  cli(["test", document, "--target", target], { env });
  const builds = fs.readFileSync(log, "utf8").trim().split("\n").map(line => JSON.parse(line));
  const modes = builds.map(build => build.mode);
  assert(builds.every(build => build.cwd === fs.realpathSync(join(directory, "cwd fixture"))));
  assert(builds.filter(build => build.args[0] === "-C").every(build =>
    build.args[1] === fs.realpathSync(join(directory, "project"))));
  assert(modes.includes("parent"));
  assert(modes.includes("package-temp") && modes.includes("script-temp") && modes.includes("pipeline-temp"));
  assert(modes.every(mode => ["parent", "package-temp", "script-temp", "pipeline-temp"].includes(mode)));
  assert.equal(builds.filter(build => build.mode === "script-temp" && build.args.includes("--build-only")).length, 1);
  assert.equal(builds.filter(build => build.mode === "pipeline-temp" && build.args[0] === "-C").length, 1);
  assert.equal(modes.at(-1), "parent", "temporary build env must not leak into the next case");
}
