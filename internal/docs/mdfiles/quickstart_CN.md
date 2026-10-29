# 快速入门：第一个 CLI 测试

mooncram 使用 Markdown 中的命令和预期输出来测试 MoonBit 命令行程序，
支持以下目标：

| 目标 | `mooncram` 块内的命令 | 前提 | 后端 |
| --- | --- | --- | --- |
| 独立脚本 | `moonx ./hello.mbtx` | 已存在的 `.mbtx` 文件，路径相对于块工作目录，也可以使用绝对路径；无需声明模块。 | 固定 Wasm。 |
| 本地可执行包 | `moonx user/acme/cmd/tool` | 使用 `mooncram user/acme` 围栏；从 `moon.mod` 精确声明该名称的目录启动；包的 `moon.pkg` 必须声明 `pkgtype(kind: "executable")` 或 `options("is-main": true)`。 | 默认 Wasm；`--target native` 选择 native。 |
| 远程可执行包 | `moonx user/tool[/package]@1.2.3` | 已发布的可执行包及精确 SemVer 版本，由 `moonx` 获取并缓存；无需声明模块。 | 固定 Wasm。 |

上表的包名用于展示格式。任意二进制、`echo`、`cat` 等普通 Shell 命令及 `.mbt`
文件均不是支持的目标。每个管道段在临时环境变量赋值之后都必须以 `moonx` 开头。
命令不经过 Shell，不展开变量、通配符或 `~`，不支持重定向。

## 执行用例前

| 操作 | 规则 |
| --- | --- |
| 编写断言 | 默认断言 stdout 和程序退出码 `0`；stderr 需要显式同时使用 `@STDOUT` 和 `@STDERR` 标记。 |
| 解析路径 | 本地模块使用启动目录直接包含的 `moon.mod`，不向父目录搜索。脚本和相对文件参数使用块工作目录，默认是规范文档的父目录，也可用 `#cwd` 指定；`#cwd` 不改变模块查找位置。 |
| 执行程序 | `test`、`update`、`update --dry-run` 都会以你的权限执行代码，没有沙箱或临时工作区隔离。dry-run 不修改 Markdown，但程序仍可能修改文件。不执行程序的校验使用 `check`。 |
| 设置超时 | 默认每个用例共用 60000 毫秒期限，包含构建、远程获取、执行和输出捕获。 |

## 创建两个文件

先安装 `mooncram` 和完整 MoonBit 工具链，将安装的 `bin` 目录加入 `PATH`。
这些脚本使用同一安装中的 `moon` 和 `moonrun`。
本例无需仓库副本、模块配置或外部依赖。在任意工作目录创建以下文件：

```text
demo/
└── tests/
    ├── hello.mbtx
    └── hello.md
```

`tests/hello.mbtx` 的完整内容：

```mbt
---
import { "moonbitlang/core/builtin" }
---

fn main {
  println("Hello, MoonBit!")
}
```

`tests/hello.md` 的完整内容：

````markdown
# Greeting

The script greets the user.

```mooncram
$ moonx ./hello.mbtx
Hello, MoonBit!
```
````

`$ ` 行开始一个用例，后续行断言 stdout，默认预期程序退出码为 `0`。
除非显式同时使用 `@STDOUT` 和 `@STDERR` 标记，否则不对 stderr 做断言。
只有标记为 `mooncram` 的反引号围栏会执行；创建 `hello.md` 时，
不要复制这里用于展示的最外层四反引号 `markdown` 围栏。

## 检查并运行

在终端中，从 `demo` 目录运行：

```sh
mooncram check tests/hello.md
mooncram test tests/hello.md
```

`check` 打印以下汇总，以 `0` 退出：

```text
1 cases, 0 errors
```

`test` 构建并执行脚本，打印以下汇总，以 `0` 退出：

```text
1 cases, 0 failed, 0 errors
```

通过的用例没有单独报告。输入路径 `tests/hello.md` 相对于 mooncram 的启动目录；
脚本 `./hello.mbtx` 相对于文档所在目录 `demo/tests`。
这个纯脚本测试不要求启动目录包含 `moon.mod`。

`check` 校验结构和当前目标，不验证编译或程序行为。
如果脚本由前面的用例生成，`check` 可能报目标缺失；`test` 会在执行各用例时解析目标。

mooncram 自身的退出码与被测程序的预期退出码独立。被测程序返回 `2`，可以通过以
`[2]` 结束的用例。`test` 全部通过时返回 `0`，只有不匹配且无错误时返回 `1`，
发生错误或没有用例时返回 `2`。

## 处理结果变化

如果问候语出现非预期变化，修复程序并重新运行 `test`。
如果变化符合意图，先明确以下更新规则：

- 更新也会处理通过的用例，并可能规范化预期和围栏；应审阅完整的拟议差异。
- 文档内任何执行错误都会阻止该文档的全部预期更新和 dry-run 文档差异；
  其他文档仍可能更新。
- `update --dry-run` 即使打印 `FAIL`，也可能返回 `0`，只表示预览完成且没有错误；
  CI 应使用 `test` 判断测试是否通过。

先预览新预期、审阅差异，再应用更新并重新验证：

```sh
mooncram update tests/hello.md --dry-run
mooncram update tests/hello.md
mooncram test tests/hello.md
```

如果使用非默认的 `--target` 和 `--timeout-ms`，在 `test`、dry-run 和 `update`
中保持一致。最后一次 `test` 必须通过，才能确认更新后的示例有效。
