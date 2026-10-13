# lomo-addons（godot-addons）

lomo 的 Godot 插件集：`lomolib` / `logic-game-framework` / `sim-nav-map` / `ultra-grid-map`。后三个都依赖 `lomolib`，所以放在一个仓库里一起管。

## 挂载位置（路径写死）

以 git submodule 挂到项目的 **`addons/lomo-addons/`**：

```
git submodule add --name lomo-addons https://github.com/15195999826/godot-addons.git <godot 项目>/addons/lomo-addons
```

- 插件内部互相引用写的是 `res://addons/lomo-addons/<插件>/...`，挂到别的路径会断。
- 只占 `addons/` 下这一个文件夹：项目自己的 / 第三方插件照常放在 `addons/<名字>/`，随项目仓库提交。
- 嵌套一层不影响插件：Godot 4.7 实测 `res://addons/lomo-addons/<插件>/plugin.cfg` 启用、`class_name` 注册、GDExtension 加载都正常。

2026-10-13 之前本仓库占满整个 `addons/`（路径是 `res://addons/<插件>/...`）；还停在旧提交的项目升级时要一并把子模块挪到 `addons/lomo-addons/`，并把项目里的 `addons/<插件>/` 路径前缀改成 `addons/lomo-addons/<插件>/`。
