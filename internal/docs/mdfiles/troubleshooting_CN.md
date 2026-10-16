# 排错：选择下一步操作

先定位单个失败文档，让源码位置、报告与下一条命令对应同一个输入。
下列命令中的 `tests/example.md` 请替换为你的文档路径；
若用例使用本地包，应从模块目录启动。

## 从失败到确认通过

1. 运行 `mooncram check tests/example.md`，根据当前文件系统校验 Markdown、
   预期、声明和目标。它不构建、不获取远程包，也不验证行为。
   由前面用例创建的目标可能在此时报缺失；应检查准备步骤，并用 `test` 执行整个顺序。
2. 运行 `mooncram test tests/example.md --color never`，构建并测试实际行为。
   stdout 上的 `FAIL` 表示已完成执行的用例与预期不匹配；stderr 上的 `ERROR`
   表示解析、配置、目标解析或执行无法完成。检查源码位置、阶段、cwd 和捕获的输出。
3. 出现不匹配时，判断是程序错误还是预期行为有意变化。
   非预期行为应修程序，再运行 `test`；不要通过更新预期接受回归。
4. 对于有意变化，运行 `mooncram update tests/example.md --dry-run`。
   审阅拟议输出、退出码变化，以及通过用例和围栏的规范化。
   确认正确后运行 `mooncram update tests/example.md`。
5. 再运行 `mooncram test tests/example.md --color never`，用它的结果判断测试是否通过，
   不能用更新命令的退出码代替。

如果需要非默认的 `--target` 和 `--timeout-ms`，在 `test`、dry-run 和 `update`
中保持一致；`check` 不接受这两个选项。`test` 和 dry-run 都会以你的权限执行代码，
可能留下副作用，没有沙箱或临时工作区隔离。

| mooncram 退出码 | 含义与操作 |
| --- | --- |
| `0` | 命令成功完成。对于 `test`，表示断言通过；对于 `check`，只表示结构和当前目标通过检查。更新或 dry-run 仍可能报告不匹配。 |
| `1` | `test` 发现不匹配且没有错误。审阅差异，判断应修程序还是更新预期。 |
| `2` | 参数、文件发现、文档或执行发生错误，或者没有用例。先修复错误再依赖本次结果；错误的优先级高于不匹配。 |

这些是 mooncram 自身的退出码。被测程序返回 `2`，可以通过以 `[2]` 结束的用例，
使 `mooncram test` 返回 `0`。

## 症状、检查点与下一条命令

| 症状 | 检查点 | 下一条命令或操作 |
| --- | --- | --- |
| `no mooncram cases found` | 输入文件后缀必须为小写 `.md`；用例需要反引号 `mooncram` 围栏和 `$ ` 命令行。外层示例围栏会遮蔽内层围栏；仅含配置的块不算用例。目录扫描跳过隐藏条目、`_build`、`target`，不跟随目录符号链接。 | 显式指定文件：`mooncram check tests/example.md`；仍为空时修正文档围栏或命令。 |
| 找不到脚本 | 脚本相对于块的 `#cwd` 目录或规范文档的父目录解析，不是启动目录。检查拼写、`.mbtx` 后缀，以及是否由前面的用例生成。 | 修正路径后运行 `mooncram check tests/example.md`；对于生成的脚本，用 `mooncram test tests/example.md` 验证准备步骤。 |
| `#cwd` 目录不存在，或文档没有执行任何用例 | 执行该文档的任何用例前，全部块工作目录就必须存在。相对 `#cwd` 以文档目录为基准，引号会成为目录名的一部分。 | 在启动 mooncram 前创建目录，或修正 `#cwd`，再运行 `mooncram check tests/example.md`。 |
| 缺少模块或模块名称不匹配 | 启动目录必须直接包含 `moon.mod`，不向父目录搜索。围栏声明必须与其 `name` 完全一致，本地目标必须写完整模块/包名。`#cwd` 不改变模块查找位置。 | 在终端切换到模块根目录，修正声明或目标，再用相对于根目录的路径运行 `mooncram check tests/example.md`。 |
| 构建失败 | 阅读 `phase: build` 上下文和捕获的编译输出，检查依赖、可执行包配置、所选后端及工具是否可用。构建失败不能满足程序的 `[N]` 预期。 | 修复报告中的构建问题，再以相同后端运行 `mooncram test tests/example.md --color never`。 |
| 超时 | 期限包含本地构建、远程获取、执行和输出捕获。根据报告阶段和部分输出，判断是否构建或下载过慢、等待输入，或程序未退出。 | 修复挂起；如果操作确实需要更多时间，重试 `mooncram test tests/example.md --timeout-ms 120000`。 |
| 输出看起来相同却失败 | 除退出码外，还要检查行尾空格、制表符、空行、ANSI 转义和末尾换行。CRLF 会规范化，其他字符仍有意义。差异展示的是预期语法，不是原始字节。 | 运行 `mooncram test tests/example.md --color never`，查看 actual 一侧的 `(escaped)` 和 `(no-eol)`，修复程序或精确预期。 |
| stderr 出现意外消息仍通过 | 无标记用例只断言 stdout；对 stderr 做断言必须同时提供两个流标记。 | 在 `@STDOUT` 下写预期输出，并加上 `@STDERR (empty)` 要求静默；或者用 `@STDOUT (ignore)` 和 `@STDERR` 只检查 stderr，再运行 `mooncram test tests/example.md`。 |
| 更新打印 `FAIL`，但汇总为 `updated 0` | 文档内任何执行错误都会抑制全部更新；查找 `ERROR` 和 `Not updating ...: execution errors in this document`。替换或更新校验错误也可能阻止修改；其他文档可能已经更新。 | 修复错误后重跑 `mooncram update tests/example.md --dry-run`，审阅差异，再应用并复测。 |
| dry-run 打印 `FAIL` 或 `would update N` 却返回 `0` | 更新成功退出只表示操作完成且没有错误，不表示断言通过。 | 运行 `mooncram test tests/example.md --color never` 获取断言结果；CI 使用 `test`。 |

对于不可见输出，空流、一个换行符、末尾没有换行的文本分别需要：不写输出行、
`"" (escaped)`、`text (no-eol)`。关闭报告颜色不会移除被测程序输出的 ANSI 转义。
不要用整行 `* (glob)` 隐藏不匹配；保留稳定文本，只放宽确实需要变化的字段。
