# Dota2 风格寻路参考实现 — 拉取与使用

> **不进仓**(被 `addons/sim-nav-map/.gitignore` 屏蔽)。
> 每个开发者本地自己拉一份，仅供 Dota2/LoL 风格 lab 开发期间对照参考用。

## 是什么

[`guinzoo/rts-path-finding`](https://github.com/guinzoo/rts-path-finding)
— C++ 实现的 RTS 寻路算法库。作者明确声明 **"That scheme was gotten from game Dota 2"**：

- **Long path（rough）**：A\* / JPS / JPS+ 三种网格寻路实现（任选其一）
- **Short path（precise）**：连续空间 **Wall-Tracing**，作者自述是因为公开渠道找不到 Dota2 wall-tracing 细节才自己 invent 出来的，**目前是公开 Dota2 风格 wall-tracing 仅有的开源实现**

License = **MIT**，77 stars，最后更新 2018-02。规模 ~85 KB，可整个啃。

## 位置

`addons/sim-nav-map/docs/references/dota2-style-source/`

## 拉取方法

```bash
git clone --depth=1 \
  https://github.com/guinzoo/rts-path-finding.git \
  addons/sim-nav-map/docs/references/dota2-style-source
```

仓库小（< 1 MB），不需要 sparse checkout。

## 关键文件索引

| 用途 | 文件 |
|---|---|
| 顶层 facade（双层调度：先 rough 再 precise） | `src/PathFinder.{hpp,cpp}` |
| Long path - A\* baseline | `src/AStar.{hpp,cpp}` |
| Long path - JPS（Harabor & Grastien 2012 改进版，no edge cutting） | `src/JPS.{hpp,cpp}` |
| Long path - JPS+（cache jump-point 距离，最快 ~0.5 ms / 256² grid） | `src/JPSplus.{hpp,cpp}` |
| **Short path - Wall-Tracing**（**本仓库价值核心**） | `src/WallTracing.{hpp,cpp}` |
| 几何基础（射线 / 圆 / 矩形 / 段相交） | `src/geometry.hpp` |
| 网格坐标类型 | `src/Coord.hpp` |

**Lab 开发的对照阅读路线**：

1. **先读 `PathFinder.cpp`** — 看 long+short 双层怎么 wire 起来（这是 Dota2 风格的精髓：long path 给航点，short path 在航点之间走，距离短到一定程度才换下一段）
2. **再读 `WallTracing.cpp`** — 短路径主算法，作者强调"无三角函数 / 短距离 < 0.2 ms / 路径不保证最短但视觉上 OK"
3. **JPS 三件套按需** — sim-nav-map 已有 `SimNavLongPathfinder`，jump point cache 也有，主要看 contract / data shape 而不是抄实现

## 来源说明 & License

- **上游**：https://github.com/guinzoo/rts-path-finding（默认分支 `master`）
- **License**：MIT（见 `dota2-style-source/LICENSE`）— 比 0 A.D. 的 GPL-2.0 宽松，**可以参考实现细节**，但 sim-nav-map 自身风格优先（重写而非复制粘贴），保留 `Copyright (c) 2018 Guinzoo` 归属

## 升级 / 重新拉取

```bash
cd addons/sim-nav-map/docs/references/dota2-style-source
git pull --depth=1
```

（仓库 2018 后基本没动，一般不需要更新）

## 删除（不再需要时）

```bash
rm -rf addons/sim-nav-map/docs/references/dota2-style-source
```
