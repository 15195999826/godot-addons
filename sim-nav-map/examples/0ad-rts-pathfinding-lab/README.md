# 0AD RTS Pathfinding Lab

This lab is a clean 0 A.D.-style movement-policy example for `sim-nav-map`.
It does not reuse the older `rts-pathfinding-lab` movement loop.

The boundary is intentional:

- `sim-nav-map` core answers navigation questions: long path, short path,
  movement-line validation, unit-line validation, filters, and diagnostics.
- This example decides movement policy: waypoint consumption, blocked movement
  handling, short-path retry, push adjustment, and arrival state.

## 0 A.D.-Style Motion Contract

The first baseline keeps the policy small:

- Candidate displacement is validated before a unit position changes.
- A blocked movement increments a failed-movement counter and requests a local
  short path.
- While following a long path, unit-line validation can trigger a short-path
  request before the unit hits a dynamic blocker.
- Push adjustment is applied only when the pushed segment is movement-line
  valid. Invalid push is discarded and marks the unit obstructed.
- There is no static obstacle escape, teleport settle, or post-move push-out
  fallback.

## Files

```text
logic/zero_ad_rts_lab_world.gd
logic/zero_ad_rts_lab_motion_controller.gd
logic/zero_ad_rts_lab_pathfinder.gd
logic/zero_ad_rts_lab_unit.gd
logic/zero_ad_rts_lab_obstacle.gd
frontend/zero_ad_rts_pathfinding_lab.tscn
tests/smoke/smoke_zero_ad_rts_lab_motion.tscn
```

## Smoke

```powershell
./tools/run_tests.ps1 zeroadlab/smoke
```

