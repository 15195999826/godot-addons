# Sim Nav Map Feature Roadmap

本文记录 `sim-nav-map` 后续开发路线。它不是一次性任务清单，而是给未来 `/goals` 会话使用的边界文档。

## 目标定位

`sim-nav-map` 是 simulation-side RTS navigation addon。它提供导航地图、阻挡建模、可达性、长/短路径查询和请求队列。

它不是 RTS movement system，也不是 game entity model。单位如何移动、推挤、让路、编队、停止、重规划，默认属于应用层。

当前 public API 边界见 [`public-api.md`](public-api.md)，稳定 smoke 入口见
[`smoke-matrix.md`](smoke-matrix.md)。

## 目录边界

```text
addons/sim-nav-map/
  core/                  # shared flags / tiny core primitives
  model/                 # SimNavMap, passability, terrain/navcell data
  obstruction/           # obstruction shapes, spatial index, manager helpers
  pathfinding/           # reachability, long path, short path, path goals, queues
  tests/                 # addon core smoke tests
  examples/              # plugin-local applications / playable regressions
  docs/                  # mental model, roadmap, references
```

## Core Addon 内应该做什么

这些属于插件内的 reusable navigation infrastructure：

- `SimNavMap` public API 稳定化
- passability class 和 bit-mask contract
- static / dynamic obstruction shape contract
- obstruction dirty lifecycle 和 cache invalidation
- hierarchical reachability / `make_goal_reachable_navcell`
- long pathfinder / JPS / fallback A*
- vertex short pathfinder / line-of-sight helpers
- `SimNavPathGoal` 和 `SimNavWaypointPath`
- `SimNavPathfinderFacade`
- `SimNavPathRequestQueue`
- core smoke coverage 和 deterministic contract
- 文档化 public API、internal helper、adapter 使用方式

这些改动应优先落在：

```text
addons/sim-nav-map/{core,model,obstruction,pathfinding,tests,docs}/
```

## Example Lab 内应该做什么

这些属于 `examples/rts-pathfinding-lab`，因为它们是 application policy：

- 把 lab unit / obstacle 投影成 `SimNavObstructionShape*`
- playable world loop
- selection / move command
- per-tick replan budget
- unit movement integration
- overlap resolution / push policy
- same-control-group filter 的具体使用方式
- moving unit avoidance 的开关和 UX
- formation offsets / group target assignment
- narrow passage behavior
- HUD / metrics / traces
- debug drawing / editor controls
- playable regression smoke

这些改动应优先落在：

```text
addons/sim-nav-map/examples/rts-pathfinding-lab/
```

只有当某个能力被多个 example 复用，并且不依赖具体游戏语义时，才考虑提升到 core addon。

## Reference 内应该做什么

`docs/references/` 保存外部架构参考和本项目整理过的学习笔记。

当前参考对象是 0 A.D. 的 simulation/pathfinding 源码：

```text
addons/sim-nav-map/docs/references/0ad-source/
```

这个目录是本地 sparse checkout，不进 git。AI 可以在本地存在时读取它作为设计参考，但不能把 GPL 源码复制进本项目实现。

tracked 参考笔记包括：

- `0ad-architecture-overview.md`
- `0ad-data-flow.md`
- `0ad-learnings.md`
- `0ad-pathfinding.md`
- `0ad-vs-inkmon-rts.md`
- `0ad-source-setup.md`

## 推荐开发顺序

### 1. 插件收口

状态：已收口为当前 addon baseline。

目标：保持 `sim-nav-map` 是清晰、可维护的 navigation addon，而不是继续扩成 application movement system。

范围：

- 维护 public API / internal helper 边界
- 保持 README / mental model / usage examples 对齐
- 保持 adapter pattern 清晰
- 维护 `simnav/smoke` 和 `rtslab/smoke` 两个稳定回归入口
- 将旧 RTS-private pathfinder fixture 视为 archived compatibility coverage

不做：

- formation
- narrow passage yield
- crowd steering
- debug overlay
- 大规模性能 tuning

### 2. Example Lab 行为实验

目标：在应用层验证 movement policy，而不是污染 core addon。

候选：

- formation slot assignment
- narrow passage push / yield policy
- unit priority
- soft-block / hard-block 区分
- stuck detection 和 replan cadence
- path quality metrics

### 3. Debug Tooling

目标：降低未来调试成本。

候选：

- selected path overlay
- static / dynamic obstruction overlay
- reachable goal adjustment visualization
- hierarchical region / dirty chunk visualization
- path request queue diagnostics

### 4. Scale / Performance

目标：在真实地图尺寸和更多单位上验证算法边界。

候选：

- larger-map benchmarks
- higher-unit-count scenarios
- request queue worker strategy
- jump-point cache lifecycle
- dirty recompute perf contracts

## 不要混淆的边界

- `SimNavObstructionShape*` 是 navigation projection DTO，不是 game entity 基类。
- `rts-pathfinding-lab` 是 plugin-local example，不是 public API。
- `0ad-source` 是参考源码，不是 vendored dependency。
- 旧 RTS-private pathfinder fixture 是历史兼容覆盖，不是新的 `sim-nav-map` work queue。
- movement policy 默认留在 example / game layer。
- core addon 只吸收可复用的 navigation mechanism。
