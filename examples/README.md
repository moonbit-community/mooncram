# A first mooncram test

Run `moon run . -- test examples` from the repository root.

```mooncram
$ ./hello.mbtx "Moon Bit"
Hello, Moon Bit!
```

The root executable can be called by the module's short name when launched
from this repository root. Programs still run in the `examples` directory.

```mooncram moonbit-community/mooncram
$ mooncram --version
0.0.3
```

A file can also import a fixed-version Mooncakes tool:

```mooncram-import
moongrep : moonbit-community/moongrep@0.3.5
```

```mooncram
$ moongrep help
Usage: moongrep <command>

Scan MoonBit source files with structural and taint rules.

Commands:
  scan  Scan MoonBit source files.
  lint  Scan MoonBit source files with embedded builtin rules.
  docs  Print embedded moongrep documentation.
  dump  Parse a MoonBit impl or expression and print untyped CST debug output.
  help  Print help for the subcommand(s).

Options:
  -h, --help  Show help information.
```

The declaration applies to every test fence in that file, including earlier
fences. Imported tools use Wasm even with `--target native`. moonx fetches and
caches the pinned package; fetching shares the case timeout with execution.
