# References

本目录保留两份一手源码副本的获取和使用说明：

- **`0ad-source/`** — 0 A.D. simulation2 子树（GPL-2.0），sim-nav-map 现役 0ad-lab 的对照源
- **`dota2-style-source/`** — guinzoo/rts-path-finding（MIT），Dota2/LoL 风格 lab 的对照源（A\* + JPS + Wall-Tracing）

早期由 AI 总结的 0 A.D. 架构 / pathfinding / 对比笔记已经删除：它们产生于本地
源码副本下载之前，可能不准确或过时。解决 issue 时不要依赖这些二手总结，必须
直接阅读 `0ad-source/` 里的源码，并把当前结论写回对应 issue 或
[`0ad-source-map.md`](0ad-source-map.md)。

## Local 0 A.D. Source

本地源码参考路径：

```text
addons/sim-nav-map/docs/references/0ad-source/
```

这个目录通过 `addons/sim-nav-map/.gitignore` 忽略，不进入仓库。它是 0 A.D. 源码
的 sparse checkout，主要用于 AI / 开发者在本机对照阅读。

拉取方式见 [`0ad-source-setup.md`](0ad-source-setup.md)。

重点参考文件：

```text
source/simulation2/helpers/Pathfinding.h
source/simulation2/helpers/HierarchicalPathfinder.h
source/simulation2/helpers/HierarchicalPathfinder.cpp
source/simulation2/helpers/LongPathfinder.h
source/simulation2/helpers/LongPathfinder.cpp
source/simulation2/helpers/VertexPathfinder.cpp
source/simulation2/components/ICmpPathfinder.h
source/simulation2/components/ICmpObstructionManager.h
source/simulation2/components/CCmpObstruction.cpp
source/simulation2/components/CCmpObstructionManager.cpp
source/simulation2/components/CCmpUnitMotion.h
source/simulation2/components/CCmpUnitMotion_System.cpp
source/simulation2/components/CCmpUnitMotionManager.h
```

当前源码索引和审计笔记见 [`0ad-source-map.md`](0ad-source-map.md)，其中包含
LongPath / ShortPath 在 `CCmpUnitMotion` 中的协作关系、动态障碍分工、以及
`sim-nav-map` 侧的实现边界。

## Local Dota2-Style Pathfinding Source

本地源码参考路径：

```text
addons/sim-nav-map/docs/references/dota2-style-source/
```

通过 `addons/sim-nav-map/.gitignore` 忽略，不进入仓库。仓库小（< 1 MB），整体 clone 即可。

拉取方式 + 关键文件索引见 [`dota2-style-source-setup.md`](dota2-style-source-setup.md)。

重点参考文件：

```text
src/PathFinder.cpp     # long+short 双层 facade（Dota2 调度核心）
src/WallTracing.cpp    # 短路径连续空间 wall-tracing（公开 Dota2 风格仅有的开源实现）
src/JPS.cpp            # 长路径 JPS（参考 contract 即可，sim-nav-map 已有自己的实现）
```

## Usage Rule

- **`0ad-source/`（GPL-2.0）**：可以学习分层、contract 和数据流，**不要复制源码实现**
- **`dota2-style-source/`（MIT）**：可以参考实现细节，但 sim-nav-map 自身风格优先（重写而非复制粘贴），保留上游 copyright 归属

`sim-nav-map` 的目标是适配当前 Godot / GDScript / sample-driven toolchain，不是移植任何上游。
