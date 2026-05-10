# References

本目录只保留 0 A.D. 一手源码副本的获取和使用说明。

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

## Usage Rule

可以学习 0 A.D. 的分层、contract 和数据流，但不要复制 GPL 源码实现。
`sim-nav-map` 的目标是适配当前 Godot / GDScript / sample-driven toolchain，
不是移植 0 A.D.。
