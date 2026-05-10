extends Node

# CORE-001: VertexPathfinder OBB vertex outset wrong direction
#
# Bug reproduced here:
#   - For a non-square static OBB, sim_nav_vertex_pathfinder.gd:107-111 expands each
#     body corner along the corner-to-center radial by `clearance * 2.0`.
#   - The resulting expanded corners are NOT on an axis-aligned (in OBB frame)
#     clearance ring — over-expanded along OBB diagonal, under-expanded along OBB axes.
#
# 0 A.D. expected (VertexPathfinder.cpp:636-685):
#     corner = center ± (hw + c) · u ± (hh + c) · v   where u, v are OBB axes.
#
# Repro: place a 80×16 OBB at four rotations. Plan a short path from one side to
# the other. For each emitted intermediate waypoint, expect it sits within 1.0
# units of one of the four axis-aligned expanded corners.
#
# At HEAD: at least one waypoint per rotation is several units off. FAIL.
# After fix: all waypoints land on the expected axis-aligned ring. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_001_vertex_obb_outset.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-001 vertex obb outset (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-001 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	for rot_deg in [0.0, 30.0, 45.0, 90.0]:
		_test_rotation(rot_deg)


func _test_rotation(rot_deg: float) -> void:
	var nav_map := SimNavMap.new(64, 64, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	var clearance := 8.0
	var obb_w := 80.0
	var obb_h := 16.0
	var obb_center := Vector2(256.0, 256.0)
	var rot_rad := deg_to_rad(rot_deg)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "wall"
	blocker.center = obb_center
	blocker.width = obb_w
	blocker.height = obb_h
	blocker.rotation_rad = rot_rad
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)

	var req := SimNavShortPathRequest.new()
	req.start = Vector2(64.0, 256.0)
	req.goal = SimNavPathGoal.point(Vector2(448.0, 256.0))
	req.clearance = clearance
	req.range_px = 600.0
	req.pass_mask = pass_mask
	req.avoid_moving_units = true

	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	if path.is_empty():
		_failures.append("rot=%.0f°: short path is empty (no route around OBB)" % rot_deg)
		return

	var u := Vector2(cos(rot_rad), sin(rot_rad))
	var v := Vector2(-sin(rot_rad), cos(rot_rad))
	var hw_ext := obb_w * 0.5 + clearance
	var hh_ext := obb_h * 0.5 + clearance
	var expected_corners: Array[Vector2] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			expected_corners.append(obb_center + sx * hw_ext * u + sy * hh_ext * v)

	var goal_pos: Vector2 = req.goal.center
	var tolerance := 1.0
	for wp in path.waypoints:
		if wp.distance_to(goal_pos) < tolerance:
			continue
		var min_distance := INF
		for expected in expected_corners:
			var d := wp.distance_to(expected)
			if d < min_distance:
				min_distance = d
		if min_distance > tolerance:
			_failures.append(
				"rot=%.0f°: waypoint %s is %.2f away from nearest axis-aligned expanded corner (tolerance %.1f)"
				% [rot_deg, str(wp), min_distance, tolerance]
			)
