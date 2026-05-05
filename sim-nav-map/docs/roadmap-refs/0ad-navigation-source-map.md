# 0 A.D. Navigation Source Map

This file supports [`../feature-roadmap.md`](../feature-roadmap.md). It records
which 0 A.D. source files informed the roadmap and which review gaps should be
absorbed into future `sim-nav-map` work.

The local 0 A.D. source checkout is a reference-only directory:

```text
addons/sim-nav-map/docs/references/0ad-source/
```

Do not commit `docs/references/0ad-source/` and do not copy GPL source
implementation into this addon. Use these files to understand API boundaries,
data flow, and tests to recreate in GDScript.

## Source Index

| Roadmap area | Main source files | Reference points |
|---|---|---|
| Terrain / passability | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/CCmpPathfinder.cpp` | `NAVCELLS_PER_TERRAIN_TILE`, `PASS_CLASS_BITS`, terrain -> navcell grid, `UpdateGrid()`. |
| Clearance rasterization | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/ICmpObstructionManager.h` | `CLEARANCE_EXTENSION_RADIUS`, `PathfinderPassability`, `Rasterize()` writing per-pass-class clearance into grid. |
| Obstruction database | `source/simulation2/components/ICmpObstructionManager.h` | static OBB, unit circle, flags, control groups, shape query filters. |
| Obstruction filters | `source/simulation2/components/ICmpObstructionManager.h` | `IObstructionTestFilter`, tag / flags / control group / moving-state filters. |
| Movement-line validation | `source/simulation2/helpers/Pathfinding.cpp`, `source/simulation2/components/ICmpPathfinder.h`, `source/simulation2/components/ICmpObstructionManager.h` | `CheckLineMovement()`, `CheckMovement()`, grid + shape legality checks for a movement segment. |
| Dirty / cache lifecycle | `source/simulation2/components/CCmpPathfinder.cpp`, `source/simulation2/helpers/HierarchicalPathfinder.h`, `source/simulation2/helpers/LongPathfinder.h` | obstruction / terrain change -> `UpdateGrid()`, hierarchical update, jump cache clear. |
| Reachability | `source/simulation2/helpers/HierarchicalPathfinder.h`, `source/simulation2/helpers/HierarchicalPathfinder.cpp` | chunk / region / global region, `IsGoalReachable()`, `MakeGoalReachable()`. |
| Long path | `source/simulation2/helpers/LongPathfinder.h`, `source/simulation2/helpers/LongPathfinder.cpp` | A* / JPS, `WaypointPath`, `ImprovePathWaypoints()`, excluded regions, debug data. |
| Short path | `source/simulation2/helpers/VertexPathfinder.h`, `source/simulation2/helpers/VertexPathfinder.cpp`, `source/simulation2/components/ICmpObstructionManager.h` | visibility graph, range-limited short path, `avoidMovingUnits`, group filter. |
| Request queue | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/CCmpPathfinder.cpp`, `source/simulation2/components/CCmpUnitMotion.h` | `LongPathRequest` / `ShortPathRequest`, async ticket, `m_MaxSameTurnMoves`, expected ticket. |
| Diagnostics exports | `source/simulation2/components/ICmpPathfinder.h`, `source/simulation2/helpers/HierarchicalPathfinder.h` | AI dirtiness information, connectivity grid read-only export. |
| Formation as example policy | `source/simulation2/components/CCmpUnitMotion.h`, `source/simulation2/components/CCmpUnitMotion_System.cpp` | formation controller runs before unit motion; useful validation idea, not a core plugin target. |

## Accepted Gap Review Items

These gaps should be represented in the roadmap because they are navigation-core
mechanisms, not RTS gameplay.

| Gap | Roadmap target | Why it belongs in core |
|---|---|---|
| Movement-line validation | Feature 6 | Pure query: whether a swept movement segment crosses impassable navcells or filtered obstruction shapes. It does not decide what movement does after failure. |
| Obstruction query filter abstraction | Feature 6 | Pure query policy over navigation shapes: include/exclude by tag, flags, control group, moving state. Adapter supplies intent; core owns the filter protocol. |
| Path goal max waypoint distance / max spacing | Feature 5 | Path output contract, separate from how a unit consumes the path. |
| Long-path excluded regions | Feature 5 | Per-query pathfinding input. Adapter decides why to exclude a region; pathfinder only respects the input. |
| Per-tag obstruction updates | Feature 3 | Shape lifecycle primitive: moving flag, active flag, group, rotation, and flags can change without rebuilding all dynamic shapes. |
| Connectivity / dirtiness exports | Feature 8 | Read-only navigation state export for diagnostics, AI, or future tools. |

## Deferred Items

These are valid navigation-adjacent primitives, but they should not become
roadmap commitments until a second example or lab scenario proves the need.

| Item | Source evidence | Current decision |
|---|---|---|
| Placement check primitive | `ICmpPathfinder::CheckUnitPlacement()`, `CheckBuildingPlacement()`; `ICmpObstruction::EFoundationCheck` | Defer. The collision query is reusable, but placement status codes easily pull in build gameplay. Promote only after repeated adapter duplication. |
| Cluster obstruction shape | `ICmpObstruction::EObstructionType::CLUSTER` | Defer. Adapter can currently split multi-part objects into several static shapes. Promote if walls / L-shaped blockers need one shared tag identity. |
| Circular world / out-of-bounds contract | `ICmpObstructionManager::SetBounds()`, `SetPassabilityCircular()` | Document rectangular out-of-bounds behavior in Feature 1; leave circular maps out of the route until needed. |
| OBB distance / shape range helpers | `DistanceBetweenShapes()`, `MaxDistanceBetweenShapes()`, `AreShapesInRange()` | Defer. Geometry is reusable, but many use cases are combat/range policy. Add only with a navigation-only caller. |

## Explicit Non-Gaps

These look related in 0 A.D. but should remain lab/game policy for `sim-nav-map`:

- `MoveRequest` types, `minRange` / `maxRange`, and entity-target movement.
- `m_FailedMovements`, stuck recovery, retry cadence, and imperfect-path cooldown.
- UnitMotion push pass, yield rules, unit priority, and deadlock resolution.
- Formation controller and formation slot assignment.
- UnitAI, stance, combat, resources, build rules, command queue, selection, HUD.
- Footprint / selection geometry and render-position vs obstruction-center policy.
- fixed-point determinism. `sim-nav-map` may stay in GDScript float unless a future
  replay requirement proves otherwise.
