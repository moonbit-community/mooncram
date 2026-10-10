# mooncram CLI 行为规范

[English version](CLI_SPEC.md)

本文描述当前 `0.0.3` 版本模块的 CLI 已实现的行为，涵盖命令行、Markdown 输入格式、
进程执行、结果匹配、报告和更新。这是一份当前实现的说明，不是新增功能提案。
中英文版本采用相同的章节结构，应同步维护。

文中的 `mooncram` 示例围栏都包裹在更大的 Markdown 示例围栏中，因此这份规范
本身不会引入可执行用例。示例中的 `./hello.mbtx` 等路径仅用于说明。

## 1. 调用方式与命令行解析

```text
mooncram [global-options] test [paths...] [global-options]
mooncram [global-options] update [paths...] [global-options] [--dry-run]
mooncram (-h | --help)
mooncram (-V | --version)
mooncram help [test|update]
mooncram test (-h | --help)
mooncram update (-h | --help)
```

在仓库目录中，可以这样启动程序：

```text
moon run . -- test README.md
moon run . -- update examples --dry-run
```

这两个示例中的 `--` 用来分隔 `moon` 的参数与 mooncram 的参数。
后面还可以再使用一个 `--`，终止 mooncram 自身的选项解析。

| 命令 | 行为 |
| --- | --- |
| `test` | 执行用例，将路由后的输出和退出状态与预期结果比较。 |
| `update` | 执行相同的用例，将不匹配的预期结果替换为实际结果的表示。 |
| `update --dry-run` | 执行用例并打印拟议的文档变更，不写入变更。 |
| `help`、`-h`、`--help` | 向 stdout 打印对应帮助，以 `0` 退出，不发现文件或执行用例。 |
| `-V`、`--version` | 在顶层向 stdout 打印程序版本字符串和换行符，以 `0` 退出。 |

除帮助或版本请求外，必须指定子命令。空命令行是参数错误，不会隐式执行 `test`。
版本选项不能放在 `test` 或 `update` 后面，例如 `mooncram test --version`
会产生参数错误。

### 1.1 选项与默认值

| 选项 | 作用域 | 默认值 | 可接受的值与作用 |
| --- | --- | --- | --- |
| `--target VALUE` | 全局 | `wasm` | 仅接受 `wasm` 或 `native`；设置本地包用例的默认后端。 |
| `--timeout-ms N` | 全局 | `60000` | 正的有符号 32 位整数，单位为毫秒；每个用例的构建和执行共用一个期限。 |
| `--color VALUE` | 全局 | `auto` | 仅接受 `auto`、`always` 或 `never`；控制 mooncram 报告的颜色。 |
| `--dry-run` | 仅 `update` | 关闭 | 打印拟议的文档差异，不替换文档。不接受参数值。 |

全局选项可以位于子命令之前，也可以位于路径之前、路径之间或路径之后。
`--target native` 和 `--target=native` 均有效；其他带值选项也支持
`--name=value`。这些选项没有短别名。每个全局带值选项最多只能指定一次，
包括分布在子命令前后的情况；重复指定会报错，不会覆盖前一个值。
重复指定 `--dry-run` 会保持启用状态。

`--dry-run` 必须位于 `update` 之后，在顶层或 `test` 中均无效。
未知命令或选项、缺少选项值以及无效的值，都会导致退出状态 `2`。

`--timeout-ms` 只接受 ASCII 十进制数字，数值范围为 `1..2147483647`。
允许前导零，不接受正负号、空格、小数、零或溢出值。命令行解析完成后的值校验
依次检查 target、timeout 和 color。

`paths` 接受零个或多个值。未提供路径时使用 `.`。在子命令之后使用 `--`，
可以把其后的所有参数作为路径，包括以 `-` 开头的名称：

```text
mooncram --target native test docs README.md --color never
mooncram update docs --timeout-ms=120000 --dry-run
mooncram test -- -example.md
```

mooncram 不会自行展开路径通配符。启动它的 shell 若进行了展开，展开发生在 CLI
收到参数之前。围栏仅允许模块声明，目标后端和超时由 CLI 选项控制。

## 2. 文件发现与执行顺序

文件发现会在读取任何文档或执行任何用例之前全部完成。

1. 相对于 mooncram 的启动目录解析每个输入路径。
2. 递归遍历实际目录。枚举目录条目时，跳过名称以 `.` 开头的条目、文件系统 API
   判定为隐藏的条目，以及名称恰好为 `_build` 或 `target` 的条目。
   隐藏属性的判断包括 Windows 隐藏属性。
3. 选择遇到的路径以后缀 `.md` 结尾的普通文件，后缀区分大小写。
   直接指定其他后缀的普通文件也会被忽略。
4. 对遇到的路径以 `.md` 结尾的文件符号链接，若其目标是普通文件，则纳入处理。
   不遍历目录符号链接。
5. 将选中的文件解析为规范绝对路径，按这些路径去重，再按字典序排序。

跳过规则作用于遍历时枚举出的目录条目。显式指定的隐藏文件、隐藏目录、`_build`
或 `target` 不会仅因其名称被拒绝，其内容仍按正常发现规则处理。
去重依据是规范路径，不是文件内容或 inode 标识。后缀判断针对遇到的路径，因此
`alias.md` 符号链接可以选中一个实际名称具有其他后缀的普通文件。

输入不存在或文件发现期间发生文件系统错误时，整次运行以 `2` 终止；
已经发现的文件也不会执行。以 `.md` 结尾但无法检查目标的符号链接也可能导致
文件发现错误。

文档按排序后的规范路径依次执行，不受输入参数排列顺序影响。用例按文档顺序
串行执行。先前用例对文件系统的修改对后续用例可见；每个进程在规范文档所在目录
启动，继承 mooncram 的环境，并覆盖该用例生效的 export 变量。

只要其他文档包含用例，允许某个文档不包含用例。如果没有尝试执行任何用例，
也没有记录任何错误，CLI 会报告 `ERROR no mooncram cases found`，
以 `2` 退出，且不打印汇总。

## 3. Markdown 识别与用例边界

文档按 UTF-8 读取，解码失败属于文档错误。
Markdown 由 `cmark` 按结构解析，并保留源码位置和排版信息。
起始围栏使用反引号、语言名严格为 `mooncram` 的围栏代码块包含测试，
`mooncram-import` 围栏声明文件工具导入。语言名区分大小写。
`mooncram` 后面允许空白和一个模块名，例如 `mooncram user/foo`。
声明仅作用于当前围栏，普通围栏没有模块名。多个词、旧版 JSON 配置和非法模块名
在围栏起始行报文档解析错误。模块名和包名由非空的斜杠分隔组件组成，组件仅含
ASCII 字母、数字、`_`、`-` 或 `.`，不允许 `.` 和 `..` 组件。
符合 Markdown 语法的更长反引号围栏也有效。

其他语言、缩进代码块、波浪号围栏和更大示例代码块内看似围栏的文本会被静默忽略。
支持引用块和列表内的用例；Markdown 容器前缀不属于命令或输出。
mooncram 解析代码行之前，先应用 Markdown 的围栏缩进规则。

符合条件的围栏必须闭合，并且至少包含一条指令（export 也满足此要求）。
未闭合或为空的测试围栏会造成文档解析错误。被忽略的围栏不会产生 mooncram 解析错误。

````markdown
```mooncram user/foo
$ ./hello.mbtx "Moon Bit"
Hello, Moon Bit!

$ cmd/main --version
my-cli * (glob)
```
````

在解析后的代码块中：

- 恰好以 `$ ` 开头的行开始一条指令；export 设置环境，其他指令开始用例。
  只有 `$` 的行也会被识别为命令起始行，随后因命令为空而报错。
- 第一条命令之前只忽略完全为空的行，其他内容均报错。
  `$` 后面仅跟制表符不属于 `$ ` 命令前缀。
- 从命令之后到下一条命令或结束围栏之前的所有行都属于预期结果，
  但该区间末尾完全为空的行除外。
- 末尾空行用作分隔符，不纳入预期结果。剩余区间内部的空行属于实际输出行；
  仅包含空白字符的行不属于空行分隔符。
- 命令只能占一行。不支持多行命令续行、块内注释或独立的 setup/teardown 语法。

如果输出行看起来像命令，应使用 JSON 字符串加 `(escaped)` 表示。

执行某个文档中的任何用例之前，会先解析整个文档，包括所有命令和预期结果。
只要有解析错误，该文档的所有用例都不会执行，包括错误位置之前的用例。
后续文档仍会继续处理。报告中的行号从 1 开始，对应原始 Markdown 文档中的位置。

### 3.1 文件级工具导入

每份文档允许零个或一个 `mooncram-import` 围栏，语言名后不接受配置。
围栏识别规则与 `mooncram` 相同，支持较长反引号围栏、列表和引用；忽略波浪号
围栏和较大示例内部的围栏。有效导入围栏必须闭合且包含至少一条声明，允许空白行。
import 不计为用例；仅含 import 的文档合法，但整次运行仍遵循无用例报错规则。

每个非空白行必须为 `别名 : user/module[/package]@version`，声明及冒号两侧可有空白。
别名区分大小写，采用 `[A-Za-z_][A-Za-z0-9_-]*`，保留 `export`。坐标至少含两个
路径组件，遵循上面的模块／包名规则。版本必须是精确 SemVer `MAJOR.MINOR.PATCH`，
可追加 `-prerelease` 和 `+build`。核心数字与纯数字预发布标识不允许前导零；
构建标识允许前导零。标识仅含 ASCII 字母、数字和连字符，以点分隔，不允许空标识。
拒绝省略版本、`latest`、范围、通配符、默认参数和变量展开。

解析时先收集并校验所有 import，再按原顺序解析命令和 export。
`Document.imports : Map[String, ToolImport]` 保存别名对应的 `name`、`coordinate`
和从 1 开始的源码 `line`。绑定对该文档所有用例生效，与声明位置无关，不跨文件。
重复别名指出两条声明所在行；第二个 import 围栏是文档解析错误，指出两个起始位置。
其他非法输入定位到错误行或围栏起始行。

````markdown
```mooncram-import
moongrep : moonbit-community/moongrep@0.3.5
```
```mooncram
$ moongrep --version
* (glob)
```
````

## 4. 命令分词与可执行目标选择

起始 `$` 之后的文本会直接解析为管道段数组或单条 export 赋值，不会传给 shell。命令解析器返回派生 `Debug`、`Eq` 的
`Command::Pipeline(Array[PipelineSegment])` 或
`Command::Export(name~ : String, value~ : String)`。
可选的 `lookup` 回调用于查询变量；未提供时，引用的变量均视为未定义。
返回的参数及赋值已经完成展开。`PipelineSegment` 包含 `argv : Array[String]`、
`stderr_to_stdout : Bool` 和 `stdout_to_null : Bool`，派生 `Debug`、`Eq`。
未出现对应标记时两个布尔值均为 `false`；`Case.pipeline` 存储这些段结构。

| 语法 | 含义 |
| --- | --- |
| 未加引号且未转义的 `\|` | 分隔管道段，两侧可以没有空格。 |
| 未加引号的空格或制表符 | 分隔参数，连续分隔符被忽略。 |
| `'text'` | 下一个单引号之前的内容均为字面量，反斜杠也不转义。 |
| `"text"` | 读取到下一个未转义的双引号。 |
| 单引号之外的反斜杠 | 将紧随其后的一个字符作为字面量，双引号内部也适用。 |
| `''` 或 `""` | 保留一个空参数。 |
| 相邻的引号片段与非引号片段 | 拼接为同一个参数，例如 `a"b"c` 变为 `abc`。 |
| 单引号之外且 `$` 未转义的 `${NAME}` | 展开环境变量；结果不重新分词或递归展开。 |

反斜杠不解释 C 或 JSON 转义序列：单引号之外的 `\n` 表示 `n`，不是换行符。
末尾反斜杠、未闭合引号，以及命令中的 NUL、CR 或 LF 都会导致解析错误。

空管道段（包括开头或结尾的 `|`、`||`）会导致解析错误。引号内或转义的 `|`
是普通参数字符。例如支持：

```text
$ ./producer.mbtx|cmd/filter|./consumer.mbtx
```

除下述精确的尾部重定向标记外，未加引号的 `&`、`;`、`<`、`>`、反引号、
`(` 和 `)`，无论出现在单词的哪个位置，都会被拒绝。通过引号或转义可以将它们作为普通字符传入。
不进行通配符展开、波浪号展开或命令替换。例如 `'$HOME'`、`*` 和 `~`
都是字面量参数；`'$(cmd)'` 也是字面量，但未加引号的 `$(cmd)` 会因圆括号报错。

每段（包括单命令）接受以下尾部标记：

| 标记 | 原 stdout | 原 stderr |
| --- | --- | --- |
| 无 | 下一段或最终捕获 | 诊断 stderr |
| `2>&1` | 下一段或最终捕获 | 同一输出管道 |
| `>/dev/null` | 丢弃 | 诊断 stderr |
| 两者组合，任意顺序 | 丢弃 | 下一段或最终捕获 |

标记内部不能有空格或制表符，与前面的命令、参数或其他标记之间必须有至少一个
空格或制表符；后面的 `|` 无需空白。每种标记最多出现一次，出现标记后该段不能
再接普通参数。缺少命令、重复标记、内部空白、其他重定向形式及 export 重定向
都是解析错误，保留文档文件名和命令行号。

分词阶段按原文中的精确标记分类，在变量展开之前完成。完整引用、正确转义的
标记及变量展开产生的标记文本保持普通参数语义。字面量 `2>&1` 必须引用或写成
`2\>\&1`，同时转义 `>` 和 `&`；字面量 `>/dev/null` 可以写成 `\>/dev/null`。
旧写法 `stdout>/null` 和 `stderr>/stdout` 会被拒绝。不根据展开后的 argv 判断
重定向。例如：

```text
$ ./producer.mbtx >/dev/null 2>&1|cmd/filter
```

`$ export NAME=value` 每条指令设置一个变量，按第一个字面量 `=` 分隔赋值。
变量名必须匹配 `[A-Za-z_][A-Za-z0-9_]*`，且不能包含变量引用；允许空值及额外的 `=`。
值遵循参数的引号和展开规则。缺少赋值、非法变量名、额外参数，以及管道中的 export
均为解析错误。export 不接受预期输出或退出码，后接非空预期区间会报解析错误；
允许空白分隔行。export 不计入用例数，仅含 export 的围栏合法；整次运行没有实际
用例时仍沿用现有的无用例错误行为。

export 按文档顺序生效，可跨同一文档内的有效代码块；切换文档后重置。
变量先查询此前的文档级 export，再查询父进程环境。已设置的空字符串有效，覆盖
父环境；自引用读取赋值前的值。每个实际用例保存独立的
`extra_env : Map[String, String]` 快照，命令原文保留用于报告、update 和 dry-run。

Windows 下导出赋值、引用查询和后续覆盖均不区分变量名大小写。导出名和查询键
统一转为 ASCII 大写，不同大小写的再次赋值覆盖同一个快照条目，传给子进程时
每个导出变量只有一个条目。Linux 和 macOS 下变量名仍区分大小写。
自引用和空值同样遵循这些规则。

仅识别 `${NAME}`，`$NAME` 保持字面量。未加引号及双引号中的引用会展开，
单引号内和美元符号被转义的引用保持字面量。展开只进行一次，不重新分词：
结果中的空格、引号、`|` 或另一个 `${NAME}` 均属于原参数。空结果仍保留一个参数，
`prefix${NAME}suffix` 会拼接为同一个参数。未定义变量、非法或未闭合引用均为带文件
行号的文档解析错误。整个文档解析成功后才执行用例。

每个管道段的首个词选择执行目标，禁止在其中展开 `${NAME}`，即使变量已定义也会
报解析错误；单引号或转义保护的引用可作为字面路径。作为普通参数传入的文件路径
遵循参数展开规则。

每个段的第一个参数不能为空。普通 `mooncram` 围栏可以执行文件导入别名或普通 `.mbtx` 文件。
脚本路径相对于规范 Markdown 文件所在目录解析，也接受绝对脚本路径。
声明模块的围栏同样允许脚本。

执行文档内任何用例前，校验所有模块声明，要求与 mooncram 启动 cwd 下的
`moon.mod` 的 `name` 精确匹配，包括仅含 export 的围栏。配置缺失、解析失败或
名称不符属于文档错误，在声明围栏的起始行报告。不向父目录搜索，不加载注册表模块。
`Case.module_name` 保存可选模块名；`Document.module_declarations` 保存声明和起始行。
执行上下文保存模块名、启动根目录和源码根目录。

声明围栏允许相对于模块 `source` 的可执行包名。`source` 缺失、为空或 null 时
使用模块根目录；其他值必须解析到模块根目录内的子目录。
对于 `user/foo`，`cmd/boo` 对应 `user/foo/cmd/boo`。短名称 `foo` 优先考虑根包
`user/foo`，其次考虑同名子包 `user/foo/foo`。可调用包通过
`pkgtype(kind: "executable")` 或旧的 `is-main: true` 声明。仅子包可调用时选择子包，
双方可调用时选择根包；双方都不可调用时报错。选中包编译失败或不支持目标后端时
直接报错，不回退。

每个发生歧义的管道段向 mooncram 的 stderr 独立输出一次 `WARNING`，包含文档位置、
两个完整包名和选择结果。警告不进入捕获输出、不匹配诊断、更新内容或错误计数。
包名不接受绝对目录、`./`、`../`、路径穿越，也不得跨入其他 `moon.mod` 或
`moon.mod.json` 界定的嵌套模块，符号链接也遵循此限制。
`moon.pkg` 使用 `moonbitlang/moon_config@0.4.2` 解析，兼容以 JSON 读取
`moon.pkg.json`；配置解析失败会报错。任意二进制、shell 命令、`.mbt` 文件和
未声明导入的注册表模块不能作为用例目标，也不会通过 `PATH` 查找目标。
其余参数会转发给被测程序，因此程序自己的 `--version` 或 `--target`
不会被解释为 mooncram 选项。

每个管道段独立用首个参数查询 `Document.imports`。命中别名时，执行
`moonx --target wasm <coordinate> -- <args...>`；保留 `Case.command` 与已解析的
管道结构。导入工具继承用例的 cwd、环境快照和输出路由。CLI `--target` 仍控制本地包，
导入工具始终使用 Wasm。模块声明围栏内按本地解析规则探测同名候选，包括根包短名和
同名子包；任一候选可执行，就在管道启动前报错，要求更换 import 别名。本地配置读取
或解析失败正常传播，不能视为“找不到包”。未命中别名的段保持原有解析行为。
远程包仅能通过已声明别名访问。

## 5. 构建、执行、输出捕获与超时

mooncram 使用外部 MoonBit 工具。构建本地用例需要 `moon`；脚本和导入还需要 `moonx`，
Wasm 包需要 `moonrun`，原生包构建需要对应的原生工具链。
运行 mooncram 自身所用的后端，与用例选择的后端相互独立。

以下参数数组使用解析后的绝对路径，尖括号中的内容是占位符，不是 shell 语法：

| 用例类型 | 构建预检查 | 程序调用 |
| --- | --- | --- |
| `.mbtx` 脚本 | `moon run --build-only --target wasm <script>` | `moonx <script> -- <args...>` |
| Wasm 包 | `moon -C <module-root> run --build-only --target wasm <package>` | `moonrun <artifact> -- <args...>` |
| 原生包 | `moon -C <module-root> run --build-only --target native <package>` | `<artifact> <args...>` |
| 导入包 | 无；moonx 获取并构建 | `moonx --target wasm <coordinate> -- <args...>` |

脚本始终使用 Wasm，即使 CLI 指定了 `native`。
mooncram 按段顺序为每个用例的所有本地段请求构建，是否复用已有构建由底层工具决定。
只有所有本地段通过构建预检查后，才会启动任何被测程序。
脚本在运行 `moonx` 之前先进行编译预检查，因此预检查的编译失败不会被接受为
程序的预期退出状态。

成功构建的 stdout 必须是 JSON，其中 `artifacts_path` 为恰好包含一个字符串的
数组。允许对象包含其他字段。相对产物路径以文档目录为基准解析。
脚本预检查也会验证该响应，不过传给 `moonx` 的仍是脚本路径。
构建退出状态非零、JSON 无效或产物数组缺失／无效，都属于执行错误。
构建错误诊断会包含构建的 stdout 和 stderr；成功构建的输出不属于程序预期结果。

管道各段并发执行，系统管道将前一段路由后的输出原始字节传入后一段 stdin，
中间不进行解码或换行规范化。仅捕获最后一段路由后的输出并与预期比较。
未重定向的 stderr 并发读取、完整缓存，再按段顺序拼接用于不匹配时的诊断，
不参与匹配。`2>&1` 将 stderr 与路由后的 stdout 连到同一根系统管道，
保留管道写入顺序，不再收集到诊断；两种标记同时出现时，仅原 stderr 使用输出
管道。`>/dev/null` 使用固定 8 KiB 字节缓冲区并发排空原 stdout，不累积或解码。
两条流都不使用输出管道时，立即关闭其未使用的写端，让下游或最终捕获读到 EOF。
构建进程始终使用默认路由。
所有捕获流都必须能够成功解码。管道默认采用 pipefail：等待所有段结束后，
全部成功返回 `0`，否则返回管道位置最右侧的非零退出码，不受完成顺序影响。
普通非零状态仍可通过 `[N]` 断言，后续用例继续执行；导入的保留错误状态遵循下面的规则。
当前没有可配置的输出大小上限，也不实时转发程序输出。

构建进程及每个管道段继承 mooncram 的环境，并覆盖该用例的 export 快照；
工作目录是规范文档的父目录。
构建进程和管道首段从 stdin 立即读到 EOF，不会读取 mooncram 的交互式输入。
后续段接收前一段路由后的输出。

捕获到的输出必须是有效 UTF-8。任一捕获流中出现无效 UTF-8 都会导致执行错误。
被丢弃的 stdout 无需为有效 UTF-8，中间路由字节保持未解码。
比较和报告前会把每个 CRLF 规范化为 LF。独立的 CR、NUL、ANSI 转义、行尾空格、
空行以及末尾是否有换行符，除此之外均保持有意义的差异。

每个用例共用一个期限，覆盖路径检查、构建、远程获取、执行和输出捕获。不会为每个子进程重新
开始计时，也不是整次运行共用一个超时。到期后，以
`timed out after N ms (including build)` 报告执行错误。
直接管理的进程使用强制取消。启动或捕获错误也会取消所有已启动段，
退出时会关闭所有未消费的管道句柄。当前实现不保证清理脱离管理的后代进程或回滚其影响。
文件发现、文档解析、报告和文档替换不在这个按用例计算的期限内。

用例以调用者的权限，在实际文档目录中执行代码。mooncram 不提供沙箱或临时
工作区隔离。`test` 和 `update --dry-run` 也遵循这一规则。

仅导入命令将 `255` 和 `-1` 保留为执行错误，包括导入程序自身返回这些状态。
并发监视所有段的退出状态；任意导入段返回保留状态都会报错，包含别名、坐标、
从 1 开始的管道段序号和状态码，并立即取消及回收其他进程。末段成功不能掩盖前段
保留错误，等待慢速前段也不能延迟发现后段错误。其他状态遵循上述 pipefail 规则。
保留状态、启动／捕获失败及超时均阻止整份文档
更新及生成试运行文档差异。

mooncram 不增加远程依赖安装或缓存机制。moonx 启动后负责获取、构建和缓存，
因此其他段可能在远程获取失败前已经运行并产生副作用；不保证获取失败前没有程序
副作用。远程获取与本地构建、执行共用已有用例期限。`test`、`update` 和
`update --dry-run` 使用相同执行流程。

## 6. 预期结果、逐行匹配与退出状态

只有以下条件全部满足，用例才会通过：

1. 程序退出状态相同。
2. 路由后的输出行数相同。
3. 每个对应输出行都满足该行的匹配规则。
4. 最后一个输出行是否缺少换行符的状态相同。

默认预期退出状态为 `0`。去掉末尾空行分隔符后，如果最后一行严格符合 `[N]`
形式，它就指定预期的有符号 32 位退出状态。`N` 是 ASCII 数字，前面可以有一个
`-`；`+`、内部空格或其他内容不会构成退出状态标记。允许前导零。
语法符合数字标记、但数值超出整数范围时，会产生解析错误。
出现在更早位置的类似状态标记的行按普通输出处理。负数状态表示进程库报告的信号
终止状态。除导入的 `255` 和 `-1` 外，非零退出状态是可以匹配的正常结果；构建失败或超时则不是。

没有预期输出行时，要求选定输出为空。空输出、一个换行符，以及末尾没有换行符的
非空行，是不同的结果：

| 实际选定输出，以 JSON 表示 | 预期文本 |
| --- | --- |
| `""` | 不写输出行。 |
| `"\n"` | 一行 `"" (escaped)`。 |
| `"hello\n"` | `hello` |
| `"hello"` | `hello (no-eol)` |
| `"hello\n\n"` | 一行 `hello`，后跟一行 `"" (escaped)`。 |

### 6.1 输出注解

注解是区分大小写的后缀，其中包括用于分隔的 ASCII 空格。
注解之后如果还有行尾空格，它就不再是后缀。

| 后缀 | 语义 |
| --- | --- |
| 无 | 精确比较整行，包括空白字符。 |
| ` (escaped)` | 将前面的文本解析为完整 JSON 字符串，再精确比较。 |
| ` (glob)` | 使用下述 glob 语法匹配整行。 |
| ` (regex)` | 使用已安装标准库的 `Regex` 匹配整行。 |
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
`(no-eol)` 只能用于最后一个输出行，后面可以再跟最后的退出状态标记。
精确匹配的空行不能带 `(no-eol)`：空输出应通过省略输出行来表达。

````markdown
```mooncram
$ ./special.mbtx
"$ this is output" (escaped)
"[2]" (escaped)
"```" (escaped)
"\u001b[31mred\u001b[0m" (escaped)
"" (escaped)
final text (no-eol)
[3]
```
````

### 6.2 Glob 与正则表达式细节

Glob 按 Unicode 字符而非字节工作。`*` 匹配零个或多个字符，`?` 匹配一个字符，
字符集合和范围包括 `[abc]`、`[a-z]`、`[!a-z]` 和 `[^a-z]`。
`!` 或 `^` 只有位于集合开头时才表示取反。反斜杠转义下一个字符，在集合中也有效。
集合中的首个 `]` 可以作为字面量；`-` 不构成范围时也可以作为字面量，
例如 `[]-]` 匹配 `]` 或 `-`。反向范围、未闭合或空集合，以及不完整的转义都会报错。
这里不进行文件系统展开，也不特殊处理目录分隔符。

正则表达式按 `^(?:PATTERN)$` 编译，并且要求匹配结果的内容等于完整实际行。
这也会约束 `foo|bar` 等分支匹配。支持的正则语法和编译诊断由已安装的 MoonBit
标准库决定。无效模式属于文档解析错误。Glob 和正则匹配都不会跨越多个输出行。

## 7. 报告与颜色

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

错误写入 **stderr**：

| 错误范围 | 报告形式 |
| --- | --- |
| 参数或文件发现 | `ERROR <message>` |
| 文档读取、解析或更新 | `ERROR <canonical-file>: <message>` |
| 单个用例执行 | `ERROR <canonical-file>:<command-line>: <message>`，随后打印缩进后的命令。 |

参数解析错误包含对应上下文的帮助文本。文档解析错误消息本身已包含文件和源码行号；
当前外层文档错误处理还会再添加一次文件前缀。依赖库、操作系统的错误措辞和构建
诊断会直接传递，因此可能随环境变化。

颜色策略在文件发现之后计算一次：

- `always` 开启 mooncram 的颜色，即使存在 `NO_COLOR` 或 `TERM=dumb`。
- `never` 关闭 mooncram 的颜色。
- `auto` 在 `NO_COLOR` 存在时关闭颜色，即使其值为空；`TERM` 恰好等于 `dumb`
  时也关闭。其他情况下，仅当检查 `/dev/stdout` 得到字符设备时才开启颜色；
  检查出错则关闭。

`FAIL` 标题和差异中的删除行使用红色，新增行使用绿色。
汇总和 `ERROR` 前缀不着色。颜色选项不会移除被测程序输出的 ANSI 字节，
也不会控制程序自身的颜色策略。

## 8. 更新结果的生成与保留规则

`update` 与 `test` 使用相同的解析、执行、比较和失败报告逻辑。
只有不匹配的用例才会生成编辑，通过的用例保持原样。
编辑仅替换命令之后的预期结果区间，保留命令、围栏、周围正文和分隔行。

对于索引为 `i` 的实际输出行，生成结果时会先尝试保留同一索引位置的原有预期，
前提是该行的匹配器仍然匹配。这可以在其他行或退出状态失败时，继续保留有效的
glob、正则模式以及显式转义写法。裸空行，以及以 `[` 开头、以 `]`
结尾的原始行会重新生成，以免产生分隔符或退出状态的歧义。
这里按行索引匹配，不会在输出的其他位置搜索相同文本。

需要新生成的精确输出行，如果为空，以空格、`$` 或 `[` 开头，包含反引号、
低于 U+0020 的控制字符或 U+007F，或者以已知注解后缀 ` (escaped)`、
` (glob)`、` (regex)`、` (no-eol)` 结尾，就会写为带 `(escaped)` 的 JSON 字符串。
其他行（包括未知括号后缀）按字面量写入。仅当需要时，最后一个输出行才带 `(no-eol)`。
实际状态非零时追加 `[N]`，为零则不需要状态标记。

对于替换结果的第 `i` 行，如果对应位置原先存在输出行，会复用该行的 Markdown
容器前缀和换行写法。新增的额外行使用命令行的前缀和换行符。
这会按源码位置保留列表、引用排版，以及 LF、CRLF、CR 等换行写法，
包括混合换行符。编辑区间之外的文本保持原样，包括文档末尾没有换行符的情况。

在试运行模式中，每个存在可用编辑的文档还会额外打印：

```text
--- <canonical-file>
+++ <canonical-file> (updated)
<document diff hunks>
```

文档差异与单个用例的失败报告都会打印。试运行不会替换文档，也不会执行最后的
源码复核和写入流程，但仍会构建并运行每个用例，因此程序副作用和构建产物仍然可能产生。

## 9. 错误隔离与安全替换

单个用例执行出错后，同一文档中的后续用例仍会执行。
但是，只要出现执行、构建或超时错误，该文档的**所有**预期结果编辑都会被取消。
如果此前已经收集了编辑，还会向 stderr 打印：

```text
Not updating <canonical-file>: execution errors in this document
```

试运行中的拟议文档差异也遵循同样的取消规则。解析错误则会直接阻止整个文档的执行。
某个文档出错不会阻止其他已发现文档继续运行和更新，也不会撤销之前的文档更新
或程序副作用。

对于有编辑、且没有用例执行错误的实际更新，mooncram 会：

1. 在文档同目录下排他创建 `.mooncram-<stamp>-<attempt>.tmp` 临时文件，
   最多尝试 100 个名称。
2. 写入更新后的文档，同步文件并关闭。
3. 重新读取目标文件，将内容与最初读取的源码比较。
4. 如果内容已变化，拒绝替换，并报告
   `source changed during execution; refusing to update <path>`。
5. 否则在同一文件系统内，把临时文件重命名以替换目标。
   退出这段流程时会尝试删除临时文件，错误路径也会执行清理。

替换以单个文件为单位保持原子性，跨文档更新不是事务。
内容检查不是文件锁，检查与重命名之间仍有时间窗口。
文件符号链接在发现阶段已经解析，所以替换作用于规范文档路径。
原始权限、inode 标识、硬链接关系和扩展元数据不会被保留。
在 Unix 上，新文件使用 `0644` 权限并受 umask 影响；文件系统库在 Windows
上忽略这个权限参数。

## 10. 计数、汇总与进程退出状态

处理完所有已发现文件后，正常汇总写入 stdout：

```text
<total> cases, <failed> failed, <errors> errors
<total> cases, updated <updated>, <errors> errors
<total> cases, would update <updated>, <errors> errors
```

例如：

```text
3 cases, 1 failed, 0 errors
3 cases, updated 1, 0 errors
3 cases, would update 1, 0 errors
```

| 计数 | 含义 |
| --- | --- |
| `total` | 尝试执行的用例数，在执行之前递增。包含执行错误用例；不包含 export、import 和解析或模块声明校验失败文档中的用例。 |
| `failed` | 执行完成但输出或退出状态不匹配的用例数。执行错误单独计数。仅在 `test` 汇总中打印。 |
| `errors` | 捕获到的用例错误与文档读取、解析、模块声明校验、更新错误之和。一次解析或声明校验失败计为一个文档错误。 |
| `updated` | 已成功写入文档中的不匹配用例数，或试运行中可生成文档差异的不匹配用例数。计量单位是用例，不是文件或变更行。 |

被取消更新或写入失败的文档不计入 `updated`。
因此，更新可能打印了 `FAIL` 报告，但由于后续用例执行错误取消了该文档的编辑，
最终仍报告 `updated 0`。

| 退出状态 | 条件 |
| --- | --- |
| `0` | 帮助／版本请求成功；或至少执行了一个用例、没有错误且 `test` 的预期全部通过；或 `update`／试运行完成且没有错误，无论此前是否不匹配。 |
| `1` | `test` 至少有一个不匹配用例，且没有错误。 |
| `2` | 参数或文件发现失败、记录了任何文档或用例错误，或者没有找到用例。 |

错误优先于不匹配。即使没有尝试执行用例，只要存在文档错误，也会打印类似
`0 cases, 0 failed, 1 errors` 的汇总；特殊的无用例消息只在 total 和 errors
均为零时使用。参数或文件发现失败、帮助／版本请求，以及这个无用例分支都不会
打印正常汇总。以上状态属于 mooncram 自身，与被测程序的预期退出状态相互独立。

## 11. 实现与验证索引

| 行为 | 实现 | 现有验证 |
| --- | --- | --- |
| 入口与参数 | [main.mbt](../main.mbt)、[cli/cli.mbt](cli/cli.mbt)、[cli/run.mbt](cli/run.mbt) | [cli/cli_wbtest.mbt](cli/cli_wbtest.mbt) |
| 调度、计数与错误隔离 | [cli/runner.mbt](cli/runner.mbt) | [tests/integration.mjs](../tests/integration.mjs) |
| 文件发现与原子替换 | [files/files.mbt](files/files.mbt)、[files/path.mbt](files/path.mbt) | [files/files_test.mbt](files/files_test.mbt) |
| Markdown 与命令 | [markdown/markdown.mbt](markdown/markdown.mbt)、[markdown/command.mbt](markdown/command.mbt) | [markdown/parser_wbtest.mbt](markdown/parser_wbtest.mbt) |
| 文件级工具导入 | [markdown/imports.mbt](markdown/imports.mbt)、[markdown/types.mbt](markdown/types.mbt) | [markdown/imports_wbtest.mbt](markdown/imports_wbtest.mbt)、[tests/integration.mjs](../tests/integration.mjs) |
| 执行与产物解析 | [execute/execute.mbt](execute/execute.mbt)、[execute/module.mbt](execute/module.mbt) | [execute/module_wbtest.mbt](execute/module_wbtest.mbt)、[execute/execute_wbtest.mbt](execute/execute_wbtest.mbt)、[tests/integration.mjs](../tests/integration.mjs) |
| 匹配与输出生成 | [output/expectation.mbt](output/expectation.mbt)、[output/glob.mbt](output/glob.mbt)、[output/render.mbt](output/render.mbt) | [output/matcher_test.mbt](output/matcher_test.mbt)、[update/update_test.mbt](update/update_test.mbt) |
| 报告与局部编辑 | [report/report.mbt](report/report.mbt)、[update/update.mbt](update/update.mbt) | [report/report_test.mbt](report/report_test.mbt)、[update/update_test.mbt](update/update_test.mbt) |

CLI 的帮助、选项解析和正则细节还依赖已安装的 MoonBit 标准库；进程和文件系统
细节依赖项目声明的依赖库。这些依赖发生变化时，更新规范前应同时核对项目源码
和可观察行为。

现有项目检查命令如下：

```text
moon test
node tests/integration.mjs
moon info && moon fmt
```

集成测试默认分别运行 Wasm 和 native 两种 mooncram 可执行程序，并使用真实的
脚本和包进行验证。传入 `--target wasm` 或 `--target native` 可以只选择一种
CLI 后端；这些是集成测试运行器的选项，与 mooncram 的用例后端选项相互独立。

导入集成测试以本地构建的 fixture 可执行文件替代 moonx，不依赖注册表或网络状态，
验证固定 Wasm 调用参数、保留错误状态及取消回收行为。
