extends Node

# CORE-013: Boundary-band branch's `target_dist <= collision_threshold`
# early-return wrongly blocks a small forward step whose tail dips just
# inside the collision ring while the segment overall heads away from the
# obstacle.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 3397, log 2026-05-10T19-28-45.
#   - blue_1 at (512.13, 190.64), goal (543, 60). Stationary blue_2 at
#     (508, 169) sits to the WNW.
#   - distance(blue_1, blue_2) = 22.03 (boundary band: 22 ≤ 22.03 ≤ 22.5).
#   - Short path picked blue_2's SW corner (485.5, 191.5) as first waypoint
#     (a sane detour west). Motion's per-frame candidate is ~1.6 px toward
#     that corner: ~ (510.53, 190.69). distance(candidate, blue_2) = 21.84
#     — 0.19 px inside collision ring (22), even though the segment's
#     midpoint is 21.76 (well outside the tolerance band) and the destination
#     SW corner sits at distance 31.82 (clearly outside).
#   - Before fix: boundary branch's `if target_dist <= collision_threshold:
#     return true` early-returned on the candidate's 21.84, blocking every
#     per-frame step → max_failed_movements → stuck.
#
# 0 A.D. expected (Geometry.cpp:259-305, CCmpObstructionManager.cpp:912-915):
#   TestRaySquare/TestRayAASquare check whether the ray goes from outside to
#   inside (entering the obstacle), not "does the endpoint sit inside". A
#   short outward segment whose tail briefly dips into the swept clearance
#   while moving past it is acceptable — the geometry test cares about ray
#   crossing, not endpoint containment.
#
# Fix (sim_nav_line_of_sight.gd _unit_shape_blocks_segment): in the boundary
# band branch, drop the `target_dist <= collision_threshold` early-return.
# The single segment-to-point check below already covers genuine "b deep
# inside" cases (t clamps to 1, sep collapses to target_dist) but does not
# trigger on a 0.2 px tail dip when start_to_point distance is essentially
# the same as collision_threshold.
#
# Before fix: forward step from (512.13, 190.64) to candidate (510.53, 190.69)
# blocked because target_dist 21.84 < collision_threshold 22. FAIL.
# After fix: step accepted; unit makes progress west toward SW corner. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_013_boundary_step_b_inside_no_early_block.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-013 boundary step b-inside (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-013 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var blue_2 := SimNavObstructionShapeUnit.new()
	blue_2.entity_id = "blue_2"
	blue_2.center = Vector2(508.0, 169.0)
	blue_2.clearance = 11.0
	blue_2.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blue_2.moving = false

	# Forward step from boundary position toward SW corner (485.5, 191.5).
	var start := Vector2(512.132629394531, 190.638610839844)
	var candidate := Vector2(510.530, 190.690)  # ~1.6 px toward SW corner
	var blocked := SimNavLineOfSight.shape_blocks_segment(start, candidate, blue_2, 11.0)
	if blocked:
		var sd := start.distance_to(blue_2.center)
		var td := candidate.distance_to(blue_2.center)
		_failures.append(
			"forward step %s->%s wrongly blocked; start_dist=%.2f cand_dist=%.2f (cand 0.16 px inside ring is irrelevant — segment heads away overall)"
			% [str(start), str(candidate), sd, td]
		)

	# Full segment to the SW corner must also be unblocked.
	var sw_corner := Vector2(485.5, 191.5)
	var full_blocked := SimNavLineOfSight.shape_blocks_segment(start, sw_corner, blue_2, 11.0)
	if full_blocked:
		_failures.append("full segment %s->%s wrongly blocked (sw_corner sits at distance 31.82 from blue_2)" % [str(start), str(sw_corner)])

	# Negative direction: a step that drives DEEP into blue_2 (target near
	# center) must still block. The single segment-to-point check has to
	# catch this case without the early-return.
	var deep_target := Vector2(508.0, 175.0)  # 6 px from blue_2 center
	var deep_blocked := SimNavLineOfSight.shape_blocks_segment(start, deep_target, blue_2, 11.0)
	if not deep_blocked:
		_failures.append("deep step %s->%s wrongly accepted; target sits 6 px from blue_2 center" % [str(start), str(deep_target)])

	# Negative direction: a static-target piercing segment must still block.
	var pierce := Vector2(497.0, 169.0)  # 11 px west of blue_2 center
	var pierce_blocked := SimNavLineOfSight.shape_blocks_segment(start, pierce, blue_2, 11.0)
	if not pierce_blocked:
		_failures.append("piercing step %s->%s wrongly accepted (target at edge of collision ring)" % [str(start), str(pierce)])
