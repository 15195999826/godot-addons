# LAB-007: Sealed-blockade separation budget burn

- Status: open (partial fix landed 2026-05-07; smoke pulled from rtslab/smoke until full target hit)
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

1. **[DONE]** Add a stuck early-exit to `_resolve_separation`: track
   each outer iter's start positions; bail when (a) no unit's net
   displacement in the iter exceeds a jitter epsilon, (b) end-of-iter-K
   ≈ start-of-iter-K-1 (2-cycle), or (c) end-of-iter-K ≈
   start-of-iter-K-2 (3-cycle).
2. **[DONE]** Skip the second `_push_out_static_obstacles_for_units`
   call within an outer iter when `_resolve_overlaps` reported no
   change — units are still in the post-static-1 configuration so the
   second pass would just regenerate candidates for nothing.
3. **[DONE]** All-exhausted short-circuit at the top of
   `_resolve_overlaps`: when every mobile unit has spent its per-frame
   overlap budget, no pair-check inner loop can move anyone — return
   immediately instead of running the O(N²·OVERLAP_RESOLVE_ITERATIONS)
   pass.
4. **[DONE]** Reduce `SEPARATION_STABILIZE_ITERATIONS` from 6 → 2.
   The early-exits (1) above already terminate normal-density scenes
   in 1–2 outer iters; capping the loop bounds the worst case in the
   sealed-enclave regime where the unit positions never quite converge
   to a fixed point.
5. **[DONE — lightweight]** Suppress the 0.45 s timer-triggered replan
   when the planner can only canonicalize the goal back to within
   `unit.radius` of `unit.position`. Don't force `arrived` /
   `has_move_order=false` — `_move_unit` reaches arrival naturally
   once the (typically 0–1 step) micro path drains, and forcing it
   early leaves overlap unresolved which paradoxically grows
   separation cost (verified: heavy variant +50 % sep peak;
   lightweight variant ≈ break-even on its own but combines cleanly
   with (1)–(4)). `_replan_all_mobile` resurrects parked units for
   re-routing on obstacle edits; `set_units_target` clears the parked
   flag for an explicit new command.
6. (Open / stretch) Cache the candidate-generation work inside
   `_push_unit_out_of_static_component`: profiling shows the second
   static-push pass takes ~1.5 ms per unit when units are crammed
   against multiple inflated rects. A per-frame, position-keyed cache
   could cut this further once (1)–(4) saturate.
7. (Open / stretch) Address the `add_static_obstacle` placement
   spike (~8 ms at the tick when `prewarm_static_context` triggers
   the next replan's nav-map rebuild). Possibly belongs in a
   sibling issue — it's a transient, not the steady-state burn.

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

### Pre-fix (commits before 2026-05-07 separation early-exit)

```text
LAB-007 sealed-blockade max_step_usec = 13965 µs at tick 628
  (pre-seal max 8598 µs, post-seal max 13965 µs,
   separation peak 13883 µs at tick 628)
SMOKE_TEST_RESULT: FAIL - LAB-007 reproduces: ... separation peak 13883 µs (99.4 % of total)
```

The post-seal peak hits within 10 % of the user's reported
`max_step_usec = 15358 µs`, and `separation_usec` accounts for ≥ 99 %
of the spike — locking in the "separation budget burn" diagnosis
without depending on a teleport shortcut.

### Post-fix (Approach items 1–5 landed)

```text
LAB-007 sealed-blockade max_step_usec = 8871 µs at tick 89
  (pre-seal max 8871 µs, post-seal max 7413 µs,
   separation peak 6605 µs at tick 493)
SMOKE_TEST_RESULT: FAIL - LAB-007 reproduces: ... still > 4 000 µs target
```

Separation peak dropped **13 883 → 6 605 µs (−52 %)** with the user's
exact operation timeline replayed. The remaining `max_step_usec` peak
is dominated by the obstacle-placement transient at tick 89 (replan
cost ~8.3 ms once `prewarm_static_context` invalidates the nav-map
cache) — see Approach item (7). Steady-state post-seal max settled at
~7.4 ms, well under the 16.7 ms frame budget but still above the
aspirational 4 ms.

The smoke is currently kept out of the `rtslab/smoke` group because
its threshold is the eventual target; rerun it manually with the
command above to track progress while items (6)–(7) are designed.

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
