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
| Unit pushing / crossing | `source/simulation2/components/CCmpUnitMotion_System.cpp`, `source/simulation2/components/CCmpUnitMotionManager.h` | `Push()`, moving-vs-stopped separation rule, initial/final position comparison, perpendicular nudge when moving units appear to cross. |
| Formation as example policy | `source/simulation2/components/CCmpUnitMotion.h`, `source/simulation2/components/CCmpUnitMotion_System.cpp` | formation controller runs before unit motion; same-control-group members ignore each other in obstruction filters and are allowed to push idle members. Useful validation idea, not a core plugin target. |

## Long / Short Path Cooperation Source Audit

This section records the 0 A.D. source-level mental model for how global and
local pathfinding cooperate. Reopen the listed files before using this as an
implementation decision; this note is a source-audit summary, not a replacement
for the local source checkout.

Relevant source files:

```text
source/simulation2/components/CCmpUnitMotion.h
source/simulation2/components/CCmpPathfinder.cpp
source/simulation2/components/ICmpPathfinder.h
source/simulation2/components/ICmpObstructionManager.h
source/simulation2/components/CCmpObstruction.cpp
source/simulation2/components/CCmpObstructionManager.cpp
source/simulation2/helpers/LongPathfinder.cpp
source/simulation2/helpers/VertexPathfinder.cpp
```

### 0 A.D. Source Facts

- `CCmpUnitMotion::MoveTo()` computes a goal and immediately calls
  `ComputePathToGoal()`. That function is the first long-vs-short path decision
  point for a move order.
- If the target is close and `TryGoingStraightToTarget(from, false)` succeeds,
  UnitMotion clears the short path but still requests a long path. The comment
  says this is a hedge because the next frame may fail the straight move, and
  the long path should stay up to date.
- Otherwise `ComputePathToGoal()` chooses short path when the goal is in short
  range and long path when it is farther away. `ShouldAlternatePathfinder()` can
  flip that choice after repeated failures, so short and long are recovery
  alternatives as well as range-based tools.
- Long and short path requests are asynchronous ticketed requests through
  `CCmpPathfinder`. The result message only carries the ticket and
  `WaypointPath`; `CCmpUnitMotion::PathResult()` ignores obsolete tickets before
  writing either `m_LongPath` or `m_ShortPath`.
- Movement consumes `m_ShortPath` first when it exists; otherwise it follows
  `m_LongPath`. The actual segment advance is still checked by movement-line
  validation, so a path result is a plan, not permission to teleport through a
  later obstruction.
- While following a long path with no active short path, `PostMove()` checks the
  next long waypoint with `TestUnitLine()`. If a dynamic unit obstruction is in
  front, it requests a short path toward a circle around a later long waypoint,
  or toward the final goal when there is no later waypoint.
- On blocked movement, `HandleObstructedMove()` treats the long path as
  salvageable first: it may skip a nearby long waypoint, request a short path to
  the vicinity of the next long waypoint, use a small backup hack near corner
  mismatch cases, or occasionally request a fresh long path.
- `PathingUpdateNeeded()` gates path churn for moved targets or invalid final
  waypoints, and `m_FollowKnownImperfectPathCountdown` suppresses repeated
  updates for a short period when a known imperfect path should still be
  followed.

### Dynamic Obstruction Policy

- `LongPathRequest` does not carry `avoidMovingUnits` or control-group inputs.
  Long path computation is driven by the passability grid and hierarchical/JPS
  layers.
- `CCmpPathfinder::UpdateGrid()` builds that grid from terrain and rasterized
  obstructions. Rasterization uses `FLAG_BLOCK_PATHFINDING`; the obstruction
  component schema explicitly describes `BlockPathfinding` as something that
  should only be set for large stationary obstructions.
- This means standard moving unit avoidance is not a global long-path concern.
  A unit-shaped obstruction can technically be rasterized if it has
  `FLAG_BLOCK_PATHFINDING`, but the intended high-frequency moving-unit path is
  local handling, not constantly changing the global long-path grid.
- `ShortPathRequest` does carry `avoidMovingUnits` and a control group.
  `VertexPathfinder::ComputeShortPath()` builds a bounded visibility graph from
  static obstructions and unit obstructions inside the local search range.
- `ICmpObstructionManager::TestLine()` and `TestUnitLine()` are the runtime
  legality checks used by UnitMotion. This is where dynamic unit collisions are
  observed while executing or pre-checking a segment.
- `CCmpUnitMotionManager::Push()` deliberately separates moving-moving and
  stopped-stopped pairs, but returns for moving-vs-stopped pairs. For
  moving-moving pairs it compares initial and final relative positions and
  applies a perpendicular nudge when the units appear to have crossed paths.
- `CCmpUnitMotionManager::Push()` has a same-control-group exception for
  formations: same-group members are treated like a stopped-stopped pair for
  push purposes, and same-group idle members may be pushed. The comment ties
  this to formation-internal obstruction ignoring.
- Pushing also maintains `pushingPressure`. `PerformMove()` slows a unit when
  pressure is high, and `PushAdjust` marks a moving unit obstructed when a push
  would drive it away from its attempted movement direction. This prevents
  repeated crowd pressure from shoving a unit far off its own route before
  blocked-move recovery has a chance to react.

### Sim Nav Map Implications

- Do not model dense dynamic units as a reason for the long pathfinder to
  globally reject or rebuild routes. That would make global path work scale with
  transient crowd layout and would fight the 0 A.D. separation of concerns.
- Long-path post-processing should be strict about static/passability legality:
  it must not create a waypoint segment that crosses blocked terrain or a
  rasterized static obstruction for the unit's clearance.
- Dynamic-unit avoidance belongs in local policy: unit-line pre-checks,
  short-path requests to a nearby long-path rejoin goal, blocked-move recovery,
  request cooldowns, and per-tick request budgets.
- Formation policy must assign slots before UnitMotion consumes paths. A
  naive id-sorted slot assignment can create crossing paths inside the
  formation; the lab should prefer a minimal-distance slot assignment before
  relying on local push recovery.
- If moving-moving push repeatedly moves a unit opposite its own target, the lab
  should damp that push or raise an obstruction signal, mirroring 0 A.D.'s
  pressure behavior. Otherwise the unit can be pushed into a static clearance
  corner and the short pathfinder may legitimately choose a visually odd
  retreat waypoint to get back out.
- This formation/push-recovery guidance was written against the RTS-formation
  style `0ad-rts-pathfinding-lab`, deleted 2026-07-03 — the remaining
  `dota2-rts-pathfinding-lab` has no formation concept (contact-resolved
  separation instead, see its `docs/design-notes/fable-motion-design.md`), so
  this specific paragraph doesn't transfer 1:1. Kept as 0 A.D. source-behavior
  reference for if a formation-style consumer is ever built again. In such a
  lab, a dense moving crowd should increase local short-path and blocked-move
  activity, not cause repeated global long-path rejection; long-path churn
  under moving-unit pressure would be a policy bug in the lab layer, not core.
- Useful diagnostics for this boundary are: long/short request counts,
  cancelled or obsolete tickets, `repath_suppressed`, path queue processed
  counts, blocked moves, unit-line failures, and frame average/max time.

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
- Example labs consume result metadata through adapter reports only (true of
  the deleted `0ad-rts-pathfinding-lab` and of the current
  `dota2-rts-pathfinding-lab` alike). Feature 5 did not move
  `CCmpUnitMotion`-style short-path fallback, retry cadence, push/yield,
  stuck/deadlock, formation, or movement controller policy into core.

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

### Sim Nav Map Feature 6 Implementation Notes

- Movement-line passability validation should walk every crossed navcell, like
  0 A.D. `Pathfinding::CheckLineMovement()`. Uniform sampling can miss a
  briefly crossed blocked navcell, so the core smoke includes an adversarial
  diagonal segment for this case.
- Movement-line passability validation should not expand by clearance again.
  `sim-nav-map` rasterizes terrain/static obstruction clearance into the
  passability grid per class, so line validation should test the path-center
  navcells against the already-expanded mask.
- Short-path visibility edges must satisfy both exact obstruction line-of-sight
  and passability-grid line validation. This keeps local vertex paths from
  accepting a tangent geometry edge that crosses a rasterized blocked cell.
- 0 A.D. control groups are not factions. `CCmpUnitMotion::GetGroup()` uses the
  formation controller for formation members and otherwise falls back to the
  unit's own entity id; `PreMove()` only exports a formation control group.
  Therefore same-faction non-formation units still block short paths and
  movement-line validation. Lab adapters should keep `group_id` as team/faction
  data and ignore only the querying entity unless a real formation controller is
  introduced.
- 0 A.D. push/separation also uses each unit's initial and final motion-state
  positions to detect crossed paths, then applies a perpendicular nudge. The
  current 0AD lab only fixes the control-group/faction mismatch; if narrow
  passage swaps still appear, the next source-aligned improvement is to add
  motion-state crossing detection rather than loosening clearance.
- `CCmpObstructionManager::TestLine()` / `TestUnitLine()` call
  `Geometry::TestRaySquare()` / `TestRayAASquare()`, whose collision rule is
  directional: a ray starting inside an obstruction is not considered a new
  collision. This lets overlapped units move out of each other instead of being
  permanently blocked by their current overlap; only outside-to-inside or
  outside-through-obstruction segments are blocked.
- With pushing enabled, `CCmpUnitMotion::ShouldCollideWithMovingUnits()`
  returns false, so moving unit obstructions are ignored by short path and
  movement-line checks; idle unit obstructions still block. The motion manager
  then handles moving-moving contact through push.
- `CCmpUnitMotionManager::Push()` deliberately separates moving-moving and
  stopped-stopped pairs, but returns immediately for moving-stopped pairs.
  Moving-stopped soft push only exists for the same formation control group,
  which the current 0AD lab does not model yet.
- The core line-validation primitive should permit a unit to move out of an
  existing unit overlap, but should not permit a segment that stays inside or
  moves deeper into that overlap. This preserves 0 A.D.'s practical "escape
  from overlap" behavior without letting an already-overlapped unit tunnel
  farther through another unit.
- The 0AD lab maps `Push()`/`PushAdjust` pressure into motion policy, not core
  navigation policy. Once pushing pressure has marked a moving-moving contact
  as obstructing, the lab may hold a step that would deepen overlap and let
  push/blocked recovery separate the pair. This is a lab-side guard against
  visible 60 Hz pass-through in one-unit corridors, while long path and short
  path contracts remain unchanged.

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
