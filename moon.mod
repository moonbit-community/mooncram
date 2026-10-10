// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "moonbit-community/mooncram"

version = "0.0.2"

readme = "README.md"

repository = ""

license = "Apache-2.0"

keywords = [ ]

preferred_target = "wasm"

description = "A simple and powerful testing toolkit for MoonBit CLI applications and Script"

import {
  "moonbitlang/async@0.22.4",
  "moonbit-community/cmark@0.4.9",
  "moonbit-community/chalk@0.0.1",
  "moonbitlang/x@0.5.5",
  "moonbitlang/moon_config@0.4.2",
}
