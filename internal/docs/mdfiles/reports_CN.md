# 报告与颜色

通过的用例不打印独立报告。预期结果不匹配时，`test`、`update` 和试运行均会向
**stdout** 打印报告：

```text
FAIL <canonical-file>:<command-line>
  $ <original command text>
  exit: expected <expected-status>, actual <actual-status>
--- expected
+++ actual
<diff hunks>
```

差异使用三行上下文。实际结果一侧使用预期结果语法呈现，包括转义、`(no-eol)`、
非零状态标记以及保留的匹配模式，不是原始程序输出的直接转储。
如果诊断 stderr 非空，报告会追加 `--- diagnostic stderr` 及其规范化后的文本，
并确保末尾有换行符。通过的用例不会打印诊断 stderr。

双流用例仅对失败的内容约束生成差异，标题为 `--- expected @STDOUT` /
`+++ actual @STDOUT`，或对应的 `@STDERR` 标题。忽略的流不产生内容差异。
退出码统一在用例头部显示一次。参与 stderr 差异展示的内容不重复打印为诊断；
stderr 被忽略而其他断言失败时，仍可作为诊断展示。

错误写入 **stderr**，显示可用的源码位置、执行上下文和底层原因。
`ERROR` 标题使用能够确定的最精确源码位置：

```text
ERROR <file>[:<line>[:<column>]]: <summary>
  <line> | <source before>⟦<highlighted range>⟧<source after>
  note: <related file>:<line>[:<column>]: <message>
  <line> | <related source excerpt>
  $ <original command text>
  phase: <resolve|build|start|run|capture>
  segment: <index>/<count> (<executable>)
  tool: <actual tool or artifact>
  cwd: <working directory>
  cause: <underlying reason>
  hint: <actionable suggestion>
--- captured <build|run> <stdout|stderr> (segment <index>/<count> (<executable>))
<captured output>
```

行号和列号从 1 开始，对应原始 Markdown 中的位置，包括列表和引用块前缀。
列号按 UTF-16 码元计数：制表符计为一个，`😀` 计为两个。
无法确定精确源码区间时，可能高亮整条已知源码行，并省略列号。

解析诊断可以显示源码片段，用 `⟦…⟧` 标出相关文本；空的 `⟦⟧` 表示没有选中
字符的定位点。关联位置通过 `note` 展示，并在可用时附上对应源码片段。
源码中的制表符、控制字符和字面量 `⟦`/`⟧` 在片段中会被转义；
列号仍对应转义前的原始行。

仅打印可用字段。没有文档位置的参数错误省略文件前缀；没有命令的文档解析错误
省略命令行。主位置或关联位置的源码片段已经展示命令时，也不再单独打印命令行。
参数值校验错误包含选项名、实际值和有效值范围；参数解析器产生的
语法错误保留对应上下文的帮助文本。操作系统及依赖库的原因文本放在 `cause` 中，
措辞可能随环境变化。配置解析器的详细报告也作为原因展示。

构建、启动、远程工具保留状态码、输出读取和超时错误均保留已捕获日志。
最后一段 stdout 与各段未合并的 stderr 分别标注来源，按最终 stdout、各段 stderr
的顺序展示。空日志省略，日志不截断，不重复展示成功构建的产物信息。
仍未读到 EOF 的非空日志标题带有 `; partial`，表示仅包含当时已经读到的字节。
无效 UTF-8 的错误报告指出读取的流及管道端点，诊断日志以完整的字节转义形式
展示并标记 `; escaped bytes`。

直接管理的进程取消并回收期间，仍会收集可用的日志输出。
普通错误的进程清理完成后，最多再收集 100 ms 的日志，仍受原用例期限约束。
期限到达后不额外收集，不无限等待后代进程持有的管道句柄。
最先记录的错误作为主错误，日志读取及清理期间的次生错误不会覆盖它。

超时摘要继续包含 `timed out after N ms (including build)`，并附上最后的执行阶段、
构建目标或尚未完成的管道段。`moonx` 内部的下载和执行归入 `run` 阶段；所有程序
结束后仍在等待输出 EOF 时归入 `capture` 阶段。

颜色策略在文件发现之后计算一次：

- `always` 开启 mooncram 的颜色，即使存在 `NO_COLOR` 或 `TERM=dumb`。
- `never` 关闭 mooncram 的颜色。
- `auto` 在 `NO_COLOR` 存在时关闭颜色，即使其值为空；`TERM` 恰好等于 `dumb`
  时也关闭。其他情况下，仅当检查 `/dev/stdout` 得到字符设备时才开启颜色；
  检查出错则关闭。

`FAIL` 标题和差异中的删除行使用红色，新增行使用绿色。
汇总和 `ERROR` 前缀不着色。颜色选项不会移除被测程序输出的 ANSI 字节，
也不会控制程序自身的颜色策略。
