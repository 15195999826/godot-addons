extends Node

# CORE-016: Unit perpetually blocked at distance < ARRIVE_EPSILON from a target
# that fell inside a stationary unit's collision ring.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick ~10380-10400, log 2026-05-10T19-54-25.
#   - blue_2 ordered to (514, 192). blue_0 stationary at (534, 184).
#   - distance(target, blue_0) = 21.54 — INSIDE the 22-px collision ring.
#     The target is fundamentally unreachable.
#   - Motion's segment-to-waypoint LOS (CORE-015) correctly rejects every step
#     that would advance toward the target. Per-frame fm increments, eventually
#     hits MAX_FAILED_MOVEMENTS even though blue_2 is only 2.6 px from target.
#   - From the player's view: "the path is open and the unit is right there,
#     why is it stuck?".
#
# 0 A.D. expected (CCmpUnitMotion::PossiblyAtDestination semantics):
#   When a unit is within arrival tolerance of its move-order target, treat
#   the order as fulfilled regardless of whether the final-waypoint LOS still
#   technically blocks. Otherwise targets that fall inside a unit's clearance
#   ring (a common interactive case — player clicks near a stationary unit)
#   produce eternal blocked_recovery.
#
# Fix (zero_ad_rts_lab_motion_controller.gd step_unit obstructed branch): on
# obstructed move, if distance(unit.position, unit.path_target) <= ARRIVE_EPSILON,
# clear paths and emit REACHED_GOAL. The unit stops at its current position;
# the player sees "arrived close enough".
#
# Before fix: blue_2 stuck at (513.56, 194.57), distance 2.6 px to target,
# repeated long_segment_unit_line_blocked + short no_route until
# max_failed_movements. FAIL.
# After fix: blue_2 emits REACHED_GOAL, has_move_order cleared, no recovery
# loop. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_016_arrive_when_blocked_close_to_target.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-016 arrive when blocked close (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-016 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var lab_pf := ZeroAdRtsLabPathfinder.new(Vector2(720.0, 420.0), 16.0, 12.0)
	lab_pf.rebuild_context([])

	var blue_0 := ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(534.0, 184.0), 11.0, 96.0, true)
	blue_0.has_move_order = false

	var start := Vector2(513.556213378906, 194.573516845703)
	var target := Vector2(514.0, 192.0)
	var blue_2 := ZeroAdRtsLabUnit.new("blue_2", "blue", start, 11.0, 96.0, true)
	blue_2.has_move_order = true
	blue_2.target = target
	blue_2.path_target = target
	blue_2.long_path = SimNavWaypointPath.new()
	blue_2.long_path.push_back(target)

	var units: Array[ZeroAdRtsLabUnit] = [blue_2, blue_0]
	lab_pf.refresh_dynamic_units(units)

	var motion := ZeroAdRtsLabMotionController.new()
	# Step the controller. With the fix, the obstructed branch will detect
	# that we're already within ARRIVE_EPSILON of the target and emit
	# REACHED_GOAL instead of accruing failed_movements.
	motion.step_unit(blue_2, 1.0 / 60.0, lab_pf, units, 1)

	var updates := motion.drain_motion_updates()
	var reached := false
	for u in updates:
		var snap: Dictionary = u.to_snapshot()
		if String(snap.get("type", "")) == "reached_goal":
			reached = true
			break
	if not reached:
		var snaps: Array = []
		for u in updates:
			snaps.append(u.to_snapshot())
		_failures.append(
			"expected REACHED_GOAL motion update; updates=%s, blue_2 fm=%d, has_path=%s, distance_to_target=%.2f"
			% [str(snaps), blue_2.failed_movements, str(blue_2.has_path()), blue_2.position.distance_to(target)]
		)
	if blue_2.has_path():
		_failures.append("expected paths cleared after reach_goal; long=%d short=%d" % [blue_2.long_path.size(), blue_2.short_path.size()])

	# Negative direction: a unit that is FAR from the target and blocked must
	# still go through normal blocked recovery (not falsely arrive).
	var far_start := Vector2(450.0, 250.0)
	var far_unit := ZeroAdRtsLabUnit.new("far", "blue", far_start, 11.0, 96.0, true)
	far_unit.has_move_order = true
	far_unit.target = target
	far_unit.path_target = target
	far_unit.long_path = SimNavWaypointPath.new()
	far_unit.long_path.push_back(target)
	var far_units: Array[ZeroAdRtsLabUnit] = [far_unit, blue_0]
	lab_pf.refresh_dynamic_units(far_units)
	var motion2 := ZeroAdRtsLabMotionController.new()
	motion2.step_unit(far_unit, 1.0 / 60.0, lab_pf, far_units, 1)
	var updates2 := motion2.drain_motion_updates()
	for u in updates2:
		var snap: Dictionary = u.to_snapshot()
		if String(snap.get("type", "")) == "reached_goal":
			_failures.append("far unit (distance %.2f) wrongly emitted REACHED_GOAL" % far_start.distance_to(target))
			break
