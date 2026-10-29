# mooncram

[English](README.md)

mooncram是一个针对MoonBit命令行程序/mbtx脚本特化的命令行测试框架, 用 Markdown 中的示例测试 MoonBit 命令行应用和脚本。写下命令和预期输出，
再用几句话解释它的用途，mooncram 就能检查这个示例是否仍然有效。

mooncram 的设计**受 [scrut](https://facebookincubator.github.io/scrut/docs/) 启发**。
它将易于阅读的命令行测试带到 MoonBit，支持本地可执行包、独立的 `.mbtx`
脚本，以及 Mooncakes 上的工具。

## 为什么使用 mooncram？

单元测试验证函数；命令行测试验证使用者实际看到的行为：参数、输出、错误提示和退出码。

你可以测试一个问候脚本、命令的 `--version` 输出、无效参数，或多个 MoonBit
工具组成的管道。测试文件就是普通的 Markdown 文档，方便在示例旁说明测试意图。
当程序行为有意改变时，也可以让 mooncram 帮你更新预期输出。

## 运行测试前的规则

| 操作 | 规则 |
| --- | --- |
| 编写命令 | 命令不经过 Shell，参数中的环境变量和通配符保持字面量。 |
| 选择断言内容 | 默认只断言 stdout 和程序退出码；要断言 stderr，必须同时使用 `@STDOUT` 和 `@STDERR` 标记。 |
| 选择后端 | 脚本和远程包固定使用 Wasm；`--target` 为本地包选择后端。 |
| 解析路径 | 本地模块从启动目录直接包含的 `moon.mod` 读取；脚本和相对文件参数使用块工作目录，默认是文档目录，也可用 `#cwd` 指定。 |
| 执行或预览 | `test`、`update`、`update --dry-run` 都会以你的权限执行代码，没有沙箱或临时工作区隔离。默认每个用例的 60000 毫秒超时包含构建、远程获取、执行和输出捕获。 |
| 审阅更新 | 已通过的用例也会处理，预期和围栏可能被规范化。文档内任何执行错误都会阻止该文档的全部预期更新，其他文档仍可能更新。 |
| 判断退出码 | mooncram 自身的退出码与程序的预期退出码独立。dry-run 即使报告不匹配也可能返回 `0`；CI 应使用 `test`。 |

## 快速开始

先安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，
将其 `bin` 目录加入 `PATH`。每次 mooncram 调用选择首个可执行的 `moon`，
并按需使用同一安装中的 `moonrun` 和 `moonx`。

将mooncram作为一个命令安装

```sh
# 稳定版
moon install moonbit-community/mooncram
# 最新版
moon install https://github.com/moonbit-community/mooncram
# 打印帮助
mooncram --help
```

直接运行wasm版本的mooncram

```sh
# 最新的稳定版
moonx moonbit-community/mooncram@latest --help
# 指定版本
moonx moonbit-community/mooncram@0.1.1 --help
```

下文统一使用安装后的 `mooncram` 命令。

## 编写第一个测试

创建两个文件，放在同一目录下：

```text
tests/
├── hello.mbtx
└── hello.md
```

在 `tests/hello.mbtx` 中写一个简单的程序：

```mbt
---
import { "moonbitlang/core/builtin" }
---

fn main {
  println("Hello, MoonBit!")
}
```

在 `tests/hello.md` 中描述要验证的行为：

````markdown
# 问候语

脚本向使用者打招呼。

```mooncram
$ moonx ./hello.mbtx
Hello, MoonBit!
```
````

然后运行：

```sh
mooncram test tests/hello.md
```

以 `$ ` 开头的行是命令，后面的行是预期 stdout。未指定退出码时，预期为 `0`。
程序默认在测试文档所在目录中运行，因此 `./hello.mbtx` 就是旁边的脚本。

每条命令开始一个新用例。一篇文档可以包含多个代码块，中间可以加入标题和说明。
只有使用反引号围栏、标记为 `mooncram` 的代码块会执行。
下文中的示意测试文档放在更大的 `markdown` 围栏中，不会作为 README 自身的用例执行。

## 选择要运行的程序

### 本地脚本

显式写出 `moonx`，再跟 `.mbtx` 文件的相对或绝对路径。参数支持单引号、双引号和反斜杠转义。
对于支持传入名字的脚本，例如本仓库的 `examples/hello.mbtx`：

````markdown
```mooncram
$ moonx ./hello.mbtx "Moon Bit"
Hello, Moon Bit!
```
````

### 项目中的可执行包

在 `mooncram` 后面加上模块的完整名称。
假设 `moon.mod` 声明了 `name = "user/acme"`，可执行包位于 `cmd/acme`：

````markdown
```mooncram user/acme
$ moonx user/acme/cmd/acme --version
acme 1.0.0
```
````

请从包含该 `moon.mod` 的目录启动 mooncram。模块声明必须与配置中的名称完全一致，
且只作用于当前代码块。包必须是可执行包，例如在 `moon.pkg` 中声明
`pkgtype(kind: "executable")`。命令必须写出 `moonx` 和包含模块名的完整包名。
对于可执行的根包，使用 `moonx user/acme`。

mooncram 会先构建本地包，再运行程序，构建诊断不会混入待匹配的程序输出。
本地包默认使用 Wasm；运行 `mooncram test tests --target native` 可以测试原生后端，
这需要 C 工具链。独立脚本始终使用 Wasm。

目标后的所有参数直接传给程序，包括字面量 `--`。目标之前不解析 moonx 选项。

### Mooncakes 上的工具

直接使用 `moonx`、完整坐标和精确版本运行：

````markdown
```mooncram
$ moonx moonbit-community/mooncram@0.0.3 --version
0.0.3
```
````

坐标格式为 `user/module[/package]@version`，必须指定精确 SemVer 版本，
不接受省略版本、版本范围或 `latest`。

`moonx` 负责下载和缓存远程工具。远程工具始终使用 Wasm，
即使本地包选择了 `--target native`。

## 描述预期结果

### 输出与退出码

默认逐行精确匹配输出，包括空格。测试失败场景时，在最后一行写下预期退出码：

````markdown
```mooncram user/acme
$ moonx user/acme/cmd/acme --unknown
@STDOUT (empty)
@STDERR
error: unknown option --unknown
[2]
```
````

`@STDOUT` 和 `@STDERR` 可以在同一次执行中分别检查两个输出流。
使用时必须同时提供两个标记，且各出现一次。添加 `(empty)` 表示要求完全没有输出，
添加 `(ignore)` 表示不检查该流的内容。不使用标记时，只匹配 stdout；
测试失败时可以在诊断中查看 stderr。

命令后面没有预期输出行，表示要求 stdout 为空。如果只关心命令能否成功退出，
可以同时使用 `@STDOUT (ignore)` 和 `@STDERR (ignore)`。

### 灵活匹配输出

对于可能变化的输出，可以用 glob 或正则表达式匹配稳定的部分：

````markdown
```mooncram user/acme
$ moonx user/acme/cmd/acme --version
acme * (glob)

$ moonx user/acme/cmd/acme --version
acme [0-9]+\.[0-9]+\.[0-9]+ (regex)
```
````

| 后缀 | 检查内容 |
| --- | --- |
| 无 | 精确匹配整行 |
| ` (glob)` | 匹配整行，支持 `*`、`?` 和 `[a-z]` 等字符集合 |
| ` (regex)` | 用正则表达式匹配整行 |
| ` (escaped)` | 用 JSON 字符串表示精确输出，例如 `"a\tb"` |
| ` (no-eol)` | 最后一行没有结尾换行符；可接在其他后缀之后 |

每条预期匹配一行输出。输出看起来像测试语法时，用 JSON 转义，
例如 `"[2]" (escaped)`、`"$ this is output" (escaped)` 或
`"#cwd(output)" (escaped)`。
用 `"" (escaped)` 明确表示一个空输出行，尤其是最后的空行。
比较时会将 CRLF 统一为 LF；捕获的输出必须是合法 UTF-8。

尽量使用固定的输入文件：fixture 可以让测试重复运行时保持稳定，同时保留精确的断言。
对于确实需要变化的部分，例如生成的 ID 或版本号，再使用模式匹配。

## 配置测试环境

### 环境变量

命令继承启动 mooncram 时的环境。在命令前赋值可以为这一条命令设置变量。
由被测程序自行读取环境，例如 `environment.mbtx`：

```mbt
---
import { "moonbitlang/core/env" }
---

fn main {
  let name = @env.get_env_var("NAME").unwrap_or("World")
  println("Hello, \{name}!")
}
```

````markdown
```mooncram
$ NAME='Moon Bit' moonx ./environment.mbtx
Hello, Moon Bit!

$ NAME=World moonx ./environment.mbtx
Hello, World!
```
````

临时赋值只作用于当前管道段及其构建过程，后续命令继承原始环境。
mooncram 不展开环境变量：参数、赋值值、
可执行路径、工作目录及预期输出中的 `${NAME}` 和 `$NAME` 都是普通文本，
参数和赋值值仍遵循通常的分词、引号和转义规则。例如，`NAME=World moonx ./hello.mbtx "${NAME}"`
传入字面参数 `${NAME}`，同时子进程的环境变量 `NAME` 为 `World`。
若要将名字作为参数传入，请显式写出值，如 `moonx ./hello.mbtx World`。

### 工作目录与 fixture

默认情况下，程序在测试文档所在目录中运行。将 fixture 放在文档旁边，
就可以通过相对路径参数读取它。若要使用其他目录，将 `#cwd(路径)` 放在代码块的第一条非空逻辑行：

````markdown
```mooncram
#cwd(../examples)
$ moonx ./hello.mbtx "Moon Bit"
Hello, Moon Bit!
```
````

声明独占一行，每块最多一次，允许前导空行。路径为 `#cwd(` 与最后一个 `)` 之间的全部内容，
不去空格、不转义、不展开变量，也不检查括号配对。空格、反斜杠、引号和括号均原样保留：
`#cwd(../fixtures with spaces)` 无需引号，`#cwd("foo")` 的目录名包含双引号。
空路径、缺少结尾 `)`、重复声明或测试命令后的声明均报错。
以 `#cwd(` 开头的输出应使用 `(escaped)`，更新器也会自动转义。

路径相对于测试文档，目录必须已存在，设置仅作用于当前代码块。
本地模块仍从启动 mooncram 的目录查找。用例按文档顺序执行，
前一个用例创建的文件对后续用例可见。程序使用当前用户权限和现有文件系统，
mooncram 不会创建隔离的临时工作区。

### 管道

用 `|` 连接脚本、本地包或远程工具；每一段都必须显式写出 `moonx`：

````markdown
```mooncram user/acme
$ moonx ./input.mbtx | moonx user/acme/cmd/acme --uppercase
HELLO, MOONBIT!
```
````

管道各段并发运行，匹配最后一段的 stdout。
退出码采用 **pipefail** 规则：取最右侧的非零退出码，全部成功时为 `0`。
第一段的 stdin 会立即收到 EOF。

各段 stderr 分别捕获，并按管道段顺序拼接。使用 `@STDOUT` 和 `@STDERR`
检查两个输出流。所有段均拒绝输出重定向，包括 `2>&1` 和 `1>/dev/null`；
通过引号或转义可以将这些文本作为普通参数传入。

命令由 mooncram 自己解析，不经过 Shell。不支持 `echo`、`cat` 等 Shell 命令，
也不支持 `&&`、`;`、命令替换、输出重定向或多行 Shell 表达式。
需要准备数据等逻辑时，可以写进 MoonBit 脚本。

## 维护测试

如果程序改成了新的问候语，`test` 会显示预期输出与实际输出的差异。
确认新行为符合预期后，可以先预览，再更新：

```sh
mooncram update tests --dry-run
mooncram update tests
mooncram test tests
```

`update` 直接修改原文档中的预期，不会弹出确认提示。
它也会规范化已经通过的用例，并保留仍然匹配的 glob/regex 模式。
命令和周围说明文字会保留。文档存在解析、构建或执行错误时，不会更新该文档。
该文档中已通过用例的更新也会被阻止；其他文档仍可能更新。应用前应审阅完整差异。

`--dry-run` 展示拟议修改，不写入 Markdown，但仍会运行程序，程序本身可能修改文件。
如果只想校验而不执行，请运行：

```sh
mooncram check tests
```

`check` 校验语法、预期和本地目标解析，不构建、不下载工具，也不运行程序。
之后仍需用 `test` 验证编译和实际行为。
如果一个脚本由前面的用例生成，`check` 可能报告它不存在，因为检查时不会执行用例。

## 命令参考与 CI

```text
mooncram check [paths...] [--color auto|always|never]
mooncram test [paths...] [--target wasm|native] [--timeout-ms N]
mooncram update [paths...] [--target wasm|native] [--timeout-ms N] [--dry-run]
mooncram docs --list
mooncram docs <document-name>
mooncram --help
mooncram --version
```

Coding Agent 和其他工具可以直接读取程序内嵌的英文参考文档，无需访问本仓库。
运行 `mooncram docs --list` 查看主题名称和摘要，
`mooncram docs quickstart` 阅读完整入门示例，`mooncram docs recipes` 获取可运行的断言模板，
`mooncram docs troubleshooting` 查找排错步骤，`mooncram docs invocation` 读取命令行规范。
名称区分大小写，不带 `.md` 后缀。
不带参数的 `mooncram docs` 显示帮助。文档输出到 stdout，不着色，也不打印用例汇总；
未知名称或无效参数以 `2` 退出。

对于 `check`、`test` 和 `update`，可以传入文件、目录，或两者混用。
目录会递归查找 `.md` 文件，不传路径时扫描当前目录。
遍历时跳过隐藏条目、`_build` 和 `target`，不跟随目录符号链接。
文件去重并排序后，再执行其中的用例。

执行错误会附上可用的源码位置、阶段、管道段、工具和工作目录，并完整展示已捕获的
stdout/stderr。未读到 EOF 的流标记为 `partial`；非法 UTF-8 在诊断中以字节转义展示。
超时信息会指出最后的执行阶段。

默认后端为 `wasm`，每个用例的默认超时为 `60000` 毫秒，包括构建、下载、执行和输出捕获。
`check` 和 `docs` 不接受 `--target` 或 `--timeout-ms`。
`check`、`test` 和 `update` 接受 `--color`，默认 `auto`；
`docs` 不接受上述三个选项，始终输出纯文本。
用例选项必须放在相应子命令之后；顶层帮助和 `help` 没有用例选项。
`NO_COLOR` 会禁用自动着色。
路径以 `-` 开头时，在路径前加上 `--`。

在 CI 中安装工具链和 mooncram 后，运行 `mooncram test tests --color never`。
通过退出状态判断结果：

| 状态码 | 含义 |
| --- | --- |
| `0` | 文档查询、检查、测试或更新成功完成 |
| `1` | `test` 中有输出或退出码断言失败 |
| `2` | 参数无效，发生解析、构建或执行错误，或没有找到用例 |

`update --dry-run` 成功完成时返回 `0`，即使提出了修改。
CI 应使用 `test` 判断测试是否通过。上述退出码属于 mooncram 自身：
被测程序返回 `2` 可以通过以 `[2]` 结束的用例，全部用例通过时 `mooncram test` 返回 `0`。

## 延伸阅读

- [快速入门](internal/docs/mdfiles/quickstart_CN.md)
- [常见断言的完整模板](internal/docs/mdfiles/recipes_CN.md)
- [排错流程与症状表](internal/docs/mdfiles/troubleshooting_CN.md)
- [示例测试文档](examples/README.md)
- [命令行参考](internal/docs/mdfiles/invocation_CN.md)
- [scrut 文档](https://facebookincubator.github.io/scrut/docs/)：本项目的 Markdown 测试工作流及本指南的教程结构参考了它

## 许可证

[Apache-2.0](LICENSE)。
