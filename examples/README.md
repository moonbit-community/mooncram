# A first mooncram test

Run `moon run . -- test examples` from the repository root.

```mooncram
$ moonx ./hello.mbtx "Moon Bit"
Hello, Moon Bit!
```

Call the root executable with `moonx` and its full module name when launched
from this repository root. Programs still run in the `examples` directory.

```mooncram moonbit-community/mooncram
$ moonx moonbit-community/mooncram --version
0.0.7
```

A fixed-version Mooncakes tool can be run directly:

```mooncram
$ moonx moonbit-community/mooncram@0.0.3 help
Usage: mooncram [options] <command>

Run MoonBit command examples in Markdown mooncram fences.

Commands:
  test    Check command output and exit status
  update  Update failing expectations in place
  help    Print help for the subcommand(s).

Options:
  -h, --help                 Show help information.
  -V, --version              Show version information.
  --target <target>          Package target: wasm or native [default: wasm]
  --timeout-ms <timeout-ms>  Per-case time limit, including build [default: 60000]
  --color <color>            Color: auto, always, never [default: auto]
```

Remote tools use Wasm even with `--target native`. moonx fetches and caches
the pinned package; fetching shares the case timeout with execution.
