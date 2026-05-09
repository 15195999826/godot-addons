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

## 0 A.D. Reference

Re-check the local 0 A.D. source before changing algorithm shape:

```text
docs/references/0ad-source/source/simulation2/helpers/Pathfinding.h
docs/references/0ad-source/source/simulation2/helpers/Pathfinding.cpp
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
- Terrain fallback now reruns search only when terrain extraction adds vertices.
  This avoids repeating the identical explicit-obstruction graph for dynamic
  unit no-path cases.
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
- [x] `./tools/run_tests.ps1 zeroadlab/smoke simnav/smoke` passes.
- [x] The implementation notes mention which 0 A.D. source files were re-read.
