extends Node

# CORE-015: Motion's per-frame candidate LOS check accumulates pass-through.
# When a path waypoint lies inside an obstacle's collision ring, the
# EDGE_EXPAND_DELTA tolerance in the boundary band means each tiny per-frame
# step never blocks (single-step b_dist drift < tolerance), and the unit
# walks straight through the obstacle over many ticks.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 9780+, log 2026-05-10T19-54-25.
#   - blue_2 at (470.32, 164.96) walking toward waypoint (475, 179).
#   - waypoint distance to blue_3 (492, 185) = 18.03 — well inside blue_3's
#     22-unit collision ring (waypoint itself is unreachable in principle).
#   - Per-frame motion candidate is ~0.6 px toward (475, 179) (slowed by push
#     pressure). Each candidate's distance to blue_3 drops only ~0.5 px from
#     the previous, staying within the boundary-band tolerance and unblocking.
#   - Over ~100 frames, blue_2 walks straight through blue_3's center
#     (recorded contact distance bottomed at 8.10 px, 14 px deep in the ring).
#
# Root cause: motion validated `validate_movement_line(start, candidate)`
# where `candidate` was the per-frame ~0.6 px sub-step. The tolerance was
# meant to absorb single-frame tangent noise, but cumulative sub-steps slipped
# past it.
#
# 0 A.D. expected (CCmpUnitMotion.h:1334):
#   `cmpPathfinder->CheckMovement(pos, target=waypoint, ...)` — validates
#   the segment from current position to the WAYPOINT, not to the per-frame
#   candidate. A waypoint inside an obstacle is rejected immediately.
#
# Fix (zero_ad_rts_lab_motion_controller.gd _perform_move): validation_target
# changed from per-frame `candidate` to the path's `waypoint`. Each frame
# revalidates the full remaining segment to the waypoint; if the waypoint
# is fundamentally unreachable (inside obstacle), motion blocks on tick 1
# instead of accumulating across 100 ticks.
#
# This repro is **multi-tick**: it runs ZeroAdRtsLabWorld.step() for 120
# frames and asserts the moving unit never enters the blocker's real
# collision ring. Single-step LOS assertions catch the necessary condition
# (LOS rejects waypoint-inside-obstacle) but miss the sufficient one
# (cumulative motion across many frames does not pierce). The original bug
# was specifically about cumulative drift, so multi-tick is the right shape.
#
# Before fix: blue_2 walks 100+ ticks toward (475, 179), passing within
# 8.10 px of blue_3's center (14 px deep into 22-px collision ring). FAIL.
# After fix: blue_2 stops well outside blue_3's ring; min_dist_to_blocker
# stays >= the real collision threshold across all frames. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_015_motion_validates_full_segment_to_waypoint.tscn


const TICK_COUNT := 120
const DELTA := 1.0 / 60.0
const COLLISION_THRESHOLD := 22.0  # blue_2.radius (11) + blue_3.clearance (11)
# Allow a tiny epsilon below collision_threshold to absorb LOS edge cases.
# The pre-fix bug saw distances drop to ~8 px, 14 px below the threshold —
# that's the regression we're guarding against.
const MIN_ALLOWED_DIST := 21.0


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-015 motion validates full segment (multi-tick, no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-015 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := ZeroAdRtsLabWorld.new()
	# Override default-spawned positions to the logged failure scenario.
	# Using two unit ids that already exist in the default world setup avoids
	# fighting with World's internal collections.
	var actor := world.get_unit("blue_2")
	var blocker := world.get_unit("blue_3")
	if actor == null or blocker == null:
		_failures.append("setup: missing blue_2 / blue_3 in default world")
		return
	actor.position = Vector2(470.32, 164.96)
	blocker.position = Vector2(492.0, 185.0)
	# Park the rest of the squad far away so they don't interfere with the
	# 1v1 geometry under test.
	for other_id in ["blue_0", "blue_1", "blue_4", "blue_5"]:
		var other := world.get_unit(other_id)
		if other != null:
			other.position = Vector2(50.0 + float(other.id.hash() % 200), 380.0)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)

	# Order blue_2 to walk to (475, 179). This target sits 18.03 px from
	# blue_3 — *inside* blue_3's collision ring — so the move is fundamentally
	# unreachable. The motion fix should keep blue_2 outside blue_3's ring
	# regardless.
	world.set_units_target(["blue_2"], Vector2(475.0, 179.0))

	var min_dist_to_blocker := actor.position.distance_to(blocker.position)
	var min_dist_tick := -1
	for i in range(TICK_COUNT):
		world.step(DELTA)
		var d := actor.position.distance_to(blocker.position)
		if d < min_dist_to_blocker:
			min_dist_to_blocker = d
			min_dist_tick = i

	if min_dist_to_blocker < MIN_ALLOWED_DIST:
		_failures.append(
			"actor pierced blocker collision ring: min_dist=%.2f at tick %d (collision_threshold=%.1f, allowed=%.1f). Pre-fix value was ~8 px."
			% [min_dist_to_blocker, min_dist_tick, COLLISION_THRESHOLD, MIN_ALLOWED_DIST]
		)


func _path_to_array(path: SimNavWaypointPath) -> Array:
	var out: Array = []
	if path == null:
		return out
	for wp in path.waypoints:
		out.append("(%.1f, %.1f)" % [wp.x, wp.y])
	return out
