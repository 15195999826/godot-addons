# Sim Nav Map

`sim-nav-map` is an independent Godot addon for simulation-side navigation maps
and RTS-style pathfinding. It is shaped by 0 A.D.-style concepts, but it is not a
full 0 A.D. clone and does not depend on `ultra-grid-map`.

## Current Architecture

The addon is split into four layers:

- `core/`: shared navigation flags, currently `SimNavObstructionFlags`.
- `model/`: map data and passability state.
- `obstruction/`: static and unit obstruction shapes plus spatial indexing.
- `pathfinding/`: reachability, long paths, short paths, path goals, and request
  queue helpers.

`SimNavMap` is the central data structure. It owns navcell dimensions, terrain
tile data, registered passability classes, static obstructions, dynamic unit
obstructions, spatial indexes, and dirty navcell tracking. Static obstructions
are rasterized into obstruction navcell data; dynamic unit obstructions are kept
as queryable shapes so callers can decide how often to rebuild or replace them.

Passability is configured through `SimNavPassabilityClassConfig` and
`SimNavPassabilityClassRegistry`. Each class receives a bit mask and can carry
clearance, terrain mask, and pathfinding participation rules.

Obstructions are represented by `SimNavObstructionShapeStatic` and
`SimNavObstructionShapeUnit`. Static shapes are oriented rectangles with
pathfinding/blocking flags. Unit shapes are circular dynamic blockers with
clearance and control-group metadata. `SimNavSpatialIndex` keeps obstruction
queries bounded to nearby objects.

Pathfinding currently has three main pieces:

- `SimNavHierarchicalPathfinder`: chunk-level reachability, dirty recompute, and
  reachable-goal canonicalization.
- `SimNavLongPathfinder`: navcell long-path search using Jump Point Search with
  A* fallback and per-passability jump caches.
- `SimNavVertexPathfinder`: local visibility-graph search for short paths around
  static shapes, unit shapes, and blocked navcells.

`SimNavPathfinderFacade` is the simple synchronous entry point for long paths.
`SimNavPathRequestQueue` provides frame-budgeted or worker-thread batch
processing for callers that do not want to compute every request in one frame.

## Current Capabilities

The completed core surface includes:

- terrain-derived navcell passability with per-class terrain masks
- class-aware clearance rasterization for terrain and static obstructions
- dirty recompute and cache invalidation for terrain/static edits
- hierarchical reachability and nearest reachable goal canonicalization
- long-path query/result DTOs with status, metadata, raw/refined path boundary,
  excluded-region isolation, path cost, and waypoint spacing
- filtered short-path queries plus movement-line and unit-line validation
- budgeted / worker-style long and short path request queue
- map, obstruction, queue, dirtiness, and connectivity diagnostics

These are navigation primitives. Unit motion, steering, formation, push/yield,
arrival packing, stuck recovery, combat, resource gathering, and UI behavior
remain project or lab policy.

## Current Coverage

Smoke tests live in `tests/` and are registered as the `simnav/smoke` group:

```powershell
./tools/run_tests.ps1 simnav/smoke
```

The current smoke group covers public API constructor/default contracts,
passability registration, terrain tiles, dirty lifecycle, spatial index queries,
path goals, map tracing, obstruction manager, hierarchical reachability and
dirty recompute, reachability metadata, jump-point cache, long paths, vertex
paths, line validation, request queue behavior, queued request cloning, and
diagnostics exports.

## Usage Mental Model

项目层如何接入 `sim-nav-map`，见 [`docs/usage.md`](docs/usage.md) 和
[`docs/mental-model.md`](docs/mental-model.md)。
简短版本：game units / buildings 不应该继承 `SimNavObstructionShape*`；
项目层 adapter 应该把真实 entity 投影成 navigation shapes，再交给 path query。

Public API 边界见 [`docs/public-api.md`](docs/public-api.md)。当前稳定入口是
`SimNavMap`、passability / obstruction projection DTO、`SimNavPathGoal`、
`SimNavWaypointPath`、hierarchical / long / vertex pathfinder、facade 和 request
queue。`SimNavObstructionShape` 是 map query 返回的 base DTO 类型；
adapter input 仍应使用 `SimNavObstructionShapeStatic` 或
`SimNavObstructionShapeUnit`。`SimNavHierarchicalChunk`、`SimNavJumpPointHit`、
`SimNavPathfinderHeap` 和 `SimNavRegionIdHelper` 仍是 internal helper。

## Example Lab

插件内的 playable usage sample 位于
[`examples/0ad-rts-pathfinding-lab/`](examples/0ad-rts-pathfinding-lab/)。它负责
adapter、movement policy、selection、replan budget、push behavior、HUD 和 smoke
regression；这些都不是 core addon public API。

```powershell
./tools/run_tests.ps1 zeroadlab/smoke
```

## Docs And References

- [`docs/public-api.md`](docs/public-api.md): 当前 public API / internal helper 边界。
- [`docs/issues/`](docs/issues/): 当前 bug、gap 和后续优化的 issue tracker。
- [`docs/smoke-matrix.md`](docs/smoke-matrix.md): 稳定 smoke 入口和 legacy RTS fixture 边界。
- [`docs/references/`](docs/references/): 0 A.D. 本地源码副本路径和刷新说明；issue
  需要 reference 时读源码，不读旧二手总结。

## Boundaries

The addon owns map/pathfinding primitives only. It does not currently own unit
movement, steering, collision response, formation layout, combat behavior, or
game-specific rules such as whether a unit may push another unit through a
narrow passage. Those policies belong to the game/lab layer that consumes this
addon.

The current implementation is optimized for correctness and playable RTS lab
behavior at small sample scale. It is ready to serve as the shared pathfinding
source for examples, but not yet a polished large-scale production navigation
stack.

## Future Directions

新工作默认先落到 [`docs/issues/`](docs/issues/)：一个问题一个 issue，一个
focused repro / lock-in smoke，修复后再把通过的场景加入稳定 manifest。

- Keep the documented public API around `SimNavMap`, `SimNavPathGoal`,
  `SimNavPathfinderFacade`, and `SimNavPathRequestQueue` stable.
- Formalize cache invalidation for static map edits, dynamic obstruction edits,
  hierarchical regions, and jump-point caches.
- Add larger-map and higher-unit-count performance scenarios before tuning data
  structures further.
- Improve path post-processing and smoothing contracts so callers get predictable
  waypoint quality.
- Add debug rendering helpers for navcells, dirty cells, regions, obstruction
  shapes, and selected paths.
- Keep old RTS private pathfinder fixtures as archived compatibility coverage;
  new navigation work should target `sim-nav-map` or an adapter.
- Keep crowd steering, formation ranking, unit priority, and push policy outside
  the core addon unless a future game requirement proves a reusable boundary.
