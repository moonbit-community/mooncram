# 调用方式与命令行解析

```text
mooncram check [paths...] [--color auto|always|never]
mooncram test [options] [paths...] [options]
mooncram update [options] [paths...] [options] [--dry-run]
mooncram docs --list
mooncram docs <document-name>
mooncram (-h | --help)
mooncram (-V | --version)
mooncram help [check|test|update|docs]
mooncram check (-h | --help)
mooncram test (-h | --help)
mooncram update (-h | --help)
mooncram docs (-h | --help)
```

在仓库目录中，可以这样启动程序：

```text
moon run . -- check examples/README.md
moon run . -- test examples/README.md
moon run . -- update examples --dry-run
```

这些示例中的 `--` 用来分隔 `moon` 的参数与 mooncram 的参数。
后面还可以再使用一个 `--`，终止 mooncram 自身的选项解析。

| 命令 | 行为 |
| --- | --- |
| `check` | 校验文档并解析本地目标，不构建或执行用例。 |
| `test` | 执行用例，将路由后的输出和退出状态与预期结果比较。 |
| `update` | 执行相同的用例，依据实际结果更新并规范化预期，包括已经通过的用例。 |
| `update --dry-run` | 执行用例并打印拟议的文档变更，不写入变更。 |
| `docs --list` | 列出内嵌文档主题及其摘要。 |
| `docs <document-name>` | 打印一份内嵌的英文 Markdown 文档。 |
| `help`、`-h`、`--help` | 向 stdout 打印对应帮助，以 `0` 退出，不发现文件或执行用例。 |
| `-V`、`--version` | 在顶层向 stdout 打印程序版本字符串和换行符，以 `0` 退出。 |

`test`、`update` 和 `update --dry-run` 都会以你的权限执行程序，没有沙箱或临时工作区
隔离。dry-run 只禁止写入更新后的 Markdown，不阻止程序副作用。
不执行程序的校验使用 `check`；CI 使用 `test`，因为 dry-run 即使报告预期不匹配，
仍可能返回 `0`。

除帮助或版本请求外，必须指定子命令。空命令行是参数错误，不会隐式执行 `test`。
版本选项不能放在 `check`、`test`、`update` 或 `docs` 后面，例如 `mooncram test --version`
会产生参数错误。

## 选项与默认值

| 选项 | 作用域 | 默认值 | 可接受的值与作用 |
| --- | --- | --- | --- |
| `--target VALUE` | `test/update` | `wasm` | 仅接受 `wasm` 或 `native`，为本地包选择后端；脚本和远程包固定使用 Wasm。 |
| `--timeout-ms N` | `test/update` | `60000` | 正的有符号 32 位整数，单位为毫秒；每个用例共用一个期限，包含构建、远程获取、执行和输出捕获。 |
| `--color VALUE` | `check/test/update` | `auto` | 仅接受 `auto`、`always` 或 `never`；控制 mooncram 报告的颜色。 |
| `--dry-run` | 仅 `update` | 关闭 | 打印拟议的文档差异，不替换文档。不接受参数值。 |

带值选项必须放在其适用的子命令之后，可以位于路径之前、路径之间或路径之后。
`--target native` 和 `--target=native` 均有效；其他带值选项也支持
`--name=value`。这些选项没有短别名。每个带值选项最多只能指定一次，
重复指定会报错，不会覆盖前一个值。
重复指定 `--dry-run` 会保持启用状态。

`--dry-run` 必须位于 `update` 之后，在顶层、`check`、`test` 或 `docs` 中均无效。
`check` 和 `docs` 也拒绝显式传入 `--target` 和 `--timeout-ms`，即使取值等于默认值。
三个用例命令都接受 `--color`；`docs` 拒绝上述三个带值选项。
顶层帮助和 `help` 没有用例选项。将 `--target`、`--timeout-ms` 或 `--color`
放在任何子命令之前都会报错。
未知命令或选项、缺少选项值以及无效的值，都会导致退出状态 `2`。

`--timeout-ms` 只接受 ASCII 十进制数字，数值范围为 `1..2147483647`。
允许前导零，不接受正负号、空格、小数、零或溢出值。

对于 `check`、`test` 和 `update`，`paths` 接受零个或多个值。未提供路径时使用 `.`。
在这些子命令之后使用 `--`，
可以把其后的所有参数作为路径，包括以 `-` 开头的名称：

```text
mooncram test --target native docs README.md --color never
mooncram update docs --timeout-ms=120000 --dry-run
mooncram test -- -example.md
```

mooncram 不会自行展开路径通配符。启动它的 shell 若进行了展开，展开发生在 CLI
收到参数之前。围栏仅允许模块声明，目标后端和超时由 CLI 选项控制。

## 内嵌文档

无需仓库副本，即可通过 `docs` 查找并阅读内嵌英文参考文档：

```text
mooncram docs --list
mooncram docs quickstart
mooncram docs recipes
mooncram docs troubleshooting
mooncram docs invocation
```

`quickstart` 提供完整的首个测试和目标选择说明；`recipes` 提供可运行的断言模板；
`troubleshooting` 帮助选择失败后的下一步操作。

`--list` 列出可用主题名和摘要。传入其中一个名称，即可在 stdout 读取该主题的
Markdown 内容。名称区分大小写，不接受路径或 `.md` 后缀。
`--list` 与单个主题名二选一。不带参数或传入 `-h`/`--help` 时打印帮助。

成功请求以 `0` 退出；无效名称或参数以 `2` 退出，并向 stderr 报错。
`docs` 不构建、执行用例或修改文件，仅接受 `--list` 和 `-h`/`--help` 选项，
不接受用例选项。

## 不执行程序的检查

`check` 与 `test/update` 共享文件发现、Markdown 解析、命令和预期输出校验，
以及文档级模块、工作目录校验。仅含配置的围栏也会校验。随后逐用例、逐管道段
根据当前文件系统解析目标，检查脚本存在性、完整可执行包名、模块边界及远程精确版本坐标。
检查只读取本地文件及配置，不构建、不下载依赖、不启动子进程，
也不修改 Markdown。

文档解析或声明校验失败计一次错误，并阻止检查该文档中的用例。目标解析失败
计当前用例一次错误，跳过其剩余管道段，并继续后续用例和文档。
汇总格式为 `N cases, E errors`；整次检查没有用例且没有其他错误时，
报告 `ERROR no mooncram cases found`，以 `2` 退出，且不打印汇总。

命令解析不查询环境变量；参数和赋值值在处理引号、转义后保持字面量。
检查结果依赖当前文件系统。如果后一用例的目标需要由前一用例生成，
`check` 可能报目标缺失；`test/update` 在执行时解析目标，支持这种场景。
检查不验证源码是否能编译、后端是否支持构建目标、远程坐标是否存在，
也不验证程序断言是否通过。检查没有逐用例的执行超时。
