extends Node

# CORE-010: Start exactly on collision boundary causes A* to detour around the
# whole obstacle when the natural escape direction is tangent.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 8703, log 2026-05-10T19-03-59.
#   - blue_1 at (481.89, 127.23), goal (473, 92) (near, ~36 px NW), and a
#     stationary blue_0 at (460, 125). distance(blue_1, blue_0) = 22.0 — exactly
#     on the collision_threshold boundary (clearance 11 + buffer 11).
#   - Going to blue_0.NE corner (482.5, 102.5) is the natural escape direction.
#     The segment is mostly N, dot to blue_0 → t clamped to 0, segment-to-point
#     ≈ 21.94 (just 0.06 px below the 22 threshold from numerical noise).
#   - Before fix (`< collision_threshold` strict): 21.94 < 22 → BLOCK. A*
#     forced to detour: start → blue_0.SE (482.5, 147.5) (south +20 px) →
#     blue_0.NE → goal. Visually the unit recoils south just before reaching.
#
# 0 A.D. expected (Geometry.cpp:259-305 TestRaySquare):
#   `'a' inside, 'b' outside -> no collision`. 0 A.D.'s ray-square test is
#   geometric and tolerates numeric edge cases. lab's circle approximation
#   needs an explicit small tolerance for tangent paths in the boundary band
#   (collision_threshold .. collision_threshold + EDGE_EXPAND_DELTA).
#
# Fix (sim_nav_line_of_sight.gd _unit_shape_blocks_segment): split into three
# bands.
#   - start_dist < collision_threshold: genuine overlap, binary escape.
#   - collision_threshold <= start_dist <= inside_threshold: boundary band, use
#     `< collision_threshold - EDGE_EXPAND_DELTA` (0.5 px tolerance).
#   - start_dist > inside_threshold: standard collision check.
#
# Before fix: short path's first consumed waypoint is blue_0.SE corner
# (482.5, 147.5), 20.27 px farther from goal than start. FAIL.
# After fix: short path goes directly to blue_0.NE / goal area without the
# southward detour. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_010_boundary_tangent_no_detour.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-010 boundary tangent regression (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-010 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	# Direct LOS unit-test: tangent escape segment must not be blocked.
	var a := Vector2(481.89, 127.23)
	var b := Vector2(482.5, 102.5)
	var blue_0 := SimNavObstructionShapeUnit.new()
	blue_0.entity_id = "blue_0"
	blue_0.center = Vector2(460.0, 125.0)
	blue_0.clearance = 11.0
	blue_0.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blue_0.moving = false

	var blocked := SimNavLineOfSight.shape_blocks_segment(a, b, blue_0, 11.0)
	if blocked:
		_failures.append(
			"tangent escape segment %s->%s wrongly blocked (mid-dist 21.94 vs threshold 22, within EDGE_EXPAND_DELTA noise)"
			% [str(a), str(b)]
		)

	# Negative direction: a piercing segment in the same band must still block.
	var pierce_target := Vector2(437.5, 102.5)  # blue_0.NW corner — segment goes WNW through blue_0 center
	var pierce_blocked := SimNavLineOfSight.shape_blocks_segment(a, pierce_target, blue_0, 11.0)
	if not pierce_blocked:
		_failures.append(
			"piercing segment %s->%s wrongly accepted; tolerance must not let real piercing through"
			% [str(a), str(pierce_target)]
		)

	# Full short-path repro: first consumed waypoint must not detour south.
	_test_short_path_first_wp_not_south()


func _test_short_path_first_wp_not_south() -> void:
	var cell_size := 16.0
	var nav_map := SimNavMap.new(int(ceil(720.0 / cell_size)), int(ceil(420.0 / cell_size)), cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 12.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)
	nav_map.rebuild_dirty()

	var blockers: Array[SimNavObstructionShapeUnit] = []
	blockers.append(_make_blocker("blue_0", Vector2(460.0, 125.0), 11.0))
	nav_map.replace_dynamic_obstructions(blockers)

	var start := Vector2(481.89, 127.23)
	var goal_point := Vector2(473.0, 92.0)
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal_point)
	req.clearance = 11.0
	req.range_px = 12.0 * cell_size
	req.pass_mask = pass_mask
	req.avoid_moving_units = false
	req.control_group = ""
	req.static_vertex_extra_outset = cell_size * 0.5

	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(req)
	if not result.is_success() or result.path.is_empty():
		_failures.append("expected success path; got status=%s reason=%s" % [str(result.status), str(result.failure_reason)])
		return

	var first_consumed: Vector2 = result.path.back()
	# The detour bug picks (482.5, 147.5) — south of the start by 20 px.
	# After fix, first consumed waypoint should be at most ~start.y (no south
	# detour past start.y by more than the unit radius).
	if first_consumed.y > start.y + 11.0:
		_failures.append(
			"first consumed waypoint %s detours south of start.y=%.2f; full path=%s"
			% [str(first_consumed), start.y, str(_path_to_array(result.path))]
		)


func _make_blocker(id: String, pos: Vector2, radius: float) -> SimNavObstructionShapeUnit:
	var shape := SimNavObstructionShapeUnit.new()
	shape.entity_id = id
	shape.center = pos
	shape.clearance = radius
	shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	shape.moving = false
	return shape


func _path_to_array(path: SimNavWaypointPath) -> Array:
	var out: Array = []
	for wp in path.waypoints:
		out.append("(%.1f, %.1f)" % [wp.x, wp.y])
	return out
