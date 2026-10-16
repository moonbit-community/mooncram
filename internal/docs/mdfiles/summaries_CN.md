# 计数、汇总与进程退出状态

## 先判断 mooncram 自身的退出码

这些退出码属于 mooncram 自身，与被测程序的预期退出码相互独立。
程序返回 `2` 可以通过以 `[2]` 结束的用例，全部用例通过时 `mooncram test` 返回 `0`。

| 退出状态 | 条件 |
| --- | --- |
| `0` | 帮助／版本或 `docs` 请求成功；`check` 至少检查一个用例且没有错误；`test` 至少执行一个用例、没有错误且全部通过；或 `update`／试运行完成且没有错误，无论此前是否不匹配。 |
| `1` | `test` 至少有一个不匹配用例，且没有错误。 |
| `2` | 参数或文件发现失败、记录了任何文档或用例错误，或者没有找到用例。 |

**CI 应使用 `test`。** `update --dry-run` 即使打印 `FAIL` 并提出修改，也可能返回 `0`。
成功预览或更新不表示断言通过；发生错误时，错误优先于不匹配。

## 汇总行与计数

处理完所有已发现文件后，正常汇总写入 stdout：

```text
<total> cases, <errors> errors
<total> cases, <failed> failed, <errors> errors
<total> cases, updated <updated>, <errors> errors
<total> cases, would update <updated>, <errors> errors
```

以上格式依次对应 `check`、`test`、`update` 和 `update --dry-run`。例如：

```text
3 cases, 0 errors
3 cases, 1 failed, 0 errors
3 cases, updated 1, 0 errors
3 cases, would update 1, 0 errors
```

| 计数 | 含义 |
| --- | --- |
| `total` | 尝试检查或执行的用例数，在处理每个用例之前递增。包含目标解析或执行错误用例；不包含配置指令和解析或模块／目录声明校验失败文档中的用例。 |
| `failed` | 执行完成但输出或退出状态不匹配的用例数。执行错误单独计数。仅在 `test` 汇总中打印。 |
| `errors` | 捕获到的用例目标解析或执行错误与文档读取、解析、声明校验、更新错误之和。一次解析或声明校验失败计为一个文档错误。 |
| `updated` | 已成功写入文档或可生成试运行差异的变化用例数，包括纯规范化及共享围栏变化涉及的所有用例。每个用例只计一次，不按文件或变更行计数。 |

被取消更新或写入失败的文档不计入 `updated`。
因此，更新可能打印了 `FAIL` 报告，但由于后续用例执行错误取消了该文档的编辑，
最终仍报告 `updated 0`。

即使没有尝试检查或执行用例，只要存在文档错误，也会打印汇总，
例如 `check` 的 `0 cases, 1 errors` 或 `test` 的 `0 cases, 0 failed, 1 errors`；
特殊的无用例消息只在 total 和 errors 均为零时使用。
参数或文件发现失败、帮助／版本请求、`docs`，以及这个无用例分支都不会
打印正常汇总。
