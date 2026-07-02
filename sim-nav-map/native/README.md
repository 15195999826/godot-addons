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

## GDScript 使用纪律

一律 ClassDB 间接引用（`ClassDB.class_exists("SimNavNative...")` + `ClassDB.instantiate(...)`），
**禁止**在 .gd 里直接写 SimNavNative* 标识符 —— 没有二进制的平台必须仍能 parse 全部脚本。

## 冒烟

`./tools/run_tests.ps1 simnav/native`（要求本机已构建/已有 committed 二进制）。
