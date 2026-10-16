# Markdown 识别与用例边界

文档按 UTF-8 读取，解码失败属于文档错误。
起始围栏使用反引号、语言名严格为 `mooncram` 的围栏代码块包含测试。语言名区分大小写。
`mooncram` 后面允许空白和一个模块名，例如 `mooncram user/foo`。
声明仅作用于当前围栏，普通围栏没有模块名。多个词或非法模块名
在围栏起始行报文档解析错误。模块名和包名由非空的斜杠分隔组件组成，组件仅含
ASCII 字母、数字、`_`、`-` 或 `.`，不允许 `.` 和 `..` 组件。
符合 Markdown 语法的更长反引号围栏也有效。

其他语言、缩进代码块、波浪号围栏和更大示例代码块内看似围栏的文本会被静默忽略。
支持引用块和列表内的用例；Markdown 容器前缀不属于命令或输出。
mooncram 解析代码行之前，先应用 Markdown 的围栏缩进规则。

符合条件的围栏必须闭合，并且至少包含一条测试命令或工作目录声明。
未闭合或为空的测试围栏会造成文档解析错误。被忽略的围栏不会产生 mooncram 解析错误。

## 完整的本地示例

先安装 `mooncram`，并确保 `moon`、`moonx` 和 `moonrun` 位于 `PATH`。
在新建的 `demo` 目录中创建以下文件。本例无需仓库副本或外部依赖。

```text
demo/
├── moon.mod
├── cmd/main/
│   ├── moon.pkg
│   └── main.mbt
└── tests/
    ├── hello.mbtx
    └── cases.md
```

`moon.mod` 的完整内容：

```text
name = "user/foo"
```

`cmd/main/moon.pkg` 的完整内容：

```text
import { "moonbitlang/core/env" }

pkgtype(kind: "executable")
```

`cmd/main/main.mbt` 的完整内容：

```mbt
fn main {
  if @env.args().get(1) is Some("--version") {
    println("my-cli 1.0.0")
  } else {
    println("my-cli")
  }
}
```

`tests/hello.mbtx` 的完整内容：

```mbt
import { "moonbitlang/core/env" }

fn main {
  let name = @env.args().get(1).unwrap_or("World")
  println("Hello, \{name}!")
}
```

`tests/cases.md` 的完整内容（不要复制外层 `markdown` 围栏）：

````markdown
```mooncram user/foo
$ moonx ./hello.mbtx "Moon Bit"
Hello, Moon Bit!

$ moonx user/foo/cmd/main --version
my-cli 1.0.0
```
````

从 `demo` 目录运行：

```sh
mooncram check tests/cases.md
mooncram test tests/cases.md
```

`check` 打印 `2 cases, 0 errors`，`test` 打印 `2 cases, 0 failed, 0 errors`，
两者均以 `0` 退出。脚本相对于 `tests` 解析；mooncram 从 `demo` 启动，
所以模块声明使用 `demo/moon.mod`。

## 用例边界

在解析后的代码块中：

- 恰好以 `#cwd(` 开头的行开始工作目录声明，并结束此前的预期输出区间；
  声明必须是第一条非空逻辑行。
- 恰好以 `$ ` 开头的行开始一条命令和用例。
  只有 `$` 的行也会被识别为命令起始行，随后因命令为空而报错。
- 第一条命令之前只接受完全为空的行和合法的工作目录声明，其他内容均报错。
  `$` 后面仅跟制表符不属于 `$ ` 命令前缀。
- 从命令之后到下一条命令、工作目录声明或结束围栏之前的所有行都属于预期结果，
  但该区间末尾完全为空的行除外。
- 末尾空行用作分隔符，不纳入预期结果。剩余区间内部的空行属于实际输出行；
  仅包含空白字符的行不属于空行分隔符。
- 命令只能占一行。不支持多行命令续行、块内注释或独立的 setup/teardown 语法。

如果输出行看起来像命令，或以 `#cwd(` 开头，应使用 JSON 字符串加 `(escaped)` 表示。

执行某个文档中的任何用例之前，会先解析整个文档，包括所有命令和预期结果。
只要有解析错误，该文档的所有用例都不会执行，包括错误位置之前的用例。
后续文档仍会继续处理。报告中的行号从 1 开始，对应原始 Markdown 文档中的位置。

## 远程包坐标

在测试围栏中直接使用 `$ moonx user/module[/package]@version <参数...>`。
坐标至少包含两个非空路径组件，遵循上面的模块／包名规则。
版本必须是精确 SemVer `MAJOR.MINOR.PATCH`，可追加 `-prerelease` 和 `+build`。
核心数字与纯数字预发布标识不允许前导零；构建标识允许前导零。
标识仅含 ASCII 字母、数字和连字符，以点分隔，不允许空标识。
目标解析时拒绝 `latest`、范围、通配符和非法版本。无版本目标属于本地包，
必须具有匹配的模块声明。远程坐标独立于围栏的模块声明；`check` 不检查其注册表存在性。

````markdown
```mooncram
$ moonx moonbit-community/moongrep@0.3.5 --version
* (glob)
```
````
