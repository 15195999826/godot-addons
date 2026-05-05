# References

本目录保存 `sim-nav-map` 开发参考材料。

## 0 A.D. Notes

这些 tracked 文档是对 0 A.D. simulation/pathfinding 架构的阅读笔记和对照分析：

- [`0ad-architecture-overview.md`](0ad-architecture-overview.md)
- [`0ad-data-flow.md`](0ad-data-flow.md)
- [`0ad-learnings.md`](0ad-learnings.md)
- [`0ad-pathfinding.md`](0ad-pathfinding.md)
- [`0ad-vs-inkmon-rts.md`](0ad-vs-inkmon-rts.md)

它们用于理解 0 A.D. 的 pathfinding / obstruction / unit motion 分层，不代表 `sim-nav-map` 要原样复刻 0 A.D.。

## Local 0 A.D. Source

本地源码参考路径：

```text
addons/sim-nav-map/docs/references/0ad-source/
```

这个目录通过 `addons/sim-nav-map/.gitignore` 忽略，不进入仓库。它是 0 A.D. 源码的 sparse checkout，主要用于 AI / 开发者在本机对照阅读。

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

## Usage Rule

可以学习 0 A.D. 的分层和数据流，但不要复制 GPL 源码实现。`sim-nav-map` 的目标是适配当前 Godot / GDScript / personal sample-driven toolchain，而不是移植 0 A.D.。
