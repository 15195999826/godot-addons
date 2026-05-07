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

## Freshness Rule

Treat this file and [`../feature-roadmap.md`](../feature-roadmap.md) as source
indexes, not as permanent truth. Before implementing a roadmap feature, reopen
the referenced 0 A.D. files and refresh the relevant audit notes here if the
local source says something different from the current docs.

The implementation target remains `sim-nav-map`'s own GDScript contract. Source
audit notes should explain which ideas are being recreated, which are being
intentionally improved, and which 0 A.D. gameplay policies are staying out of
the core addon.

## Source Index

| Roadmap area | Main source files | Reference points |
|---|---|---|
| Terrain / passability | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/CCmpPathfinder.cpp` | `NAVCELLS_PER_TERRAIN_TILE`, `PASS_CLASS_BITS`, terrain -> navcell grid, `UpdateGrid()`. |
| Clearance rasterization | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/ICmpObstructionManager.h` | `CLEARANCE_EXTENSION_RADIUS`, `PathfinderPassability`, `Rasterize()` writing per-pass-class clearance into grid. |
| Obstruction database | `source/simulation2/components/ICmpObstructionManager.h` | static OBB, unit circle, flags, control groups, shape query filters. |
| Obstruction filters | `source/simulation2/components/ICmpObstructionManager.h` | `IObstructionTestFilter`, tag / flags / control group / moving-state filters. |
| Movement-line validation | `source/simulation2/helpers/Pathfinding.cpp`, `source/simulation2/components/ICmpPathfinder.h`, `source/simulation2/components/ICmpObstructionManager.h` | `CheckLineMovement()`, `CheckMovement()`, grid + shape legality checks for a movement segment. |
| Unit-line validation | `source/simulation2/components/ICmpObstructionManager.h`, `source/simulation2/components/CCmpObstructionManager.cpp`, `source/simulation2/components/CCmpUnitMotion.h` | Gitea `main` adds `TestUnitLine()`; UnitMotion checks upcoming long-path segment against dynamic unit obstructions and requests short path when needed. |
| Dirty / cache lifecycle | `source/simulation2/components/CCmpPathfinder.cpp`, `source/simulation2/helpers/HierarchicalPathfinder.h`, `source/simulation2/helpers/LongPathfinder.h` | obstruction / terrain change -> `UpdateGrid()`, hierarchical update, jump cache clear. |
| Reachability | `source/simulation2/helpers/HierarchicalPathfinder.h`, `source/simulation2/helpers/HierarchicalPathfinder.cpp` | chunk / region / global region, `IsGoalReachable()`, `MakeGoalReachable()`. |
| Long path | `source/simulation2/helpers/LongPathfinder.h`, `source/simulation2/helpers/LongPathfinder.cpp` | A* / JPS, `WaypointPath`, `ImprovePathWaypoints()`, excluded regions, debug data. |
| Short path | `source/simulation2/helpers/VertexPathfinder.h`, `source/simulation2/helpers/VertexPathfinder.cpp`, `source/simulation2/components/ICmpObstructionManager.h` | visibility graph, range-limited short path, `avoidMovingUnits`, group filter. |
| Request queue | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/CCmpPathfinder.cpp`, `source/simulation2/components/CCmpUnitMotion.h` | `LongPathRequest` / `ShortPathRequest`, async ticket, `m_MaxSameTurnMoves`, expected ticket. |
| Diagnostics exports | `source/simulation2/components/ICmpPathfinder.h`, `source/simulation2/helpers/HierarchicalPathfinder.h` | AI dirtiness information, connectivity grid read-only export. |
| Formation as example policy | `source/simulation2/components/CCmpUnitMotion.h`, `source/simulation2/components/CCmpUnitMotion_System.cpp` | formation controller runs before unit motion; useful validation idea, not a core plugin target. |

## Feature 5 Long-Path Source Audit

This section refreshes the Feature 5 target against the local 0 A.D. source.
Use it before changing `sim-nav-map` long-path API or result DTOs. If the source
is refreshed, re-check these files before relying on the bullets below:

```text
source/simulation2/helpers/LongPathfinder.h
source/simulation2/helpers/LongPathfinder.cpp
source/simulation2/helpers/Pathfinding.h
source/simulation2/helpers/PathGoal.h
source/simulation2/components/ICmpPathfinder.h
source/simulation2/components/CCmpPathfinder.cpp
source/simulation2/components/CCmpUnitMotion.h
```

### 0 A.D. Source Facts

- `PathGoal` is the shared goal shape for long and short pathfinding. It covers
  point, circle, inverted circle, square, and inverted square goals, and carries
  `maxdist` as the maximum desired distance between path waypoints.
- `LongPathRequest` is small: ticket, start coordinates, `PathGoal`,
  passability class, and notify entity. The public path result is also small:
  ticket, notify entity, and `WaypointPath`.
- `WaypointPath` stores waypoints in reverse consumption order: the earliest
  waypoint is at the back of the vector. `CCmpUnitMotion` consumes and pops from
  that end.
- 0 A.D.'s public long-path API does not expose explicit status, cost, raw path,
  canonicalization metadata, or failure reason. Consumers infer failure or poor
  quality mostly from an empty path or from post-result checks.
- Long path computation first canonicalizes the goal through hierarchical
  reachability. `LongPathfinder` asks `HierarchicalPathfinder` to make the goal
  reachable, then expects the working goal to become a point goal.
- If the start navcell is not passable, long pathfinding asks the hierarchical
  layer for the nearest passable navcell before running JPS. This is a safety
  behavior around invalid starts, not a public result status.
- If the start already lies in the final goal navcell, long path returns a single
  waypoint at the exact goal coordinates.
- Reconstructed JPS waypoints are refined after search. The final goal waypoint
  is rewritten to the exact reachable goal coordinate, then
  `ImprovePathWaypoints()` applies line-of-sight cleanup and optional
  `maxdist` spacing.
- `ImprovePathWaypoints()` only removes an intermediate waypoint when the line
  between the surrounding waypoints is valid against the passability grid. This
  is the source-side reason Feature 5 post-processing must not create
  obstacle-crossing segments.
- The excluded-region overload is a per-query long-path input. It builds a
  special passability map where excluded circular regions are treated as blocked
  for that computation. This should not be modeled as a persistent map edit in
  `sim-nav-map`.
- Async long and short path requests share a ticket/result dispatch mechanism.
  `CCmpPathfinder` computes queued requests and posts only the ticket and
  `WaypointPath` back to the notified entity.
- `CCmpUnitMotion` layers gameplay and movement-policy hacks on top of the
  sparse path result: rejecting paths that move farther from the goal, falling
  back to a short-path attempt after an empty long path, and later deciding when
  to request short paths while following a long path.

### Sim Nav Map Feature 5 Implications

- Adding explicit result statuses is an intentional `sim-nav-map` improvement,
  not a direct 0 A.D. API copy. The useful status split should cover at least
  success, canonicalized success, invalid start recovery, unreachable/no path,
  and empty/direct-goal edge cases when the implementation can distinguish them.
- Canonicalized goal metadata belongs in the result contract because 0 A.D. does
  canonicalization internally but does not surface it. `sim-nav-map` should make
  that boundary visible so adapters do not guess from the returned waypoints.
- Raw vs refined output should be explicit. 0 A.D. reconstructs a JPS/navcell
  waypoint chain and then mutates it through refinement; `sim-nav-map` should
  preserve enough metadata for smoke tests to prove refinement reduced or spaced
  waypoints without changing reachability.
- If `sim-nav-map` returns waypoints in forward order, document that as an
  intentional difference from 0 A.D.'s reverse `WaypointPath` consumption order.
- Path cost, path length, waypoint count, canonical goal, and refinement mode
  are diagnostic/result metadata for consumers. They should stay navigation
  facts, not movement policy.
- Excluded regions should be request-scoped. A smoke test should prove that one
  query can avoid an excluded circle without dirtying or permanently changing
  subsequent path queries.
- `maxdist` / max waypoint spacing is a path output contract. It should be
  represented as request preference or goal option, and verified as a waypoint
  spacing guarantee that does not bypass line-of-sight legality.
- Do not port `CCmpUnitMotion` policy into Feature 5. The short-path fallback,
  imperfect-path countdown, target-motion retry cadence, and dynamic-unit
  line-check replanning remain Feature 6+ or lab-side movement behavior.

### Feature 5 Documentation Updates Needed

- Update `public-api.md` when the new result DTO names, status values, waypoint
  order, and metadata fields are chosen.
- Update `feature-roadmap.md` if implementation findings change the Feature 5
  scope or expose a stale assumption from this audit.
- Update `smoke-matrix.md` with core and lab smoke scenes for status,
  canonicalization metadata, raw/refined waypoint boundaries, max spacing, and
  excluded-region query isolation.

### Sim Nav Map Feature 5 Implementation Outcome

- The chosen DTOs are `SimNavLongPathQuery` and `SimNavLongPathResult`.
  `SimNavLongPathfinder.compute_path_result()` and
  `SimNavPathfinderFacade.compute_path_result()` return metadata-rich results;
  `compute_path_immediate()` remains the path-only compatibility API.
- Status values are explicit: `success`, `canonicalized`, `start_recovered`,
  `direct_goal`, `unreachable`, `no_path`, `invalid_start`, and
  `invalid_query`.
- `raw_navcell_path` is diagnostic and stored start-to-goal. `SimNavWaypointPath`
  remains reverse-consumption order to preserve the existing API and 0 A.D.-like
  waypoint consumption semantics.
- `excluded_regions` are copied from the query and checked only during that
  long-path computation. They do not mark map cells dirty and do not persist
  into later queries.
- `post_process` supports `raw`, `line_of_sight`, and `max_spacing`. Spacing is
  a navigation output preference (`waypoint_spacing` or `PathGoal.maxdist`),
  not movement policy.
- `rts-pathfinding-lab` consumes result metadata through adapter reports only.
  Feature 5 did not move `CCmpUnitMotion`-style short-path fallback, retry
  cadence, push/yield, stuck/deadlock, formation, or movement controller policy
  into core.

## Accepted Gap Review Items

These gaps should be represented in the roadmap because they are navigation-core
mechanisms, not RTS gameplay.

| Gap | Roadmap target | Why it belongs in core |
|---|---|---|
| Movement-line validation | Feature 6 | Pure query: whether a swept movement segment crosses impassable navcells or filtered obstruction shapes. It does not decide what movement does after failure. |
| Unit-only line validation | Feature 6 | Pure query: whether a swept segment would hit dynamic unit obstructions under a filter. It lets adapters decide when to replan locally without making that replan cadence a core policy. |
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
- UnitMotion's decision to request short path while following a long path. Core may expose
  the unit-line query, but the replan cadence and target selection remain consumer policy.
- UnitMotion push pass, yield rules, unit priority, and deadlock resolution.
- Formation controller and formation slot assignment.
- `ICmpPathfinder::DistributeAround()` style unit distribution. It can inform lab formation
  validation, but slot/rank/final layout policy should not become a core navigation API yet.
- UnitAI, stance, combat, resources, build rules, command queue, selection, HUD.
- Footprint / selection geometry and render-position vs obstruction-center policy.
- fixed-point determinism. `sim-nav-map` may stay in GDScript float unless a future
  replay requirement proves otherwise.
