# sim-nav-map native backend (GDExtension)

C++ 可切换后端：寻路核心 + 分离求解热路径。GDScript 实现是永久默认与参照真值机；
本扩展面向高性能需求的项目，行为与 GDScript 逐位对拍（方案与验收见
[`../docs/gdextension-port-plan.md`](../docs/gdextension-port-plan.md)）。

## 布局

```text
native/
  src/            C++ 源码
  SConstruct      构建入口（产物落 ../bin/）
  setup.ps1       一次性机器准备：pin 克隆 godot-cpp + dump extension_api.json
  godot-cpp/      (gitignored) setup.ps1 克隆，pin 见 setup.ps1
../bin/           构建产物（committed —— 消费项目免工具链）
../simnav_native.gdextension
```

## 构建

前置：VS2022 C++ 工具链、Python + SCons（`pip install scons`）、PATH 上有 Godot 4.7。
Web 线另需 Emscripten **4.0.20**（= 官方 4.7 web 模板实际编译版本，以导出页 boot banner
"Build configuration" 为准；emsdk pin 安装。换版本后必须先 `scons ... --clean` 再重编，
emsdk 原地切版本不会改变命令行签名，SCons 会误判目标物是新的）。

```powershell
./setup.ps1     # 一次性
scons platform=windows target=template_debug custom_api_file=extension_api.json
scons platform=windows target=template_release custom_api_file=extension_api.json
# Web（先激活 emsdk 环境）
scons platform=web target=template_release threads=no custom_api_file=extension_api.json
```

## 构建纪律（血泪：混装产物会让扩展在 `StringName::init_bindings` 段错误）

**工具链环境变过（emsdk 切版本 / 重跑 setup.ps1 re-dump API / 在 godot-cpp 目录内单独跑过 scons）
之后，必须全清重编**，否则新旧目标物混链，产物在扩展 init 最早期段错误（比类注册还早，
崩栈在 `StringName::init_bindings`）：

```powershell
git -C godot-cpp clean -fdxq       # 清生成绑定 + 全部目标物 + sconsign
Remove-Item .sconsign.dblite, src\*.obj, src\core\*.obj, src\*.o, src\core\*.o -ErrorAction SilentlyContinue
# 三个发布 target（windows debug/release + web release）全部重编，别只编当前在用的那个
scons platform=windows target=template_debug custom_api_file=extension_api.json
scons platform=windows target=template_release custom_api_file=extension_api.json
scons platform=web target=template_release threads=no custom_api_file=extension_api.json
```

根因形态：native/ 与 godot-cpp/ 各有一份 .sconsign 数据库写同一批对象路径，
签名系统跨库互不知情；extension_api.json 被 re-dump 刷新 mtime 也会触发部分重生成。
症状 = "M1 的 dll 能跑、之后编的全崩"。

## GDScript 使用纪律

一律 ClassDB 间接引用（`ClassDB.class_exists("SimNavNative...")` + `ClassDB.instantiate(...)`），
**禁止**在 .gd 里直接写 SimNavNative* 标识符 —— 没有二进制的平台必须仍能 parse 全部脚本。

## 冒烟

`./tools/run_tests.ps1 simnav/native`（要求本机已构建/已有 committed 二进制）。
