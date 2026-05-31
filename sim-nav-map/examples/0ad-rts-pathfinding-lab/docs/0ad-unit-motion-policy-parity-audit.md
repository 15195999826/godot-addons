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

The controller now exposes a lab-only experiment toggle:

- `0ad_skip_blocked_waypoint`
- `lab_keep_blocked_waypoint` (current default)

0 A.D. baseline does the opposite for multi-waypoint long paths: it pops the
current waypoint and short-paths toward the following waypoint. That rule is in
`docs/references/0ad-source/source/simulation2/components/CCmpUnitMotion.h`,
inside `PostMove()`.

Treat the current lab behavior as a guard while the parity mismatch is audited,
not as the final policy.

### 2026-05-11: `_push_max_distance` same-control-group short-circuit (RESOLVED)

Resolved 2026-05-11 by removing the lab-only short-circuit. Locked in by
`_test_arrived_same_formation_separation_push_rate` in
`tests/smoke/smoke_zero_ad_rts_lab_motion.gd`. Full smoke 40/40.

Source observation. lab `zero_ad_rts_lab_motion_controller.gd:_push_max_distance`
short-circuits to `combined_radius` when both pair members share a
control group:

```gdscript
if same_control_group:
    return combined_radius   # 22 for two unit-radius-11 entities
```

This is a deviation from 0 A.D. `CCmpUnitMotionManager::Push()`, which
computes `maxDist = combinedClearance * PUSHING_RADIUS_MULTIPLIER +
extension` independent of control group. The 0 A.D. same-control-group
exception only changes `movingPush` (forces it to 0 so moving + idle
formation members still push). This audit's own notes already say
"same-group members are treated like a stopped-stopped pair for push
purposes" — but a stopped-stopped pair still uses the standard
`max_distance ≈ 27.6`, not `combined_radius = 22`.

Visible failure (log
`zero_ad_rts_lab_2026-05-11T01-48-26_tick_4234.json`): six formation
members all arrive, settle in pairs at distance 19-22 px (overlap
0-3 px), and the same-control-group `max_distance = 22` rule yields
`distance_factor ≈ 0.31` and a per-tick push amount `~0.25 px`. With
multiple neighbors pushing in different directions the vector sum
falls near zero, so units stay in the overlapping configuration.

Removing the short-circuit makes the same scenario use
`max_distance ≈ 27.6` and `distance_factor ≈ 0.76` → push amount
`~0.61 px/tick` → 2-3 ticks separates a 2-3 px overlap.

The same fix also resolves the related "stopped formation member
silently dampens a still-moving teammate" pattern: the moving unit was
within same-group `max_distance = 22` of a stopped teammate, push
pressure built up, speed got dampened. With `max_distance ≈ 27.6`
push range is wider, but pressure direction is symmetric so the
asymmetric-pressure rule (`docs/custom-features/asymmetric-push-pressure.md`)
already covers leader-vs-chaser pressure routing.

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

## Parity Experiment Result

Status: partial parity experiment complete; do not restore the 0 A.D. skip rule
yet.

The motion decision log now records the `long_segment_unit_line_blocked`
takeover context:

- `blocked_waypoint`
- `skipped_waypoint`
- `takeover_policy`
- `skipped_blocked_waypoint`
- `requested_short_path_goal`

The matching `short_path_result` also carries the request context plus:

- `first_consumed_short_waypoint`
- `short_path_length`
- `first_short_waypoint_farther_from_final_goal`
- `current_final_goal_distance`
- `first_short_waypoint_final_goal_distance`

The logged tick-3665 replay must include the local idle-unit cluster from the
export. A reduced replay with only `blue_3` does not reproduce the bad skip
path; the bad route depends on the nearby dynamic unit geometry around
`blue_0` / `blue_1` / `blue_2` / `blue_3` / `blue_4`.

Under `0ad_skip_blocked_waypoint`, the lab reproduces the old policy shape:
`blocked_waypoint = (605.0, 202.5)` is popped and the requested short-path goal
becomes `skipped_waypoint = (639.0, 241.25)`. In the exported scene geometry,
that short-path result begins with a waypoint that moves farther away from the
final goal before recovering, matching the observed large detour.

Under `lab_keep_blocked_waypoint`, the requested short-path goal stays at the
blocked immediate waypoint and the long path keeps that waypoint. This remains
the better lab behavior for the logged case, but it is still a documented
temporary deviation from 0 A.D.

Current conclusion:

- Keep `lab_keep_blocked_waypoint` as the default for now.
- Do not tune cooldown, search range, speed, or collision radius to hide this.
- Do not treat async / threading as the first fix.
- Before restoring 0 A.D. skip parity, fix the mismatch that makes the local
  short path accept a retreating first waypoint for this subgoal. The most
  likely next checks are short-path unit obstacle geometry, filter semantics,
  `PostMove()`-style timing, and whether subgoal short paths need a bounded
  equivalent to the 0 A.D. path-quality rejection/hack.

## Current Guard

The current smoke regression is:

```text
tests/smoke/smoke_zero_ad_rts_lab_motion.gd
_test_logged_long_segment_short_takeover_keeps_immediate_subgoal()
_test_logged_long_segment_policy_diagnostics_compare_skip_and_keep()
```

The first test proves the logged detour no longer occurs under the current lab
policy. The second compares both takeover policies against the export-derived
local unit cluster and proves the current 0 A.D.-style skip still exposes the
detour-risk diagnostics. Neither test means full 0 A.D. parity is complete.
