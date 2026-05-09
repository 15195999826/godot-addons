# 0 A.D. UnitMotion Policy Parity Audit

Date: 2026-05-09

This audit was opened after export:

```text
C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/zero_ad_rts_pathfinding_lab_logs/zero_ad_rts_lab_2026-05-09T20-19-32_tick_4776.json
```

The observed issue was not a long-path failure. The long path was usable, but
short-path takeover around a dynamic blocker produced a large detour.

## Current Status

The lab currently has a temporary deviation in
`logic/zero_ad_rts_lab_motion_controller.gd`.

When `long_segment_unit_line_blocked` fires, the lab keeps the blocked immediate
long waypoint and short-paths back to that waypoint neighborhood. This prevents
the logged detour, but it is not 0 A.D. parity.

0 A.D. baseline does the opposite for multi-waypoint long paths: it pops the
current waypoint and short-paths toward the following waypoint. That rule is in
`docs/references/0ad-source/source/simulation2/components/CCmpUnitMotion.h`,
inside `PostMove()`.

Treat the current lab behavior as a guard while the parity mismatch is audited,
not as the final policy.

## 0 A.D. Baseline

### Path Selection

`ComputePathToGoal()` is the top-level route selection:

- Try a valid direct route first when not alternating pathfinder type.
- Use short path when the goal is within `LONG_PATH_MIN_DIST`.
- Otherwise request a long path.
- `ShouldAlternatePathfinder()` flips short/long choice after repeated movement
  failures.

`RequestLongPath()` sets goal `maxdist` to the short-path minimum search range
minus one. This controls long-path waypoint spacing.

`RequestShortPath()` carries clearance, search range, passability class,
`ShouldCollideWithMovingUnits()`, control group, and notify entity.

### Unit-Line Takeover

After movement, while following a long path, 0 A.D. checks `TestUnitLine()` from
the current position to the next long waypoint.

If unit-line is blocked:

- With more than one long waypoint left, pop the current waypoint and request a
  short path to a circle around the following waypoint.
- With only one long waypoint left, request a short path to the final goal.

The source comment says this is because the obstruction may be at the waypoint
and the end is treated specially.

### Obstructed Recovery

`HandleObstructedMove()` is a separate recovery path:

- Increment failed movement and eventually notify obstructed/failed.
- If the final goal is in short-path range, recompute to the goal.
- On repeated short-path trouble, add a small backup waypoint.
- If a long waypoint is close enough, pop it.
- Occasionally alternate back to long pathfinding.
- Otherwise request a short path to a circle near the next long waypoint.

### Path Results

`PathResult()` ignores obsolete tickets.

For goal-targeted paths, `RejectFartherPaths()` rejects a result whose first
consumed waypoint would take the unit farther from the goal. If a long path
fails or is rejected, 0 A.D. can insert a fake target waypoint so the short
pathfinder gets one more chance to recover.

Short paths to long-path subgoals are not considered goal-targeted when a long
path remains.

### Filters And Groups

0 A.D. uses movement filters consistently across path and line checks:

- Formation members use the formation controller as control group.
- Solo units use their own entity id as group.
- Entity targets can be skipped by obstruction tag.
- `ShouldCollideWithMovingUnits()` depends on pushing and block-movement state.
- `TestUnitLine()` checks only dynamic unit obstructions and can relax unit
  clearance slightly.

## Lab Parity Gaps

These gaps are likely more important than the single waypoint-pop line:

1. The current immediate-waypoint guard is a deliberate non-parity patch.
2. The lab checks long-segment unit-line in `step_unit()` before `_perform_move()`;
   0 A.D. performs movement first and runs the predictive unit-line check in
   `PostMove()`.
3. The lab hardcodes `avoid_moving_units = false` in short-path requests and
   movement filters. This is close to pushing-enabled 0 A.D. behavior, but the
   lab has no explicit `ShouldCollideWithMovingUnits()` contract.
4. The lab has no target obstruction tag skip.
5. The lab does not implement the 0 A.D. long-path short-path hack for rejected
   or empty long results.
6. The lab does not reject farther goal-targeted path results.
7. The lab long-path waypoint spacing is an adapter value
   (`cell_size * 4.0`), not the 0 A.D. `SHORT_PATH_MIN_SEARCH_RANGE - 1`
   maxdist rule.
8. The lab unit-line validation uses the current `sim-nav-map` line primitive,
   not the exact 0 A.D. `TestUnitLine()` AASquare logic with relaxed clearance.

## Next Decision

Do not continue tuning cooldown, collision radius, motion speed, search range,
or async scheduling to hide this.

The next step should be a parity experiment:

1. Add diagnostics for `long_segment_unit_line_blocked` that records:
   `blocked_waypoint`, `skipped_waypoint`, requested short-path goal, first
   consumed short waypoint, short path length, and whether the first short
   waypoint moves farther from the final goal.
2. Run the logged scenario under two policies:
   `0ad_skip_blocked_waypoint` and `lab_keep_blocked_waypoint`.
3. If 0 A.D.-style skip still produces the large detour, fix the underlying
   mismatch before restoring parity. Candidate areas are unit-line timing,
   waypoint spacing, short-path unit obstacle geometry, and filter semantics.
4. If the lab intentionally keeps the immediate waypoint for better behavior,
   keep it documented as a lab policy deviation and keep the smoke regression
   that protects the logged case.

## Current Guard

The current smoke regression is:

```text
tests/smoke/smoke_zero_ad_rts_lab_motion.gd
_test_logged_long_segment_short_takeover_keeps_immediate_subgoal()
```

It proves the logged detour no longer occurs under the current lab policy. It
does not prove 0 A.D. parity.
