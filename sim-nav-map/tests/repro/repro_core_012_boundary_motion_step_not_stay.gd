extends Node

# CORE-012: Motion's small per-frame candidate step is wrongly classified as
# "stay/deeper" when start sits in the vertex-graph boundary band.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 3015, log 2026-05-10T19-24-28.
#   - blue_0 at (519.275, 216.328), goal (518, 329) (mostly south, ~113 px
#     away, no obstacle in the way visually).
#   - Stationary blue_3 at (497, 219) sits to the WNW. distance(blue_0, blue_3)
#     = 22.44 — boundary band (22 ≤ 22.44 ≤ 22.5).
#   - Motion's `_perform_move` builds a per-frame candidate ~1.6 px south
#     toward goal: ~ (519.26, 217.93). distance(candidate, blue_3) = 22.29 —
#     0.15 px CLOSER to blue_3 than start, but still 0.29 px outside the real
#     collision ring (22).
#   - Before fix: boundary-band branch checked `target_dist <= start_dist`
#     and treated this as stay/deeper → blocked. Every frame's tiny step gets
#     rejected → blocked_recovery → max_failed_movements → stuck despite an
#     obviously open route south.
#
# 0 A.D. expected (Geometry.cpp:259-305 TestRaySquare):
#   The "a inside, b outside / b inside" rule applies only when 'a' is
#   genuinely inside the obstacle. When 'a' is outside (boundary band is still
#   outside the real collision ring), the standard outside check governs:
#   block iff segment pierces the obstacle. A target merely 0.15 px closer
#   than start, but still outside, is not piercing.
#
# Fix (sim_nav_line_of_sight.gd _unit_shape_blocks_segment): boundary-band
# branch no longer compares target_dist to start_dist. It uses the same check
# as the outside branch (target inside collision ring → block; otherwise
# segment-to-point < collision_threshold - EDGE_EXPAND_DELTA → block).
# Stay/deeper rule is reserved for the genuine-overlap branch
# (`start_dist < collision_threshold`).
#
# Before fix: short forward step from boundary position blocked. FAIL.
# After fix: forward step accepted; unit progresses south. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_012_boundary_motion_step_not_stay.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-012 boundary motion step (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-012 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	# Direct LOS unit-test: short forward step from boundary position.
	var start := Vector2(519.275329589844, 216.327850341797)
	var candidate := Vector2(519.260, 217.928)  # ~1.6 px south, mid-step
	var blue_3 := SimNavObstructionShapeUnit.new()
	blue_3.entity_id = "blue_3"
	blue_3.center = Vector2(497.0, 219.0)
	blue_3.clearance = 11.0
	blue_3.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blue_3.moving = false

	var blocked := SimNavLineOfSight.shape_blocks_segment(start, candidate, blue_3, 11.0)
	if blocked:
		_failures.append(
			"forward step %s->%s wrongly blocked; start_dist=%.2f cand_dist=%.2f, both > collision_threshold 22"
			% [str(start), str(candidate), start.distance_to(blue_3.center), candidate.distance_to(blue_3.center)]
		)

	# Negative direction: a step that *enters* the collision ring must still block.
	var pierce := Vector2(508.0, 219.0)  # 11 px from blue_3 center — well inside collision ring
	var pierce_blocked := SimNavLineOfSight.shape_blocks_segment(start, pierce, blue_3, 11.0)
	if not pierce_blocked:
		_failures.append("piercing step %s->%s wrongly accepted (target inside collision ring)" % [str(start), str(pierce)])

	# 0 A.D. Geometry.cpp:280-281 TestRaySquare is binary: `a inside → return
	# false`. The lab's earlier stay-or-deeper guard violated this and stranded
	# units in real overlap (CORE-014 found the symptom: motion candidate
	# tangent geometry briefly heading inward got blocked every frame). The
	# correct behaviour is escape-allowed regardless of b's position; push
	# system + blocked recovery separate units across frames.
	var inside_a := Vector2(486.0, 219.0)  # 11 px from blue_3 center
	var inside_b := Vector2(497.0, 219.0)  # blue_3 center itself
	var stay_blocked := SimNavLineOfSight.shape_blocks_segment(inside_a, inside_b, blue_3, 11.0)
	if stay_blocked:
		_failures.append("stay-deeper from genuine overlap %s->%s should NOT block (0 A.D. binary inside rule)" % [str(inside_a), str(inside_b)])


func _path_to_array(path: SimNavWaypointPath) -> Array:
	var out: Array = []
	for wp in path.waypoints:
		out.append("(%.1f, %.1f)" % [wp.x, wp.y])
	return out
