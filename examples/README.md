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
0.0.8
```

A fixed-version Mooncakes tool can be run directly:

```mooncram
$ moonx moonbit-community/mooncram@0.0.3 --version
0.0.3
```

Remote tools use Wasm even with `--target native`. moonx fetches and caches
the pinned package; fetching shares the case timeout with execution.
