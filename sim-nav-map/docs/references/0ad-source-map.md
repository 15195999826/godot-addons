# 0 A.D. Source Map

This file records which 0 A.D. source files are relevant to `sim-nav-map`
navigation work and which review gaps should be absorbed into issue-based
development.

The local 0 A.D. source checkout is a reference-only directory:

```text
addons/sim-nav-map/docs/references/0ad-source/
```

Do not commit `docs/references/0ad-source/` and do not copy GPL source
implementation into this addon. Use these files to understand API boundaries,
data flow, and tests to recreate in GDScript.

## Freshness Rule

Treat this file as a source index, not as permanent truth. Before implementing
an issue fix that depends on 0 A.D. behavior, reopen the referenced files and
refresh the relevant audit notes here if the local source says something
different from the current docs.

The implementation target remains `sim-nav-map`'s own GDScript contract. Source
audit notes should explain which ideas are being recreated, which are being
intentionally improved, and which 0 A.D. gameplay policies are staying out of
the core addon.

## Source Index

| Area | Main source files | Reference points |
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
| Short path | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/helpers/VertexPathfinder.h`, `source/simulation2/helpers/VertexPathfinder.cpp`, `source/simulation2/components/ICmpObstructionManager.h`, `source/simulation2/components/CCmpUnitMotion.h` | `ShortPathRequest`, visibility graph, range-limited short path, `avoidMovingUnits`, group filter, long-waypoint rejoin policy caller. |
| Request queue | `source/simulation2/helpers/Pathfinding.h`, `source/simulation2/components/CCmpPathfinder.cpp`, `source/simulation2/components/CCmpPathfinder_Common.h`, `source/simulation2/components/CCmpUnitMotion.h` | `LongPathRequest` / `ShortPathRequest`, async ticket, `PathRequests`, `m_MaxSameTurnMoves`, expected ticket. |
| Diagnostics exports | `source/simulation2/helpers/Grid.h`, `source/simulation2/components/ICmpPathfinder.h`, `source/simulation2/components/CCmpPathfinder.cpp`, `source/simulation2/components/CCmpPathfinder_Common.h`, `source/simulation2/helpers/HierarchicalPathfinder.h` | `GridUpdateInformation`, AI dirtiness information, passability grid, debug data, connectivity grid read-only export. |
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

### Documentation Updates Needed

- Update `public-api.md` when the new result DTO names, status values, waypoint
  order, and metadata fields are chosen.
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

## Feature 6 Filtered Short Query And Line Validation Source Audit

This section refreshes the Feature 6 target against the local 0 A.D. source.
Use it before changing `sim-nav-map` short-path requests, obstruction filters,
or line-validation APIs. If the source is refreshed, re-check these files before
relying on the bullets below:

```text
source/simulation2/helpers/Pathfinding.h
source/simulation2/helpers/Pathfinding.cpp
source/simulation2/helpers/VertexPathfinder.h
source/simulation2/helpers/VertexPathfinder.cpp
source/simulation2/components/ICmpPathfinder.h
source/simulation2/components/ICmpObstructionManager.h
source/simulation2/components/CCmpObstructionManager.cpp
source/simulation2/components/CCmpUnitMotion.h
```

### 0 A.D. Source Facts

- `ShortPathRequest` carries ticket, start coordinates, clearance, search
  range, `PathGoal`, passability class, `avoidMovingUnits`, control group, and
  notify entity. It is still a navigation request, not a movement controller.
- `VertexPathfinder::ComputeShortPath()` builds a local visibility graph inside
  a range-limited search region. The range boundary itself becomes an
  impassable edge so short-path work stays local.
- The short pathfinder asks the obstruction manager for static and unit
  obstruction squares in range, using `ControlGroupMovementObstructionFilter`
  built from `avoidMovingUnits` and the request control group.
- `WaypointPath` is reconstructed in reverse consumption order for short paths,
  consistent with the long-path result shape.
- `ICmpObstructionManager` exposes exact collision primitives with an
  `IObstructionTestFilter`: `TestLine()`, `TestUnitLine()`, static/unit shape
  tests, and static/unit/all obstruction range queries.
- The concrete filter family covers useful navigation cases: include all,
  stationary-only, skip a tag, skip control groups, require flags, and combine
  tag/group/flag predicates.
- `Pathfinding::CheckLineMovement()` validates a line segment against the
  passability grid. `ICmpPathfinder::CheckMovement()` combines obstruction-line
  collision with terrain/passability line validation and returns a boolean
  legality answer.
- `CCmpObstructionManager::TestLine()` checks both static and unit obstructions;
  `TestUnitLine()` checks only unit obstructions. Both accept the same filter
  protocol and swept radius input.
- `CCmpUnitMotion` uses `CheckMovement()` before advancing along a segment and
  uses `TestUnitLine()` while following a long path to detect upcoming dynamic
  unit blockage. Its decision to request a short path after a blocked segment is
  caller policy, not part of the primitive.

### Sim Nav Map Feature 6 Implications

- A `sim-nav-map` obstruction filter contract should be explicit and reusable
  across shape range queries, short-path queries, movement-line validation, and
  unit-only line validation. Avoid adding unrelated booleans to each API.
- Filter inputs should model navigation predicates: tag/self ignore, static vs
  dynamic inclusion, moving-state inclusion, flags, control group, and secondary
  control group. They should not encode unit role, command intent, formation
  assignment, or game-side priority.
- Short-path result failure should expose status/metadata when range, invalid
  query, blocked start, blocked goal, or no local route can be distinguished.
  Adapters should not infer every case from an empty `SimNavWaypointPath`.
- Movement-line validation should answer whether a swept segment is legal
  against passability and filtered obstructions. It must not decide whether a
  unit retries, stops, pushes, yields, or declares itself stuck.
- Unit-only line validation should use the same filter protocol but restrict
  collision to dynamic unit obstruction shapes. It is a primitive for adapters
  that want to know whether the next long-path segment is blocked by units.
- If long-path segment consumption is documented, keep it at the boundary level:
  core may expose the primitive and metadata; lab decides when to ask for a
  short path and how often to retry.
- Lab smoke should prove adapter consumption of filters and line validation
  without rewriting `_move_unit()` / `_resolve_separation()` or importing
  `CCmpUnitMotion` movement policy.

### Documentation Updates Needed

- Update `public-api.md` with the chosen filter DTO/factory names, supported
  predicates, short query status/result metadata, and line-validation result
  contract.
- Update `smoke-matrix.md` with core and lab smoke scenes for filter parity,
  movement-line validation, unit-only line validation, range-limited short
  query status, and adapter-only consumption.

## Feature 7 Request Queue Budget / Worker Contract Source Audit

This section refreshes the Feature 7 target against the local 0 A.D. source.
Use it before changing `SimNavPathRequestQueue`, ticket/result DTOs, or worker
batch semantics. If the source is refreshed, re-check these files before relying
on the bullets below:

```text
source/simulation2/helpers/Pathfinding.h
source/simulation2/components/ICmpPathfinder.h
source/simulation2/components/CCmpPathfinder.cpp
source/simulation2/components/CCmpPathfinder_Common.h
source/simulation2/components/CCmpUnitMotion.h
```

### 0 A.D. Source Facts

- `ICmpPathfinder::ComputePathAsync()` and `ComputeShortPathAsync()` return a
  unique non-zero ticket. The eventual `CMessagePathResult` carries the matching
  ticket and a `WaypointPath`.
- `CCmpPathfinder` stores long and short requests separately but processes both
  through the same `PathRequests<T>` template shape: request vector, result
  vector, atomic next-work index, and compute-done flag.
- `PathRequests::PrepareForComputation(max)` selects how many pending requests
  are eligible for this compute pass. `m_MaxSameTurnMoves` is the configured
  cap when same-turn processing should be budgeted.
- Worker tasks and the main thread share the same request batch through an
  atomic work index. Each worker writes the result slot for its assigned work
  item, preserving ticket/result identity.
- `SendRequestedPaths()` finishes outstanding work, posts short and long
  `CMessagePathResult` messages, then clears only the computed slice. Uncomputed
  requests stay pending for a later pass.
- Pending requests are serialized with the next ticket value. After
  deserialization, the pathfinder starts processing if pending requests exist.
- `CCmpUnitMotion` stores an expected ticket and expected type, ignores obsolete
  path results, and clears the expectation when a matching result arrives.
- `CCmpUnitMotion` also layers gameplay policy on result handling: short-path
  fallback after a failed long path, rejecting paths that move farther from the
  goal, imperfect-path countdown, and target-motion retry cadence.

### Sim Nav Map Feature 7 Implications

- Queue requests should be cloned at enqueue time and identified by stable
  tickets. Later caller mutation must not alter pending work.
- Long and short requests can share ticket lifecycle, cancellation, result
  collection, pending counts, and diagnostics, but their result DTOs should
  retain their own query/result metadata.
- Budgeted processing should define exactly how many requests may be computed
  per call and what remains pending. Result order should be deterministic enough
  for smoke tests to assert ticket identity and stale-result handling.
- 0 A.D. applies its same-turn cap when preparing each request batch. In
  `sim-nav-map`, the queue API exposes an explicit per-call compute cap instead
  of a gameplay turn cadence; adapters decide how often to call it.
- Cancellation should be explicit in `sim-nav-map`, even though 0 A.D. mostly
  relies on consumers ignoring obsolete tickets. This is an intentional API
  improvement for adapters that do not have an engine message bus.
- Worker/batch support should be a queue execution mechanism, not a policy that
  decides when a unit should replan. Lab can choose request cadence and ticket
  invalidation rules.
- Diagnostics should expose navigation scheduling facts such as pending,
  processed, cancelled, stale, worker-running, and result counts. They should
  not expose movement strategy or unit command policy as core state.

### Documentation Updates Needed

- Update `public-api.md` with queue request/result types, ticket lifecycle,
  cancellation behavior, budget semantics, worker semantics, and diagnostics.
- Update `smoke-matrix.md` with core queue smoke for cloning, cancellation,
  partial budget processing, stale result isolation, worker collection, and lab
  adapter consumption.

## Feature 8 Scale Diagnostics And Perf Scenarios Source Audit

This section refreshes the Feature 8 target against the local 0 A.D. source.
Use it before adding diagnostics exports, scale smoke, or benchmark-only scenes.
If the source is refreshed, re-check these files before relying on the bullets
below:

```text
source/simulation2/helpers/Grid.h
source/simulation2/helpers/HierarchicalPathfinder.h
source/simulation2/helpers/HierarchicalPathfinder.cpp
source/simulation2/helpers/LongPathfinder.h
source/simulation2/helpers/VertexPathfinder.h
source/simulation2/components/ICmpPathfinder.h
source/simulation2/components/CCmpPathfinder.cpp
source/simulation2/components/CCmpPathfinder_Common.h
```

### 0 A.D. Source Facts

- `GridUpdateInformation` records whether pathfinding data is dirty, whether it
  is globally dirty, and a per-navcell dirtiness grid. It can merge new updates
  and then clear the source update payload.
- `CCmpPathfinder` keeps internal dirtiness information for pathfinder updates
  and a separate accumulated AI dirtiness payload. The AI-facing payload can be
  read and flushed independently.
- `ICmpPathfinder` exposes the passability grid, AI pathfinder dirtiness
  information, an explicit flush call, and debug data from the latest long-path
  computation.
- `CCmpPathfinder::UpdateGrid()` lazily initializes grids, merges obstruction
  and terrain updates, updates the long pathfinder and hierarchical pathfinder,
  and accumulates AI-facing dirtiness information.
- `HierarchicalPathfinder` builds chunk regions and global regions for
  connectivity. Partial updates can replace dirty chunks and then rebuild global
  region connectivity where needed.
- `HierarchicalPathfinder::GetConnectivityGrid()` generates a read-only grid
  of connected areas for a passability class by mapping reachable regions to
  compact ids.
- Long and vertex pathfinder debug/implementation state exists to reason about
  path computation cost, but 0 A.D. does not turn movement feel, formation
  quality, or deadlock recovery into pathfinder diagnostics.

### Sim Nav Map Feature 8 Implications

- Diagnostics exports should be snapshots, not mutable access to internal grids.
  Useful snapshots include map/navcell size, passability masks, dirty scope,
  obstruction counts, queue counts, last query cost, and connectivity regions.
- Dirtiness exports should distinguish current core dirty state from
  accumulated consumer-facing dirtiness. If a flush API is added, smoke should
  prove it does not clear unrelated internal state needed by pathfinding.
- Connectivity export should be passability-class scoped and should report
  enough metadata for adapters/tests to verify region count and passability
  class identity without depending on internal chunk objects.
- Scale scenarios should separate correctness smoke from benchmark-only runs.
  Correctness smoke can assert stable diagnostics shape and monotonic counters;
  benchmark scenes should document how to run and interpret results without
  making fragile timing thresholds the default gate.
- Lab can render or print diagnostics, but core owns only navigation data. HUD
  layout, movement smoothness, formation behavior, and deadlock recovery remain
  lab/game policy observations.

### Documentation Updates Needed

- Update `public-api.md` with diagnostic DTO names, snapshot fields,
  connectivity/dirtiness export semantics, and any flush behavior.
- Update `smoke-matrix.md` with core diagnostics smoke and any benchmark-only
  scene instructions, clearly separated from required correctness groups.

## Accepted Gap Review Items

These gaps were accepted because they are navigation-core mechanisms, not RTS
gameplay.

| Gap | Implementation area | Why it belongs in core |
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
core commitments until a second example or lab scenario proves the need.

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
