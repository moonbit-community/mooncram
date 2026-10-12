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
0.0.4
```

A file can also import a fixed-version Mooncakes tool:

```mooncram-import
mbtcram : moonbit-community/mooncram@0.0.3
```

```mooncram
$ mbtcram help
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

The declaration applies to every test fence in that file, including earlier
fences. Imported tools use Wasm even with `--target native`. moonx fetches and
caches the pinned package; fetching shares the case timeout with execution.
