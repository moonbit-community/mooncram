#!/usr/bin/env python3
"""Exercise both CLI backends with real MoonBit scripts and packages.

Run from any directory: python3 tests/integration.py [--target wasm|native]
Requires Python 3, moon, moonx, moonrun, and the native C toolchain.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
PROGRAM = (ROOT / "tests/fixtures/program.mbt").read_text()
IMPORTS = [
    "moonbitlang/async",
    "moonbitlang/async/fs",
    "moonbitlang/async/stdio",
    "moonbitlang/core/env",
    "moonbitlang/x/sys",
]


def run(command, *, cwd=ROOT, env=None, expected=0, timeout=120):
    result = subprocess.run(
        [str(arg) for arg in command], cwd=cwd, env=env,
        capture_output=True, text=True, timeout=timeout,
    )
    assert result.returncode == expected, (
        f"{command}: expected exit {expected}, got {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def block(body, **config):
    info = " " + json.dumps(config) if config else ""
    return f"```mooncram{info}\n{body}```\n"


def exercise(target):
    artifact = json.loads(run([
        "moon", "run", "--build-only", "--target", target, "cmd/mooncram",
    ]).stdout)["artifacts_path"][0]
    executable = ["moonrun", artifact, "--"] if target == "wasm" else [artifact]
    env = {
        **os.environ, "MODE": "parent", "MOONCRAM_INHERITED": "yes",
        # Keep standalone fixture builds local, including in read-only-home CI.
        "MOON_DEP_CACHE": "off", "MOON_BUILD_CACHE": "off",
    }
    (ROOT / "_build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"integration-{target}-", dir=ROOT / "_build") as name:
        directory = Path(name)
        docs = directory / "docs"
        docs.mkdir()
        project = directory / "project"
        package = project / "cmd"
        package.mkdir(parents=True)
        (project / "moon.mod").write_text(
            'name = "mooncram/integration"\n'
            'import { "moonbitlang/async@0.22.4", "moonbitlang/x@0.5.5" }\n'
        )
        (project / ".mooncakes").symlink_to(ROOT / ".mooncakes", target_is_directory=True)
        imports = "import {\n" + "".join(f'  "{item}",\n' for item in IMPORTS) + "}\n"
        (package / "moon.pkg").write_text(imports + 'options("is-main": true)\n')
        (package / "main.mbt").write_text(PROGRAM)
        script_imports = imports.replace("moonbitlang/async", "moonbitlang/async@0.22.4").replace(
            "moonbitlang/x/sys", "moonbitlang/x@0.5.5/sys"
        )
        (docs / "program with space.mbtx").write_text(script_imports + PROGRAM)
        (docs / "input.txt").write_text("stdin contents\n")
        (docs / "relative.txt").write_text("cwd contents\n")
        script = '"./program with space.mbtx"'
        local = "../project/cmd"

        def cli(*args, expected=0, cwd=docs, **kwargs):
            return run([*executable, *args], cwd=cwd, env=env, expected=expected, **kwargs)

        assert "Usage: mooncram" in cli("--help").stdout
        assert "dry-run" in cli("update", "--help").stdout
        assert "0.1.0" in cli("--version").stdout
        cli("test", "--timeout-ms", "0", expected=2)
        cli("test", "--target", "js", expected=2)
        cli("test", "--color", "invalid", expected=2)
        cli("test", "--dry-run", expected=2)
        cli("test", "missing.md", expected=2)
        empty = docs / "empty.md"
        empty.write_text("No test blocks.\n")
        assert "no mooncram cases" in cli("test", empty, expected=2).stderr

        good = docs / "pass.md"
        content = block(f"$ {script} hello\nHello, Moon Bit!\n")
        for program in (script, local):
            content += block(
                f"$ {program} args 'Moon Bit' \"a'b\" '' '$HOME' '*' '|' --version\n"
                '["Moon Bit","a\'b","","$HOME","*","|","--version"] (equal)\n'
            )
            content += block(
                f"$ {program} context\ntest\nyes\ncwd contents\nstdin contents\n\n"
                f"$ {program} context\ntest\nyes\ncwd contents\nstdin contents\n",
                stdin="./input.txt", env={"MODE": "test"},
            )
            content += block(f"$ {program} echo\n")
            content += block(f"$ {program} setup\n\n$ {program} read\nside effect preserved\n")
            content += block(f"$ {program} crlf\none\ntwo\n")
            content += block(f"$ {program} streams\none\nthree\n[2]\n")
            content += block(f"$ {program} streams\ntwo\n[2]\n", stream="stderr")
            content += block(f"$ {program} streams\none\ntwo\nthree\n[2]\n", stream="merged")
        content += block(f"$ {local} hello\nHello, Moon Bit!\n", target="wasm" if target == "native" else "native")
        content += block(f"$ {local} large\no* (glob)\n")
        content += block(f"$ {local} large\ne* (glob)\n", stream="stderr")
        good.write_text(content)
        result = cli("test", good, "--target", target, "--color", "never")
        assert "0 failed, 0 errors" in result.stdout
        assert "\x1b" not in result.stdout
        print(f"{target}: scripts, packages, args, cwd, env, stdin, streams, large output passed", flush=True)

        failed = docs / "failure.md"
        failed.write_text(block(f"$ {local} streams\nwrong\n"))
        result = cli("test", failed, "--target", target, expected=1)
        assert "failure.md:2" in result.stdout
        assert "-wrong" in result.stdout and "+one" in result.stdout
        assert "expected 0, actual 2" in result.stdout
        assert "diagnostic stderr\ntwo" in result.stdout
        assert "\x1b" in cli("test", failed, "--color", "always", expected=1).stdout

        update = docs / "update.md"
        nested = block(f"$ {script} special\nold\n\n$ {script} hello\nHello,* (glob)\n")
        source = "😀 Intro\n\n" + "\n".join(
            "> - " + line if i == 0 else ">   " + line
            for i, line in enumerate(nested.rstrip("\n").split("\n"))
        ) + "\n\n" + block(f"$ {local} crlf\no* (glob)\nwrong\n") + "Unchanged tail"
        original = source.replace("\n", "\r\n").encode()
        update.write_bytes(original)
        result = cli("update", update, "--dry-run", "--target", target)
        assert "would update 2" in result.stdout and "(updated)" in result.stdout
        assert update.read_bytes() == original
        cli("update", update, "--target", target)
        updated = update.read_bytes()
        assert updated.startswith("😀 Intro\r\n\r\n> - ```mooncram\r\n".encode())
        assert b"Hello,* (glob)\r\n" in updated and b"o* (glob)\r\n" in updated
        assert b"(escaped)" in updated and b"(no-eol)" in updated
        assert updated.endswith(b"Unchanged tail")
        assert b"\n" not in updated.replace(b"\r\n", b"")
        cli("test", update, "--target", target)
        cli("update", update, "--target", target)
        assert update.read_bytes() == updated
        assert not list(docs.glob(".mooncram-*"))
        print(f"{target}: diagnostics, dry-run, local updates, escaping, pattern preservation passed", flush=True)

        bad_package = project / "bad"
        bad_package.mkdir()
        (bad_package / "moon.pkg").write_text('options("is-main": true)\n')
        (bad_package / "main.mbt").write_text("fn main { nonexistent_function() }\n")
        (docs / "bad.mbtx").write_text("fn main { nonexistent_function() }\n")
        library = project / "library"
        library.mkdir()
        (library / "moon.pkg").write_text("")
        (library / "lib.mbt").write_text("pub fn value() -> Int { 1 }\n")
        error_doc = docs / "error.md"
        for bad_case in (
            "$ ../project/bad\n",
            "$ ./bad.mbtx\n",
            "$ ../project/library\n",
            "$ ./missing.mbtx\n",
            "$ /bin/echo hello\n",
            f"$ {local} invalid-utf8\n",
        ):
            original_error = block(f"$ {local} hello\nwrong\n\n" + bad_case)
            error_doc.write_text(original_error)
            result = cli("update", error_doc, "--target", target, expected=2)
            assert error_doc.read_text() == original_error
            assert "Not updating" in result.stderr
            if "bad" in bad_case:
                assert "build failed" in result.stderr
        error_doc.write_text(block(f"$ {local} hello\nwrong\n\n$ {local} hello | cat\n"))
        before = error_doc.read_bytes()
        assert "shell operator" in cli("update", error_doc, expected=2).stderr
        assert error_doc.read_bytes() == before

        # A deadline covers the build and executable together. Both managed
        # native artifacts and moonrun processes must be cancelled promptly.
        slow = docs / "slow.md"
        for backend in ("wasm", "native"):
            slow.write_text(block(f"$ {local} slow\n", target=backend, timeout_ms=350))
            start = time.monotonic()
            result = cli("test", slow, expected=2)
            assert time.monotonic() - start < 4
            assert "timed out after 350 ms" in result.stderr
        assert not (docs / "slow-finished.txt").exists()

        mutate = docs / "mutate.md"
        mutate.write_text(block(f"$ {local} mutate\nwrong\n"))
        result = cli("update", mutate, "--target", target, expected=2)
        assert "source changed" in result.stderr
        assert mutate.read_text() == "changed by command\n"

        scan = directory / "scan"
        scan.mkdir()
        for ignored in (".hidden", "_build", "target"):
            child = scan / ignored
            child.mkdir()
            (child / "ignored.md").write_text("```mooncram\ninvalid\n```\n")
        (scan / "cycle").symlink_to(scan, target_is_directory=True)
        (scan / "a.md").write_text(block(f'$ "{package}" setup\n'))
        (scan / "z.md").write_text(block(f'$ "{package}" read\nside effect preserved\n'))
        result = cli("test", scan, scan / "a.md", "--target", target)
        assert "2 cases" in result.stdout
        result = cli("test", "--target", target, cwd=scan)
        assert "2 cases" in result.stdout
        # Other work gives cancelled processes time to reveal stray side effects.
        assert not (docs / "slow-finished.txt").exists()
        print(f"{target}: error isolation, timeout, concurrent edit, scan order and symlink checks passed", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["wasm", "native"], action="append")
    args = parser.parse_args()
    for target in args.target or ["wasm", "native"]:
        exercise(target)
    print("All CLI integration checks passed.")


if __name__ == "__main__":
    main()
