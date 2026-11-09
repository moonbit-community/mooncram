# 仓库输入边界分析报告

分析日期：2026-11-09。

本次对照仓库文档，检查了文件发现、Markdown 解析、命令分词、目标解析、构建执行、输出匹配和预期更新流程，重点寻找“单独看符合规则，组合使用却产生意外结果”的输入。

最值得优先处理的是**管道构建产物互相覆盖**和**符号链接路径解析到错误位置**。此外，确认了长 glob 的性能问题和 stderr 拼接时的规范化边界差异。下文区分实现问题与已有文档说明的使用陷阱，不将所有意外行为都归类为缺陷。

**1. 优先修复：同一管道中的不同构建环境，最终可能运行同一个产物**

合理输入：同一个本地包在两个管道段中运行，每段通过临时环境变量选择不同的编译配置。规则允许临时环境变量作用于对应管道段的构建和执行。

复现使用两个 C 编译器包装脚本，分别注入 `VALUE=1`、`VALUE=2`。本地包通过一个最小 C 函数把编译时的值写入 stderr。命令结构如下，编译器路径为示意：

```text
$ MOON_CC=/path/cc1 moonx user/buildenv | MOON_CC=/path/cc2 moonx user/buildenv
```

实测结果：

| 运行方式 | stderr |
| --- | --- |
| 单独运行第一段 | `1\n` |
| 单独运行第二段 | `2\n` |
| 两段组成管道 | **`2\n2\n`**，预期为 `1\n2\n` |

两段程序均正常退出。这不是临时运行环境泄漏，而是编译产物被覆盖：所有段先完成构建，再启动程序；第一段保存的是产物路径，第二次构建覆盖该路径后，两段都运行第二次生成的文件。

影响：被测试的程序可能不是对应管道段按其环境构建出来的程序。测试结果与分别运行各段的结果不同，也可能让断言验证了错误的构建配置。

相关位置：

- [internal/execute/execute.mbt](internal/execute/execute.mbt)，第 32–55 行：先依次准备所有命令，再启动管道。
- 同文件第 109–128 行：本地包构建完成后，仅保存产物路径供后续执行。

建议为各段隔离构建输出，或保存不会被后续构建覆盖的产物。修复时应保留“全部本地构建成功后才启动被测程序”的现有约定。

**2. 路径问题：符号链接后接 `..`，可能运行错误的脚本**

假设目录中有以下符号链接：

```text
work/link → work/actual/nested
```

以下两种输入都能触发：

```text
#cwd(link/..)
$ moonx ./hello.mbtx
```

```text
$ moonx ./link/../hello.mbtx
```

文件系统解析 `link/..` 的结果是 `work/actual`；仓库却先通过字符串归一化删除 `link/..`，得到 `work`。

复现时，在 `work/hello.mbtx` 和 `work/actual/hello.mbtx` 分别放置输出不同内容的脚本，确认实际运行了外层脚本。两个文件都存在时，不会报路径错误，只会执行错误的目标。

相关位置：

- [internal/files/path.mbt](internal/files/path.mbt)，第 6–10 行：`resolve_from` 提前调用 `normalize()`。
- [internal/resolve/working_directory.mbt](internal/resolve/working_directory.mbt)，第 9–14 行：先做词法归一化，再调用 `realpath`。
- [internal/resolve/document.mbt](internal/resolve/document.mbt)，第 80–92 行：脚本路径同样经过上述归一化。

建议文件系统路径先保留原始组件进行解析，再做规范化；模块名的词法校验可以单独保留。

**3. 性能问题：20 KB 的合法 glob，匹配耗时数秒且不受执行超时约束**

实测输入：

- 程序输出一行 20,000 个 `a`。
- 精确预期：20,000 个 `a`。
- glob 预期：同样的文本后加 `* (glob)`。
- 两次均指定 `--timeout-ms 100`。

本机 native CLI 的测量结果：

| 匹配方式 | 总耗时 | 结果 |
| --- | ---: | --- |
| 精确匹配 | 0.092 秒 | 通过 |
| glob | **5.744 秒** | 通过，没有超时 |

这些时间是当前环境的观测值，不是跨机器的性能保证。

glob 实现对每个模式 token 遍历整行，复杂度为 `O(模式长度 × 输出长度)`；这个例子约产生四亿次状态计算。匹配调用发生在执行超时返回之后，所以执行阶段成功结束后，匹配仍可能消耗大量时间。

相关位置：

- [internal/output/glob.mbt](internal/output/glob.mbt)，第 92–113 行：逐 token、逐输出字符的动态规划。
- [internal/cli/runner.mbt](internal/cli/runner.mbt)，第 41–51 行：`execute_case` 返回后才进行匹配及失败报告。

这是性能及超时范围的组合问题。建议增加固定前缀等快速匹配路径，并为匹配、差异生成和更新提供独立预算。

**4. 规范边界：跨管道段拼出来的 CRLF 不会被规范化**

合理输入：第一段 stderr 输出 `"\r"`，第二段输出 `"\n"`。stdout 均为空，两段正常退出。

按段拼接后的字节是 `"\r\n"`，但断言实际看到的仍是 CRLF；同一段直接输出 CRLF 时，则会变成 LF。因此，产生相同拼接字节的两种方式，匹配结果不同。

以一个空输出行作为 stderr 预期，实测得到以下失败差异：

```diff
-"" (escaped)
+"\r" (escaped)
```

原因是实现先分别规范化每段 stderr，再拼接。这样最终拼接产生的 CRLF 不会被再次处理。

相关位置：

- [internal/execute/pipeline.mbt](internal/execute/pipeline.mbt)，第 163–169 行：先对每段调用 `normalize_output`，再拼接字符串。
- [执行规则](internal/docs/mdfiles/execution_CN.md)，第 69–70 行：描述比较和报告前将每个 CRLF 规范化为 LF。

这是规范化顺序的边界歧义。应明确规范化针对每段原始流，还是最终合并流；若承诺后者，需要在拼接后处理。

**5. 已有文档说明、但仍容易误解的规则组合**

下面这些输入同样容易产生意外结果，但详细文档已经规定了对应行为，应作为使用陷阱或规则设计问题处理。

| 合理输入或使用方式 | 实际结果 |
| --- | --- |
| `moonx user/pkg@1.2.3-rc.mbtx` | 虽然版本符合 SemVer，却优先按本地脚本处理。缺少文件时报错；同名本地文件存在时直接运行它。已实测。 |
| 对权限为 `0600` 的 Markdown 执行 `update` | 在 umask 为 `022` 时变成 `0644`；硬链接关系也断开。已实测。 |
| 使用 `@STDERR (ignore)` 忽略二进制 stderr | 仍会捕获并校验 UTF-8，非法字节导致执行错误。 |
| 前一个用例创建后续块的 `#cwd` 目录 | 所有目录提前校验，因此整份文档执行零个用例。 |
| 后一个用例运行前一个用例生成的脚本 | `test` 可以支持；`check` 因不执行前一个用例，可能报告脚本不存在。 |
| `test b.md a.md`，希望按参数顺序执行 | 文件按规范路径排序，可能先执行 `a.md`，影响跨文件副作用依赖。 |
| 预期最后一行是字面量 `[2]` | 会解释成退出码；应写成 `"[2]" (escaped)`。 |
| `update --dry-run` 用于 CI 校验 | 会执行程序、可能产生副作用；打印 `FAIL` 仍可能退出 `0`。 |
| `--target native` 测试 `.mbtx` | 脚本仍使用 Wasm。 |
| 远程程序正常返回 `255`，预期写 `[255]` | 仍被视为执行错误，该状态被远程执行保留。 |

文档依据：

- [命令和目标选择](internal/docs/mdfiles/commands_CN.md)：`.mbtx` 后缀优先级、环境变量和工作目录提前校验。
- [错误隔离与安全替换](internal/docs/mdfiles/errors_CN.md)：不保留原始权限、inode、硬链接关系及扩展元数据。
- [输出预期](internal/docs/mdfiles/expectations_CN.md)：流标记、忽略流仍校验 UTF-8、末尾退出码标记。
- [文件发现与执行顺序](internal/docs/mdfiles/discovery_CN.md)：按规范路径去重和排序。
- [调用方式](internal/docs/mdfiles/invocation_CN.md)：`check` 与执行的区别。
- [更新规则](internal/docs/mdfiles/updates_CN.md)：dry-run 执行副作用及退出状态。
- [构建与执行](internal/docs/mdfiles/execution_CN.md)：脚本固定 Wasm、远程保留退出状态。

其中，远程坐标与脚本后缀的歧义，以及更新导致的文件元数据变化，值得在常用文档中更突出地说明。

**6. 验证范围与结果**

验证环境为 Linux，使用本机 MoonBit 工具链 `moon 0.1.20261104 (940aa18 2026-11-04)`。

| 验证项 | 结果 |
| --- | --- |
| `moon test` | 166/166 通过 |
| `moon test --target native` | 166/166 通过 |
| `node e2etests/integration.mjs` | Wasm、native 完整端到端测试通过 |
| `moon run . -- test examples/README.md` | 3 个用例通过 |
| 额外更新往返检查 | 22,800 组排版、换行、输出和退出码组合未发现异常 |
| `moon check` | 通过 |
| `moon info`、`moon fmt` | 完成，未产生源码或接口差异 |

构建产物覆盖、符号链接路径、stderr 拼接边界、远程坐标后缀优先级和文件元数据变化，均使用 Wasm 与 native 两种 CLI 后端复现。长 glob 的上述耗时数据来自 native CLI。

未实测 Windows，也未通过真实远程包下载验证注册表行为。现有测试通过不代表上述边界问题不存在。

本次分析没有修改生产代码；临时加入的组合检查文件已移出仓库。在保存本报告前，工作区保持干净。

**7. 会话复现材料**

主要案例已整理为本机会话的临时脚本：

```text
/tmp/mooncram-audit/reproduce.py
```

已分别运行并验证：

```sh
python3 /tmp/mooncram-audit/reproduce.py --backend native
python3 /tmp/mooncram-audit/reproduce.py --backend wasm
```

该脚本会在临时目录创建独立 fixture，复现构建产物覆盖、符号链接路径、stderr 拼接边界、远程坐标后缀优先级和文件元数据变化。它不包含长 glob 的性能测量。

更新往返组合检查源码保留于 `/tmp/mooncram-audit/audit_probe_test.mbt`。长 glob 的测量输入保留于 `/tmp/mooncram-audit/long.mbtx`、`/tmp/mooncram-audit/long-exact.md` 和 `/tmp/mooncram-audit/long-glob.md`。

这些复现材料位于 `/tmp`，不属于版本库，可能随临时目录清理而消失；本报告保存了主要输入条件、实际结果及相关源码位置。
