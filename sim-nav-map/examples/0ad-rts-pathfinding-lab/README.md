# 0AD RTS Pathfinding Lab

This lab is the active 0 A.D.-style movement-policy example for `sim-nav-map`.

The boundary is intentional:

- `sim-nav-map` core answers navigation questions: long path, short path,
  movement-line validation, unit-line validation, filters, and diagnostics.
- This example decides movement policy and order semantics: `UnitActor` owns the
  current move order, `MotionController` handles path following/recovery and
  emits motion updates, and `World` dispatches those updates on the simulation
  tick.

## 0 A.D.-Style Motion Contract

The baseline keeps the policy small, but mirrors the important 0 A.D. motion
gates:

- Candidate displacement is validated before a unit position changes.
- Path requests are owned by the unit as a single expected request: a new long
  request cancels a pending short request, and a new short request cancels a
  pending long request.
- A blocked movement increments a failed-movement counter, widens local short
  path search with repeated failures, occasionally alternates back to long
  pathfinding, and eventually records an explicit move failure instead of
  growing requests forever.
- While following a long path, unit-line validation can trigger a short-path
  request before the unit hits a dynamic blocker. 0 A.D. normally pops the
  current waypoint and short-paths toward the next waypoint neighborhood; the
  lab currently keeps the immediate waypoint for one logged detour case while
  the parity mismatch is audited.
- Known-imperfect paths are followed for a short countdown before another
  update is allowed.
- Push adjustment is applied only when the pushed segment is movement-line
  valid. Invalid push is discarded and marks the unit obstructed.
- There is no static obstacle escape, teleport settle, or post-move push-out
  fallback.

## 0 A.D.-Style Performance Policy

- Move orders enqueue long-path requests instead of computing all paths in the
  command frame.
- `ZeroAdRtsLabWorld.step()` processes only a small fixed path budget per tick.
- Blocked movement can enqueue local short-path requests, but results are still
  applied from the same budgeted queue.
- Suppressed repaths, stale request cancellation, move failures, and
  known-imperfect path cooldowns are exposed in metrics and export logs.
- Push adjustment uses a spatial bucket around each unit instead of scanning all
  unit pairs globally.

## Files

```text
docs/steady-state-frame-performance-plan.md
docs/0ad-unit-motion-policy-parity-audit.md
docs/archive/2026-05-09-short-path-visibility-optimization.md
logic/zero_ad_rts_lab_world.gd
logic/zero_ad_rts_lab_motion_controller.gd
logic/zero_ad_rts_lab_move_order.gd
logic/zero_ad_rts_lab_motion_update.gd
logic/zero_ad_rts_lab_pathfinder.gd
logic/zero_ad_rts_lab_unit.gd
logic/zero_ad_rts_lab_obstacle.gd
frontend/zero_ad_rts_pathfinding_lab.tscn
tests/smoke/smoke_zero_ad_rts_lab_motion.tscn
tests/smoke/smoke_zero_ad_rts_lab_ui_ops.tscn
tests/smoke/smoke_zero_ad_rts_lab_0ad_budget.tscn
tests/exploration/exploration_playthrough.tscn
```

## Controls

The frontend interaction model:

- `1`: command mode. Left-click selects, drag selects, right-click moves the
  current selection. If nothing is selected, right-click moves all mobile units.
- `2`: place static obstacle.
- `3`: place non-mobile blocker unit.
- `4`: erase the nearest editable obstacle or blocker.
- `A`: select all mobile units.
- `C`: clear traces.
- `R`: reset the scene.
- `Space`: pause/resume simulation.
- `Export log`: write a JSON debug snapshot to `user://zero_ad_rts_pathfinding_lab_logs/`.

## Smoke

```powershell
./tools/run_tests.ps1 zeroadlab/smoke
```
