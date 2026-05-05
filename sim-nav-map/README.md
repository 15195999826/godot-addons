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

## Current Coverage

Smoke tests live in `tests/` and are registered as the `simnav/smoke` group:

```powershell
./tools/run_tests.ps1 simnav/smoke
```

The current smoke group covers passability registration, terrain tiles, dirty
lifecycle, spatial index queries, path goals, map tracing, obstruction manager,
hierarchical reachability and dirty recompute, jump-point cache, long paths,
vertex paths, and request queue behavior.

## Usage Mental Model

项目层如何接入 `sim-nav-map`，见 [`docs/usage.md`](docs/usage.md) 和
[`docs/mental-model.md`](docs/mental-model.md)。
简短版本：game units / buildings 不应该继承 `SimNavObstructionShape*`；
项目层 adapter 应该把真实 entity 投影成 navigation shapes，再交给 path query。

Public API 边界见 [`docs/public-api.md`](docs/public-api.md)。当前稳定入口是
`SimNavMap`、passability / obstruction projection DTO、`SimNavPathGoal`、
`SimNavWaypointPath`、hierarchical / long / vertex pathfinder、facade 和 request
queue。`SimNavHierarchicalChunk`、`SimNavJumpPointHit`、`SimNavPathfinderHeap`
和 `SimNavRegionIdHelper` 仍是 internal helper。

## Example Lab

插件内的 playable usage sample 位于
[`examples/rts-pathfinding-lab/`](examples/rts-pathfinding-lab/)。它负责 adapter、
movement policy、selection、replan budget、push behavior、HUD 和 smoke regression；
这些都不是 core addon public API。

```powershell
./tools/run_tests.ps1 rtslab/smoke
```

## Roadmap And References

- [`docs/public-api.md`](docs/public-api.md): 当前 public API / internal helper 边界。
- [`docs/feature-roadmap.md`](docs/feature-roadmap.md): 未来开发路线和 core / example / reference 边界。
- [`docs/smoke-matrix.md`](docs/smoke-matrix.md): 稳定 smoke 入口和 legacy RTS fixture 边界。
- [`docs/references/`](docs/references/): 0 A.D. 架构笔记和本地源码参考路径。

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
