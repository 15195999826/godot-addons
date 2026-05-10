# 0AD Lab Short Path Visibility Optimization Goals

This document is the working target for optimizing short-path performance in
`examples/0ad-rts-pathfinding-lab`.

Do not treat the older `docs/issues/LAB-*` files as the issue tracker for this
lab. Those files describe the legacy `examples/rts-pathfinding-lab` and can
only be used as historical context after the same symptom is reproduced in this
0AD lab.

## Problem

The current 0AD lab can produce long single-frame stalls when a short-path
request builds a local visibility graph around dense static terrain or dynamic
blockers.

Known trigger:

```text
C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/zero_ad_rts_pathfinding_lab_logs/zero_ad_rts_lab_2026-05-09T15-10-09_tick_2592.json
```

That export reported `perf.max_step_usec = 226571`. Older exports did not yet
carry exact per-frame stage profiles, so the first task is to keep diagnostics
strong enough that the next spike can be attributed to a specific request and
stage.

Recent exploratory profiling before the final optimization pass showed this
shape:

| Scenario | Before prototype | After current terrain-span prototype | Notes |
|---|---:|---:|---|
| `fully_blocked_path` | ~268 ms short request | ~32 ms short request | Better, still unacceptable |
| `partial_wall_with_gap` | ~294 ms short request | ~25 ms short request | Better, still unacceptable |
| `rapid_obstacle_thrash` | 300 ms+ | 300 ms+ | Mostly dynamic-blocker churn, separate stage |

These numbers are observation snapshots, not acceptance targets.

Current result after the 2026-05-09 optimization pass:

| Scenario | `avg_step_usec` | `max_step_usec` | `max_short_compute_usec` | Notes |
|---|---:|---:|---:|---|
| `baseline_open_movement` | 717.46 | 9666 | 0 | No short requests; average remains in the same practical band for this lab run. |
| `fully_blocked_path` | 782.20 | 22589 | 1922 | Static short-path spike removed; slowest frame is long-path setup. |
| `partial_wall_with_gap` | 724.11 | 24641 | 936 | Arrives `6/6`; static short-path spike removed. |
| `rapid_obstacle_thrash` | 4624.46 | 45484 | 27803 | Still a dynamic blocker thrash / runaway problem and not claimed solved here. |

Follow-up source pass on 2026-05-09:

| Scenario | `avg_step_usec` | `max_step_usec` | `max_short_compute_usec` | Notes |
|---|---:|---:|---:|---|
| `baseline_open_movement` | 710.57 | 9406 | 0 | Still flat against the previous headless baseline. |
| `fully_blocked_path` | 777.84 | 22715 | 2109 | Static short path remains under target; slowest frame is long-path setup. |
| `partial_wall_with_gap` | 725.77 | 24494 | 961 | Arrives `6/6`; static short path remains under target. |
| `rapid_obstacle_thrash` | 3436.82 | 16636 | 13562 | Improved by virtual-goal search and no-op terrain fallback guard, but still a dense dynamic-unit no-path problem. |

Interactive export `zero_ad_rts_lab_2026-05-09T18-09-04_tick_4443.json`
showed a different spike shape: stable lifetime `avg_step_usec` was
`564.75`, but the worst frame was `19985us` at tick `4057`. That frame was
not a short-path visibility spike. Its `path_budget_usec` was `19130us`, caused
by two synchronous long-path requests in the same tick (`9582us` and `9408us`).

After adding the synchronous elapsed budget, exploration no longer combines two
very expensive long paths into one 19ms-class frame. The remaining worst frames
are either one expensive long-path request or two cheaper requests that still
fit the count budget:

| Scenario | `avg_step_usec` | `max_step_usec` | `max_short_compute_usec` | Notes |
|---|---:|---:|---:|---|
| `baseline_open_movement` | 790.96 | 5245 | 0 | Initial long paths are spread over later ticks. |
| `fully_blocked_path` | 890.96 | 11792 | 2050 | Static short path still under target; worst frame is one long path. |
| `partial_wall_with_gap` | 748.64 | 12451 | 957 | Arrives `6/6`; worst frame is one long path. |
| `rapid_obstacle_thrash` | 3490.61 | 7896 | 2412 | Still a dynamic blocker thrash / runaway loop issue, but no 19ms frame in this run. |

Long-path follow-up on 2026-05-09:

0 A.D. `LongPathfinder::ComputePath()` routes through `ComputeJPSPath()`,
tracks `PathfinderState.steps`, uses `JumpPointCache`, reconstructs a reverse
waypoint path, and then runs `ImprovePathWaypoints()` on the JPS waypoint chain.
The local queued/result path contract was still using dense `_astar_cells()`.
That made the remaining long-path spike a real algorithm mismatch, not a short
path visibility regression.

The current result path now uses JPS for ordinary long-path result queries,
keeps request-scoped `excluded_regions` on the A* path because local JPS does
not support exclusions yet, and exports long-search diagnostics:
`search_algorithm`, `search_expansion_count`, `search_push_count`,
`search_jump_count`, `search_closed_count`, `search_max_open_count`, and
`search_path_cell_count`.

One local JPS correctness gap was fixed while doing this pass: cardinal
successor pruning now follows the 0 A.D. shape that adds both the forward
diagonal and the perpendicular jump when the tile behind the side channel is
blocked. This removed the old hidden dependency on `compute_path_immediate()`'s
A* fallback for wall and start-recovery cases.

The JPS chain is still expanded for `raw_navcell_path` export so the public
result contract remains start-to-goal navcells, but line-of-sight refinement now
uses the sparse JPS chain, matching 0 A.D.'s `ImprovePathWaypoints()` strategy
more closely.

Latest exploration after this pass:

| Scenario | `avg_step_usec` | `max_step_usec` | Max long request | `max_short_compute_usec` | Notes |
|---|---:|---:|---:|---:|---|
| `baseline_open_movement` | 700.11 | 6071 | 2778 | 0 | Max frame is two JPS long requests in one tick. |
| `fully_blocked_path` | 673.09 | 7099 | 3346 | 0 | Static short path is no longer the spike; no runaway replan in this run. |
| `partial_wall_with_gap` | 650.28 | 7085 | 3291 | 0 | Arrives `6/6`; max frame is two JPS long requests. |
| `rapid_obstacle_thrash` | 2568.07 | 6305 | 2878 | 2471 | Still dynamic blocker thrash, but no 19ms frame in this run. |

Conclusion: the single long-path 9-12ms spike is addressed in this run. The
remaining 6-7ms max frames are primarily two 2-3.4ms synchronous JPS long
requests sharing one tick, plus dynamic-thrash policy work in the stress phase.
That is a scheduler / motion-policy follow-up, not the original long-path
algorithm spike.

Interactive behavior follow-up on 2026-05-09:

```text
C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/zero_ad_rts_pathfinding_lab_logs/zero_ad_rts_lab_2026-05-09T18-57-37_tick_5476.json
```

This export did not contain a performance spike (`slow_frames = 0`,
`avg_step_usec = 488.14`, `max_step_usec = 7459` at tick 2), but it did expose
two behavior diagnostics:

- Unit-made chokepoints can look passable while the exact movement line is
  blocked by another stationary unit. This matches the 0 A.D. split: ordinary
  dynamic units are handled by `TestUnitLine()` / short path, not by long-path
  global passability. This is a visual / local-geometry edge case, not a
  current long-path bug.
- Some short-path results contained duplicate adjacent waypoints when the
  dynamic virtual goal landed on an obstruction-corner vertex, for example
  paths shaped like `goal-corner -> same corner -> next corner`. This is a
  core short-path quality bug and is now covered by
  `smoke_sim_nav_vertex_pathfinder`.

## 0 A.D. Reference

Re-check the local 0 A.D. source before changing algorithm shape:

```text
docs/references/0ad-source/source/simulation2/helpers/Pathfinding.h
docs/references/0ad-source/source/simulation2/helpers/Pathfinding.cpp
docs/references/0ad-source/source/simulation2/helpers/LongPathfinder.h
docs/references/0ad-source/source/simulation2/helpers/LongPathfinder.cpp
docs/references/0ad-source/source/simulation2/helpers/VertexPathfinder.h
docs/references/0ad-source/source/simulation2/helpers/VertexPathfinder.cpp
docs/references/0ad-source/source/simulation2/components/CCmpPathfinder.cpp
docs/references/0ad-source/source/simulation2/components/ICmpObstructionManager.h
docs/references/0ad-source/source/simulation2/components/CCmpUnitMotion.h
```

Relevant 0 A.D. strategy:

- Short path is local. `ShortPathRequest` carries clearance, range,
  passability, moving-unit avoidance, and control group; it does not own motion
  policy.
- `VertexPathfinder::ComputeShortPath()` clamps work to a finite search range
  and adds the range boundary as impassable edges.
- When the target lies outside range, 0 A.D. shifts the local search window
  toward the goal instead of growing it globally.
- Static and unit obstructions are queried by range before visibility graph
  construction. The graph should not receive every explicit static/unit shape
  on the whole map.
- Terrain passability is converted into edge geometry by `AddTerrainEdges()`;
  it does not create one independent obstacle per blocked navcell.
- Visibility checks have constant-factor pruning: axis-aligned edge fast paths,
  `quadInward` / `quadOutward` quadrant checks, nearest-edge partial sorting,
  and a virtual goal vertex for non-point goals.
- Async request processing exists in 0 A.D., but it is a scheduling decision,
  not a substitute for making each short-path query cheap enough.
- Long/short path requests are queued through `CCmpPathfinder::ComputePathAsync()`
  and `ComputeShortPathAsync()`. `CSimulation2Impl::UpdateComponents()` processes
  limited same-turn batches with `StartProcessingMoves(true)` and then starts
  uncapped worker processing at turn end with `StartProcessingMoves(false)`.
  The cap is `MaxSameTurnMoves`, loaded in `CCmpPathfinder::Init()`, and exists
  specifically to avoid spending too much time in the immediate feedback phases.
  In the Godot lab, which intentionally does not use async workers for this
  phase, the equivalent guard is a synchronous elapsed-time budget layered on
  top of the existing request-count budget.

Source files re-read for the current implementation:

- `VertexPathfinder.cpp`: `ComputeShortPath()`, `AddTerrainEdges()`,
  `CheckVisibility*()`, `SplitAAEdges()`.
- `VertexPathfinder.h`: short-path API and range contract.
- `Pathfinding.h`: `ShortPathRequest` / movement-line contracts.
- `ICmpObstructionManager.h` and `CCmpObstructionManager.cpp`:
  obstruction filters, `GetStaticObstructionsInRange()`,
  `GetUnitObstructionsInRange()`, `TestLine()`, and `TestUnitLine()`.
- `CCmpPathfinder.cpp`: `CheckMovement()`.
- `CCmpUnitMotion.h`: `RequestShortPath()`,
  `ShouldCollideWithMovingUnits()`, and target/short-path handoff behavior.
- `LongPathfinder.h` / `LongPathfinder.cpp`: `PathfinderState`,
  `JumpPointCache`, `ComputeJPSPath()`, cardinal/diagonal jump expansion,
  path reconstruction, and `ImprovePathWaypoints()`.

## Current Implementation Notes

The first-stage optimization now follows this shape:

- Explicit static and dynamic obstruction collection is range-limited via
  `SimNavMap.get_static_obstruction_shapes_in_range()` and
  `SimNavMap.get_dynamic_obstruction_shapes_in_range()` before graph vertices
  are built.
- Terrain passability no longer creates dense per-navcell obstruction spans for
  every short-path graph. Terrain boundary vertices are extracted only as a
  fallback after explicit obstruction vertices fail to produce a path.
- Static obstruction corner vertices can include request-level raster slack.
  The 0AD lab sets this to half a navcell so paths around explicit OBBs clear
  its rasterized passability margin without changing the core default OBB
  corner contract.
- Lazy visibility A* now prunes expansion to the goal plus nearest candidate
  vertices instead of checking every vertex against every other vertex.
- Non-point short goals now use one dynamic virtual goal vertex, following 0 A.D.
  `VertexPathfinder::ComputeShortPath()` more closely. The goal point is
  recomputed from the current vertex instead of trying several fixed goal
  candidates and rerunning visibility search.
- If a visibility vertex already lies inside the non-point short goal, the
  search now reconstructs the path to that vertex directly instead of appending
  a duplicate virtual-goal waypoint at the same position.
- Terrain fallback now reruns search only when terrain extraction adds vertices.
  This avoids repeating the identical explicit-obstruction graph for dynamic
  unit no-path cases.
- `SimNavPathRequestQueue.process_budget()` now accepts an optional elapsed
  microsecond budget. The 0AD lab still caps requests by count, but also stops
  after the first live request that exhausts the synchronous budget. The lab
  default is `3500us`, so cheap requests can still share a frame while expensive
  long paths are spread over later ticks instead of combining into one visible
  frame spike.
- `SimNavLongPathfinder.compute_path_result()` now uses JPS for ordinary result
  queries, preserving A* only for request-scoped `excluded_regions`. The local
  JPS cardinal successor pruning was corrected against 0 A.D.'s
  `AddJumpedHoriz()` / `AddJumpedVert()` expansion shape.
- Long-path result diagnostics now expose search structure (`search_algorithm`,
  expansion/push/jump/closed/max-open counts, and sparse path cell count), so
  slow frames can distinguish search growth from scheduling multiple path
  requests in one tick.
- JPS result queries refine the sparse JPS waypoint chain while still exporting
  dense `raw_navcell_path` for the existing public result contract.
- `SimNavShortPathResult` and path request batch diagnostics expose structural
  counters: explicit static/unit obstruction counts, terrain edge/vertex count,
  total vertex count, visibility check count, and A* expansion count.

The remaining `rapid_obstacle_thrash` spike is now characterized by dense
dynamic blockers, not static terrain. The latest worst request had
`explicit_unit_obstruction_count=21`, `vertex_count=90`,
`visibility_check_count=586`, and `astar_expansion_count=65`. This points to a
second-stage dynamic-unit visibility pruning / movement policy problem rather
than a return of the static short-path graph explosion.

## Scope

In scope:

- `SimNavVertexPathfinder` visibility graph construction and edge checks.
- Diagnostics needed to prove where a short-path spike happened.
- 0AD lab smoke/exploration tests that lock behavior while performance changes.

Out of scope for this optimization:

- Moving long-path or short-path computation to an async worker.
- Changing motion policy thresholds to hide the spike.
- Formation behavior beyond preserving current control-group filtering.
- Reusing old `examples/rts-pathfinding-lab` issue assumptions without a new
  0AD lab repro.

## Target

Primary target for static terrain / static obstacle short paths:

- `fully_blocked_path`: no single short request above 8 ms.
- `partial_wall_with_gap`: no single short request above 8 ms.
- Default playable scene: average step time must not meaningfully regress from
  the current measured headless exploration baseline. In this pass it stayed
  effectively flat: `700.64us` before vs `717.46us` after.
- No static-passability penetration and no return of the previous corner
  backtrack behavior.

Stretch target:

- Static short-path spikes stay below 4 ms on the lab machine.

Separate second-stage target for dynamic blocker thrash:

- Keep dynamic-unit avoidance behavior correct first.
- Do not solve dynamic thrash by making long path consider every moving unit.
  That would contradict 0 A.D.'s separation: long path remains mostly static /
  passability based, while short path and movement-line validation handle local
  dynamic obstruction.

## TDD Plan

Use a performance-invariant TDD loop, not a traditional unit-only TDD loop.

1. Add or keep a failing repro that captures the current spike on the 0AD lab,
   using `world.last_step_profile.path_request_batch[*].compute_usec` rather
   than only `perf.max_step_usec`.
2. Assert behavior invariants in the same repro:
   `partial_wall_with_gap` still reaches, `fully_blocked_path` does not spin
   forever, static line validation stays legal, and request count stays bounded.
3. Add structural metrics before optimizing if wall-clock is too noisy:
   explicit static count, explicit unit count, terrain-edge count, vertex count,
   visibility-check count, and A* expansion count.
4. Make one algorithmic change at a time.
5. Re-run `zeroadlab/smoke`, `simnav/smoke`, and the exploration playthrough.
6. Only lower the threshold after the algorithmic bottleneck is actually
   removed. A loose threshold that merely permits 25-32 ms should be treated as
   a regression guard, not a success criterion.

## Candidate Optimizations

Prioritize changes that match 0 A.D.'s strategy and preserve a single clear
logic path.

1. Range-limit explicit static and dynamic obstruction collection before graph
   construction. This mirrors 0 A.D.'s `GetStaticObstructionsInRange()` /
   `GetUnitObstructionsInRange()` call shape and prevents distant map objects
   from inflating every short-path graph.
2. Replace per-blocked-navcell obstacle expansion with terrain-edge extraction.
   This is the biggest suspected gap because one blocked region should become
   a small set of boundary edges, not hundreds of mutually visible rectangles.
3. Add visibility-graph structural counters so the test can prove reduced
   graph size, not just lucky wall-clock.
4. Add quadrant pruning for obstacle-corner vertices after terrain-edge
   extraction is stable.
5. Add nearest-edge / partial-sort style checks if edge counts are still high.
6. Consider virtual goal handling only if multiple goal candidate searches are
   shown to dominate.

Avoid these as first-line fixes:

- Raising cooldowns or shrinking search range until the core graph cost is
  understood.
- Async worker migration.
- Long path dynamic-obstacle rejection.
- Extra fallback routes that mask a blocked visibility graph instead of making
  the graph smaller and correct.

## Acceptance Checklist

- [x] The document's repros are current 0AD lab repros, not legacy lab issues.
- [x] Slow-frame exports include exact tick and stage profile for spikes.
- [x] Short-path graph construction range-filters explicit static/unit shapes.
- [x] Static short-path repros prove `compute_usec < 8000`.
- [x] `partial_wall_with_gap` still arrives.
- [x] `fully_blocked_path` remains bounded and does not repeatedly replan.
- [x] `rapid_obstacle_thrash` is measured separately and not claimed solved by
      the static optimization.
- [x] Duplicate short-path virtual-goal waypoints are covered by a core smoke
      test and are not mixed with dynamic-unit chokepoint policy.
- [x] `./tools/run_tests.ps1 zeroadlab/smoke simnav/smoke` passes.
- [x] The implementation notes mention which 0 A.D. source files were re-read.
