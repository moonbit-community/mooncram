# 常见断言的完整模板

以下示例提供完整程序和测试文档，复制两个文件即可，无需占位脚本或模块配置。
先安装 `mooncram` 和完整 MoonBit 工具链，将安装的 `bin` 目录加入 `PATH`。
脚本使用同一安装中的 `moon` 和 `moonrun`。
脚本固定了 `moonbitlang/async` 和 `moonbitlang/x` 的版本；
首次构建需要下载依赖。

```text
demo/
└── tests/
    ├── demo.mbtx
    └── recipes.md
```

## 程序

`tests/demo.mbtx` 的完整内容：

```mbt
import {
  "moonbitlang/async@0.22.4",
  "moonbitlang/async@0.22.4/stdio",
  "moonbitlang/core/env",
  "moonbitlang/x@0.5.5/sys",
}

async fn main {
  match @env.args().get(1).unwrap_or("hello") {
    "hello" => @stdio.stdout.write("Hello, MoonBit!\n")
    "fail" => {
      @stdio.stderr.write("error: invalid argument\n")
      @sys.exit(2)
    }
    "warn" => {
      @stdio.stdout.write("progress\n")
      @stdio.stderr.write("warning: using default\n")
    }
    "version" => {
      let version = @env.get_env_var("DEMO_VERSION").unwrap_or("1.2.3")
      @stdio.stdout.write("version: \{version}\n")
    }
    "env" => {
      let name = @env.get_env_var("DEMO_NAME").unwrap_or("World")
      @stdio.stdout.write("Hello, \{name}!\n")
    }
    "copy" => @stdio.stdout.write(@stdio.stdin.read_all())
    "prompt" => @stdio.stdout.write("ready> ")
    _ => @sys.exit(3)
  }
}
```

## 测试文档

`tests/recipes.md` 的完整内容（不要复制外层 `markdown` 围栏）：

````markdown
# CLI assertion examples

## Nonzero exit code, empty stdout and an exact error

```mooncram
$ moonx ./demo.mbtx fail
@STDOUT (empty)
@STDERR
error: invalid argument
[2]
```

## Assert stderr only

```mooncram
$ moonx ./demo.mbtx warn
@STDOUT (ignore)
@STDERR
warning: using default
```

## Require stderr to be empty

```mooncram
$ moonx ./demo.mbtx hello
@STDOUT
Hello, MoonBit!
@STDERR (empty)
```

## Match the changing field with a glob or regex

```mooncram
$ DEMO_VERSION=1.2.3 moonx ./demo.mbtx version
version: * (glob)

$ DEMO_VERSION=2.4.0 moonx ./demo.mbtx version
version: [0-9]+\.[0-9]+\.[0-9]+ (regex)
```

## Read a temporary environment variable

```mooncram
$ DEMO_NAME='Moon Bit' moonx ./demo.mbtx env
Hello, Moon Bit!
```

## Pipe one script's stdout into another's stdin

```mooncram
$ moonx ./demo.mbtx hello | moonx ./demo.mbtx copy
Hello, MoonBit!
```

## Assert a prompt without a final newline

```mooncram
$ moonx ./demo.mbtx prompt
"ready> " (escaped) (no-eol)
```
````

从 `demo` 目录运行：

```sh
mooncram check tests/recipes.md
mooncram test tests/recipes.md
```

`check` 打印 `8 cases, 0 errors`，`test` 打印 `8 cases, 0 failed, 0 errors`。
两者均以 `0` 退出，包括程序有意返回 `2` 的用例。

## 按任务调整模板

- 断言 stderr 时，两个流标记缺一不可。`(ignore)` 跳过该流的内容断言；
  `(empty)` 要求零个字符，即使只有一个换行符也失败。不写标记时只断言 stdout。
  所有形式仍会检查退出码，默认值为 `0`。
- 固定输出使用精确匹配；动态字段内容无需进一步约束时使用 glob，格式也有要求时
  使用 regex。版本示例用两个固定输入演示变化；真实版本测试若需要在版本变化时
  显式更新预期，就使用精确匹配。保留稳定的 `version: ` 前缀，避免把有意义的
  整行替换成 `* (glob)`。每个模式匹配一整行，不会跳过额外输出行。
- 程序自行读取 `DEMO_NAME`。赋值只影响当前管道段及其构建，不影响后面的用例。
  命令参数中的 `$DEMO_NAME` 是字面文本，mooncram 不会展开它。
- 管道每段都写 `moonx`。只断言最后一段的 stdout，stderr 按段顺序拼接。
  退出码取最右侧非零退出码，全部成功时为 `0`。此处由提供的 `copy` 模式读取 stdin，
  没有使用 Shell 的 `cat`。
- 提示符末尾的空格也是预期的一部分。JSON 转义让空格可见，`(no-eol)` 要求末尾没有
  换行符；程序会输出末尾换行时，应去掉 `(no-eol)`。
