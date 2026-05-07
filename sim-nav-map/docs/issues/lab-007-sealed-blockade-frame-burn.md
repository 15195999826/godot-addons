# LAB-007: Sealed-blockade separation budget burn

- Status: open
- Severity: P1
- Layer: lab
- Source: user export-log report
- Created: 2026-05-07

## Symptoms

User repro: "Place obstacles to dynamically seal every passable route to
the move target. Once the last route closes, frame time spikes."

Export log
`C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/rts_pathfinding_lab_logs/rts_pathfinding_lab_2026-05-07T21-02-10_tick_716.json`
captures the steady state after sealing:

```text
perf.last_step_usec = 13860
perf.max_step_usec  = 15358
perf.avg_step_usec  = 6814   (716 measured ticks)
recent_events: place_obstacle_1 → max_step 1501 → place_obstacle_2 → max 5485
              → place_obstacle_3 → max 10087 → tick 716 → max 15358
```

The 6 mobile blue units are trapped in a thin enclave bounded by
`stone_block` + `north_wall` + `south_wall` (defaults) on the west and
`custom_obstacle_1` + `custom_obstacle_2` (+`_3`) on the east. The move
target `(610, 210)` lives in a different global region, so:

- 4 blue settle to `arrived=true` after canonicalization picks a
  reachable goal at their feet (`distance_to_reachable_goal ≈ 18 px`)
  and the resulting one-step path closes immediately
- 2 blue (`blue_2`, `blue_5`) keep `has_move_order=true` with
  `path_len=1`, replanning every `REPLAN_INTERVAL=0.45 s`
- `last_report` shows the lab path query is cheap:
  `reachability_usec=1072`, `vertex_usec=346` ⇒ ≈1.4 ms per unit; even
  with 2 active replanners that is only ≈3 ms

## Current read

The dominant cost is **separation**, not pathfinding. The hot path is
`RtsPathfindingLabWorld._resolve_separation()`:

```text
SEPARATION_STABILIZE_ITERATIONS = 6
OVERLAP_RESOLVE_ITERATIONS       = 4
SEPARATION_TOTAL_BUDGET_USEC     = 16000   ← effective frame ceiling
```

Every tick six tightly-packed mobile units adjacent to three static
inflated rectangles repeatedly trigger micro-pushes. The inner
`changed` flag flips on any displacement (no `≥ ε` threshold), so the
outer stabilize loop never early-exits and the budget guard is the
only escape. That explains the 13–15 ms steady state: separation
spends almost all of the 16 ms ceiling, plus the ≈1.4 ms × 2 path
queries leaks through the per-unit `_move_unit` work. The
`reachability_canonicalized=true` + `reachable_goal ≈ unit.position`
state means the planner cannot help the unit move out — every replan
returns the same near-self canonical goal.

This is distinct from LAB-002 ("rapid obstacle edits while moving"):

- LAB-002 stress: dominant cost is path queries / obstacle rebuild
  during dynamic edits; units are still mobile.
- LAB-007 sealed: dominant cost is `_resolve_separation`'s 16 ms
  budget burning in steady state after edits stop.

LAB-002's per-frame path-budget fix would not close LAB-007 because
the ceiling is hit even when no replan runs that tick.

## Investigation backlog

- Confirm by phase profiling that `separation_usec` is the dominant
  share of `last_step_profile` after sealing (export log only carries
  `total_usec`; the smoke can read `world.last_step_profile`).
- Validate the `changed`-flag jitter hypothesis: log per-unit
  displacement magnitudes inside `_push_out_static_obstacles_for_units`
  for one tick after sealing.
- Check whether `reachable_goal` (canonicalized to ≈ unit position)
  could be detected as "stuck-unreachable" so future replans short
  circuit until obstacle revision changes.
- Cross-check with CORE-003 (region-graph walk for
  `find_nearest_passable_navcell`): when `start_global == 0` and the
  unit is sealed, that fallback walks the chunk grid; not the path
  here (start is passable) but worth keeping in mind for true sealing
  cases.

## Proposed approach

1. Add a stuck early-exit to `_resolve_separation` /
   `_resolve_overlaps`: a push only counts as `changed` if the unit's
   final displacement for the iteration is ≥ a small epsilon (e.g. one
   navcell or radius-fraction). Jitter below the threshold returns
   `changed=false` and the outer loop ends immediately.
2. Tighten `SEPARATION_TOTAL_BUDGET_USEC` once (1) lands and the
   typical separation time drops; re-measure.
3. (Stretch) Suppress the 0.45 s replan timer when the planner returns
   `reachable_goal.distance_to(unit.position) <= unit.radius` and the
   obstacle revision has not changed. Resume on next obstacle edit.
4. (Stretch) Keep an obstacle-revision keyed unreachable cache at the
   lab pathfinder so the cheap-but-recurrent 1.4 ms reachability call
   becomes O(1) for the same key.

## Verify before fixing

- [x] Confirm `last_step_profile.separation_usec` accounts for ≥ 80 %
      of the 13–15 ms peak in the repro — measured 99.4 % at HEAD
- [x] Decide threshold: `max_step_usec ≤ 4000 µs` (consistent with
      LAB-002) — locked in for the smoke; revisit after fix lands

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_007_sealed_blockade.tscn
```

Smoke: [`examples/rts-pathfinding-lab/tests/repro/repro_lab_007_sealed_blockade.gd`](../../examples/rts-pathfinding-lab/tests/repro/repro_lab_007_sealed_blockade.gd).

Setup faithfully replays the user's operation timeline (no teleport,
no synthetic state injection):

1. `setup_default()` — six blue mobiles at `x≈74-104`, group target
   `(610, 210)`; blue starts moving on tick 1.
2. At tick 41: `add_static_obstacle((423, 155))`.
3. At tick 89: `add_static_obstacle((421, 284))`.
4. At tick 140: `add_static_obstacle((434, 395))` — completes the seal.
5. Continue stepping `1/60` until tick 716 (matches the user export's
   `measured_step_count`).

Track max single-step wall time across the entire 716-tick run, and
also break it out into pre-seal (`tick < 140`) vs post-seal windows.
Threshold `≤ 4 000 µs` (BASELINE 13–15 ms).

At HEAD the smoke FAILs:

```text
LAB-007 sealed-blockade max_step_usec = 13965 µs at tick 628
  (pre-seal max 8598 µs, post-seal max 13965 µs,
   separation peak 13883 µs at tick 628)
SMOKE_TEST_RESULT: FAIL - LAB-007 reproduces: ... separation peak 13883 µs (99.4 % of total)
```

The post-seal peak hits within 10 % of the user's reported
`max_step_usec = 15358 µs`, and `separation_usec` accounts for ≥ 99 %
of the spike — locking in the "separation budget burn" diagnosis
without depending on a teleport shortcut. The pre-seal max of 8598 µs
also matches the rising-edge behavior the user's `recent_events`
captured (`max_step_usec` climbed 1501 → 5485 → 10087 → 15358 across
the three `place_obstacle` events).

## Cross-refs

- [LAB-002](lab-002-stress-long-frames.md) — same layer, different
  shape (rapid edits vs sealed steady state); fixes do not subsume
  each other but should be re-measured together.
- [LAB-003](lab-003-active-jump-55px.md) — another consequence of
  long synchronous frames.
- [LAB-006](lab-006-empty-path-after-long-path-success.md) — same
  scene topology family (stone_block + walls + custom obstacles),
  earlier failure mode in this geometry.
- [PROCESS-001](process-001-core-lab-proof-protocol.md) — apply
  before promoting any fix to a core issue.
