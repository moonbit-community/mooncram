# 预期结果、逐行匹配与退出状态

默认情况下，用例断言 **stdout 和程序退出码**，默认预期退出码为 `0`，不对 stderr
做断言。要检查 stderr，必须同时写出 `@STDOUT` 和 `@STDERR`，各一次：
用 `@STDOUT (ignore)` 只检查 stderr，或在 stdout 预期之外添加
`@STDERR (empty)`，要求 stderr 没有任何输出。

末尾 `[N]` 指定被测程序的预期退出码，与 mooncram 自身的退出码独立。
程序返回 `2` 可以通过以 `[2]` 结束的用例，全部用例通过时 `mooncram test` 返回 `0`。
构建失败和超时属于执行错误，不能作为程序退出码断言。

## 准备示例文件

下文的注解和双流示例共用一个脚本。确保 `mooncram`、`moon` 和
`moonrun` 位于 `PATH`。在新建的 `demo` 目录中创建以下文件，无需模块配置或仓库副本。
脚本固定了依赖版本，首次构建需要下载这些依赖。

```text
demo/
└── tests/
    ├── output.mbtx
    ├── escaped.md
    └── streams.md
```

`tests/output.mbtx` 的完整内容：

```mbt
import {
  "moonbitlang/async@0.22.4",
  "moonbitlang/async@0.22.4/stdio",
  "moonbitlang/core/env",
  "moonbitlang/x@0.5.5/sys",
}

async fn main {
  match @env.args().get(1).unwrap_or("result") {
    "result" => @stdio.stdout.write("result\n")
    "special" => {
      @stdio.stdout.write("$ this is output\n[2]\n```\n")
      @stdio.stdout.write("\u001b[31mred\u001b[0m\n\nfinal text")
      @sys.exit(3)
    }
    "--invalid" => {
      @stdio.stderr.write("error: invalid argument\n")
      @sys.exit(2)
    }
    _ => @sys.exit(3)
  }
}
```

从下文对应小节复制 `escaped.md` 和 `streams.md` 的完整内容，
不要复制最外层四反引号 `markdown` 围栏。

## 选择匹配策略

先使用精确输出和确定性输入，只放宽预期行为中确实允许变化的字段：

| 策略 | 使用场景 | 预期行示例 |
| --- | --- | --- |
| 精确匹配 | 文本、数值和空格应保持稳定；这是默认方式，变化会在审阅中明确呈现。 | `processed 3 files` |
| Glob | 某个字段可以是任意文本，但周围措辞必须稳定。 | `saved report-*.json (glob)` |
| Regex | 动态字段仍须符合特定格式或取值范围。 | `processed [0-9]+ files (regex)` |
| 转义后的精确匹配 | 固定输出含控制字符、有意义的空白或看似测试语法的文本。 | `"ready> " (escaped) (no-eol)` |

能控制输入时，优先使用固定测试数据而非模式。例如应当恰好处理三个文件时，
保留 `processed 3 files`；上表的正则也会接受错误的数量。
有意义的输出应避免整行 `* (glob)` 或 `.* (regex)`，它们可能掩盖标签变化、
空字段或错误消息。保留稳定前缀、分隔符和单位，并按契约尽量约束动态值。
模式仍然只断言一个输出行，额外输出行和末尾换行差异都会失败。

## 用例通过的条件

对于无标记用例，只有以下条件全部满足，用例才会通过：

1. 程序退出状态相同。
2. 最终 stdout 的输出行数相同。
3. 每个对应输出行都满足该行的匹配规则。
4. 最后一个输出行是否缺少换行符的状态相同。

默认预期退出状态为 `0`。去掉末尾空行分隔符后，如果最后一行严格符合 `[N]`
形式，它就指定预期的有符号 32 位退出状态。`N` 是 ASCII 数字，前面可以有一个
`-`；`+`、内部空格或其他内容不会构成退出状态标记。允许前导零。
语法符合数字标记、但数值超出整数范围时，会产生解析错误。
出现在更早位置的类似状态标记的行按普通输出处理。负数状态表示进程库报告的信号
终止状态。除远程包的 `255` 和 `-1` 外，非零退出状态是可以匹配的正常结果；构建失败或超时则不是。

没有预期输出行时，要求选定输出为空。空输出、一个换行符，以及末尾没有换行符的
非空行，是不同的结果：

| 实际选定输出，以 JSON 表示 | 预期文本 |
| --- | --- |
| `""` | 不写输出行。 |
| `"\n"` | 一行 `"" (escaped)`。 |
| `"hello\n"` | `hello` |
| `"hello"` | `hello (no-eol)` |
| `"hello\n\n"` | 一行 `hello`，后跟一行 `"" (escaped)`。 |

## 输出注解

注解是区分大小写的后缀，其中包括用于分隔的 ASCII 空格。
注解之后如果还有行尾空格，它就不再是后缀。

| 后缀 | 语义 |
| --- | --- |
| 无 | 精确比较整行，包括空白字符。 |
| ` (escaped)` | 将前面的文本解析为完整 JSON 字符串，再精确比较。 |
| ` (glob)` | 使用下述 glob 语法匹配整行。 |
| ` (regex)` | 使用本 CLI 支持的正则语法匹配整行，详见下文。 |
| ` (no-eol)` | 要求最后一个输出行没有终止 LF；位于匹配后缀之后（如果有）。 |

移除末尾 `(no-eol)` 后，只解释一个匹配后缀。例如
`"literal (glob)" (escaped)` 匹配字面量文本 `literal (glob)`。
未知括号后缀（包括 `(equal)`）作为普通文本参与精确匹配。例如，
`hello (equal)`、`hello (foo)` 和 `hello (glob) (foo)` 都按整行字面量匹配。
`hello (foo) (no-eol)` 匹配没有终止 LF 的 `hello (foo)`。
要按字面量匹配以已知注解结尾的文本，应使用 JSON 字符串加 `(escaped)`。
不支持可选行、重复行或跳过输出行的注解。

`(escaped)` 可以通过 JSON 转义表示控制字符和看似语法的输出。
解码后的值不能包含 LF；多个输出行必须分开写。
`(no-eol)` 只能用于每条流的最后一个输出行，后面可以再跟用例最后的退出状态标记。
精确匹配的空行不能带 `(no-eol)`：空输出应通过省略输出行来表达。

`tests/escaped.md` 的完整内容：

````markdown
```mooncram
$ moonx ./output.mbtx special
"$ this is output" (escaped)
"[2]" (escaped)
"```" (escaped)
"\u001b[31mred\u001b[0m" (escaped)
"" (escaped)
final text (no-eol)
[3]
```
````

从 `demo` 目录依次运行 `mooncram check tests/escaped.md` 和
`mooncram test tests/escaped.md`，分别打印 `1 cases, 0 errors` 和
`1 cases, 0 failed, 0 errors`，两者均以 `0` 退出。脚本的退出码 `3` 符合 `[3]` 预期。

## Glob 与正则表达式细节

Glob 按 Unicode 字符而非字节工作。`*` 匹配零个或多个字符，`?` 匹配一个字符，
字符集合和范围包括 `[abc]`、`[a-z]`、`[!a-z]` 和 `[^a-z]`。
`!` 或 `^` 只有位于集合开头时才表示取反。反斜杠转义下一个字符，在集合中也有效。
集合中的首个 `]` 可以作为字面量；`-` 不构成范围时也可以作为字面量，
例如 `[]-]` 匹配 `]` 或 `-`。反向范围、未闭合或空集合，以及不完整的转义都会报错。
这里不进行文件系统展开，也不特殊处理目录分隔符。

正则表达式必须匹配完整输出行，分支匹配也遵循此规则：`foo|bar` 匹配 `foo` 或
`bar`，不匹配 `foox` 或 `xbar`。无需自行添加 `^` 和 `$`。
Glob 和正则匹配都不会跨越多个输出行。

正则语法和诊断由构建当前 mooncram 可执行文件时包含的实现决定。
更新本机 MoonBit 工具链不会改变已有可执行文件的正则能力；需要新的 mooncram 构建才会改变。

本 CLI 支持以下常用写法：

| 预期行 | 可匹配的输出示例 | 含义 |
| --- | --- | --- |
| `item [0-9]+ (regex)` | `item 42` | 一个或多个 ASCII 数字。 |
| `v[0-9]+\.[0-9]+\.[0-9]+ (regex)` | `v1.2.3` | 以字面量点号分隔的数字版本组件。 |
| `status: (ok\|error) (regex)` | `status: ok` 或 `status: error` | 分组与分支。 |
| `colou?r (regex)` | `color` 或 `colour` | 可选字符。 |
| `[A-Za-z_][A-Za-z0-9_]* (regex)` | `name_1` | ASCII 标识符；`*` 允许后续字符出现零次或多次。 |
| `[[:digit:]]{2,4} (regex)` | `2026` | ASCII POSIX 字符类与有界重复。 |

预期行中直接书写反斜杠，例如上表的 `\.`。用 `[0-9]`、`[[:space:]]` 和
`[A-Za-z0-9_]` 分别替代 `\d`、`\s`、`\w`；这些简写及其大写形式均不支持。
POSIX 字符类按 ASCII 匹配。
也不支持前瞻断言、后顾断言和反向引用。无效模式属于文档解析错误；
可以运行 `mooncram check <file>` 校验，无需执行用例。

## stdout 与 stderr 双流断言

使用 `@STDOUT` 和 `@STDERR`，一次执行分别断言两个流：

`tests/streams.md` 的完整内容：

````markdown
```mooncram
$ moonx ./output.mbtx
@STDOUT
result
@STDERR (empty)

$ moonx ./output.mbtx --invalid
@STDOUT (ignore)
@STDERR
error: invalid argument
[2]
```
````

从 `demo` 目录依次运行 `mooncram check tests/streams.md` 和
`mooncram test tests/streams.md`，分别打印 `2 cases, 0 errors` 和
`2 cases, 0 failed, 0 errors`，两者均以 `0` 退出。

两个标记区分大小写，必须各出现一次，顺序任选。缺少配对、重复标记、首个标记
之前出现非空预期文本，或使用未知标记注解，都会产生带文件和行号的解析错误。
标记的形式严格为 `@STDOUT` / `@STDERR`，可加 ` (ignore)` 或 ` (empty)`。
要按字面量匹配标记形式的输出，请使用 JSON 字符串加 `(escaped)`，
例如 `"@STDOUT" (escaped)`。

普通区段复用精确匹配、glob、regex 和 escaped 规则；每个流分别处理最后一行的
`(no-eol)`。普通区段没有输出行时要求该流为空。`(ignore)` 跳过内容断言；
`(empty)` 要求恰好零个字符，即使只有一个换行符也会失败。
这两种注解区段不接受预期输出行。每个区段末尾的裸空行用作分隔符，
需要断言空输出行时使用 `"" (escaped)`。末尾的 `[N]` 属于整个用例，默认退出码为 `0`。

`@STDOUT` 检查最后一段的 stdout；`@STDERR` 检查所有段的 stderr，
按管道段顺序拼接，不添加分隔字节。
不比较两条流之间的时间顺序。忽略的流仍会捕获并进行 UTF-8 校验，
超时与进程回收规则保持一致。不含流标记的用例仅断言最后一段的 stdout 和管道退出码，
stderr 用于诊断。

两个流的约束和用例退出码必须全部满足。仅当严格的大写标记名后接行尾、空格或
制表符时识别为标记；后面的文本若不是严格支持的注解，则报解析错误。
`@stdout` 和 `@STDOUTish` 仍是普通输出。首个标记前允许裸空行分隔符。
普通区段内部的裸空行若后面仍有本区段的输出行，则属于输出。
较早位置的 `[N]` 是输出，仅用例最后一行设置退出码。
