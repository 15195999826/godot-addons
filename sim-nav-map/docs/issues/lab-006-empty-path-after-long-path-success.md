# LAB-006: Lab adapter drops waypoints — unit stuck despite long-path success

- Status: resolved
- Severity: P1
- Layer: lab
- Source: user-reproduced 2026-05-07 (export tick 817)
- Created: 2026-05-07
- Resolved: 2026-05-07

## Resolution

- submodule commit: `180908b`
- smoke: `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_006_grid_fallback_empty_path.tscn` (registered under `rtslab/smoke` group)
- 0 A.D. files checked: n/a (lab adapter bug; the failure is between core long-pathfinder output and lab-side `unit.path`, none in 0 A.D.'s C++)
- Fix: in `examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd::plan_path`, the smoothing-validation branch (`_path_respects_lab_bounds(start, smoothed, ...)` returns `false`) used to silently discard the path (`smoothed = []`), leaving the unit frozen with `has_move_order=true` and no replan trigger. It now falls back to the unsmoothed core long path (`long_path`), which `compute_path_result` already validated via navcell-center passability. The lab's continuous `segment_clear` is strictly stricter than navcell-center passability (it can flag the start→first-waypoint segment as marginal-clip), so re-running it on `long_path` here would just discard the only good fallback we have; the runtime push-out / collision pass corrects any incidental edge clipping along the navcell-center route.
- baseline impact: none (`BASELINE.md` "Known correctness limits" did not list LAB-006; lab/simnav metrics unchanged across the regression matrix).
- public-api.md: no change. The fix is internal to the lab adapter.

## Symptoms

User reproduced: select 6 mobile units, issue a first move command (group
moves east, all arrive). Issue a second move command back west — five
units replan and travel correctly; one unit (`blue_3`) sits at its old
end-of-first-leg position and never moves again.

Export log:
`C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/rts_pathfinding_lab_logs/rts_pathfinding_lab_2026-05-07T20-00-14_tick_817.json`

Frozen state for `blue_3` (current tick):

- `position = (581.87, 212.93)` (east edge, end of first leg)
- `target = path_target = (63.0, 226.0)` (second command, far west)
- `arrived = false`, `has_move_order = true`
- `path = []`, `path_index = 0`, `replan_timer = 0.32` (just replanned)

## Root cause (working hypothesis from log)

The most recent plan report for `blue_3` at tick 631 captures the bug:

```text
unit_id        blue_3
start          (581.87, 212.93)
target_after   (63.0, 226.0)
path_size      0                          ← path delivered to unit is empty
pathfinder_report.path_size                0
pathfinder_report.used_vertex              false
pathfinder_report.used_grid_fallback       true
pathfinder_report.skipped_vertex_reason    "crowded_edge_long_query"
pathfinder_report.long_path_result.status  "success"
pathfinder_report.long_path_result.refined_waypoint_count  3
pathfinder_report.long_path_result.path_length              536.65
```

The core long pathfinder returned `status=success` with a refined waypoint
path of size 3 (raw 34 navcells over 536.65 px, full route west around
the wall stack). The lab pathfinder adapter — which falls back to the
grid path when the vertex layer is skipped because of
`crowded_edge_long_query` — then delivers `path_size: 0` to the unit.
Somewhere between `pathfinder_report.long_path_result.refined_waypoint_path`
and the unit's `unit.path`, the waypoints are lost.

Without a path the unit sits with `has_move_order = true` and never
issues another replan within the export window, because
`replan_timer < REPLAN_INTERVAL` and the existing path-following logic
has no handler for "long-path succeeded but adapter handed me an empty
path".

Likely suspects:

1. The grid-fallback branch in
   `examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd`
   (`plan_path` and surrounding plumbing — see also CORE-008 audit
   tagging `crowded_edge_long_query`) discards the refined waypoint path
   when it cannot also produce a vertex short-path attachment.
2. Reverse-consumption ordering of `refined_waypoint_path` is being
   filtered into an empty list before being copied into `unit.path`.

## Proposed fix (to validate)

1. Read the lab pathfinder's grid-fallback path: confirm whether
   `long_path_result.refined_waypoint_path` is being copied to
   `unit.path` correctly when `used_vertex == false` and
   `used_grid_fallback == true`.
2. If a transformation is applied (e.g. last-segment vertex smoothing),
   ensure it preserves at least one waypoint when the source path is
   non-empty.
3. Add a smoke that reproduces the bug from the export-log scenario:
   - 6 mobile units, default obstacle map.
   - First command east (so units end at the east edge).
   - Wait for arrival.
   - Second command back west to `(63, 226)`.
   - Step until all units arrive OR `tick >= 800`.
   - Assert all 6 units' `arrived == true`.

## Verify before fixing

- [ ] Read `rts_pathfinding_lab_pathfinder.gd` `plan_path` and any
      grid-fallback branch
- [ ] Confirm that
      `pathfinder_report.long_path_result.refined_waypoint_path` is
      non-empty in the failing report (it should be, given
      `refined_waypoint_count = 3`)
- [ ] Decide whether `crowded_edge_long_query` skip should also bypass
      grid-fallback or coexist with it

## Repro at HEAD

No smoke yet (issue created from a user export-log replay). Smoke
deliverable is part of the fix per Branch B: replay the second-command
scenario, assert `arrived_count == 6` after a bounded number of ticks.

## Cross-refs

- CORE-008 — vertex pathfinder quadrant prune. The
  `skipped_vertex_reason = "crowded_edge_long_query"` tag points to the
  same call site.
- LAB-003 — also a lab-side stuck/teleport class of bug.
