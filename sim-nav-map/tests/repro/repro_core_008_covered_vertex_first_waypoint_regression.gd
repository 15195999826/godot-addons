extends Node

# CORE-008: Vertex pathfinder picks regressive first waypoint when an
# obstacle corner is covered by a neighbor's collision ring.
#
# Repro from 0ad-rts-pathfinding-lab tick 7352 (log 2026-05-10T18-33-11):
#   - blue_4 at (489.94, 219.03), goal (392, 120) (NW direction).
#   - Stationary blue_3 at (488, 197) and blue_0 at (529, 228) block the
#     direct line and many candidate edges.
#   - Before fix: vertex graph keeps blue_3.SE corner (510.5, 219.5) as a
#     candidate even though it sits inside blue_0's 22-unit collision ring
#     (target_dist 20.36 < 22). Every edge into it gets rejected by LOS,
#     so A* falls back to blue_0.SW (506.5, 250.5) — first wp is 34 px
#     farther from the final goal (173 vs 139). Unit visibly walks SE
#     before heading NW.
#   - After fix (sim_nav_vertex_pathfinder.gd _vertex_covered_by_obstacles,
#     mirrors 0 A.D. VertexPathfinder.cpp:727-734): covered corners are
#     filtered out of the vertex graph, A* reaches an uncovered corner
#     closer to the goal, first wp is no longer regressive.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_008_covered_vertex_first_waypoint_regression.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-008 covered vertex regression (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-008 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var cell_size := 16.0
	var map_w := int(ceil(720.0 / cell_size))
	var map_h := int(ceil(420.0 / cell_size))
	var nav_map := SimNavMap.new(map_w, map_h, cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 12.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)
	nav_map.rebuild_dirty()

	var blockers: Array[SimNavObstructionShapeUnit] = []
	blockers.append(_make_blocker("blue_3", Vector2(488.0, 197.0), 11.0))
	blockers.append(_make_blocker("blue_0", Vector2(529.0, 228.0), 11.0))
	var blocker_array: Array[SimNavObstructionShapeUnit] = []
	for b in blockers:
		blocker_array.append(b)
	nav_map.replace_dynamic_obstructions(blocker_array)

	var start := Vector2(489.94, 219.03)
	var goal_point := Vector2(392.0, 120.0)
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal_point)
	req.clearance = 11.0
	req.range_px = 12.0 * cell_size  # SHORT_PATH_MIN_SEARCH_RANGE
	req.pass_mask = pass_mask
	req.avoid_moving_units = false
	req.control_group = ""
	req.static_vertex_extra_outset = cell_size * 0.5

	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(req)
	if not result.is_success():
		_failures.append("expected success, got status=%s reason=%s" % [str(result.status), str(result.failure_reason)])
		return
	if result.path.is_empty():
		_failures.append("expected non-empty path")
		return

	var current_goal_distance := start.distance_to(goal_point)
	var first_consumed: Vector2 = result.path.back()
	var first_goal_distance := first_consumed.distance_to(goal_point)
	if first_goal_distance > current_goal_distance + 0.01:
		_failures.append(
			"first consumed waypoint %s is %.2f from goal, farther than start %.2f (regressive); full path=%s"
			% [str(first_consumed), first_goal_distance, current_goal_distance, str(_path_to_array(result.path))]
		)

	# Direct sanity: blue_3.SE corner (510.5, 219.5) lies inside blue_0's collision ring
	# (distance 20.36 < clearance 11 + buffer 11). After the filter A* must not
	# emit it as a path vertex.
	var covered_corner := Vector2(510.5, 219.5)
	for wp in result.path.waypoints:
		if wp.distance_to(covered_corner) < 0.5:
			_failures.append(
				"path retains covered vertex %s (should be filtered, dist to blue_0=%0.2f)"
				% [str(wp), wp.distance_to(Vector2(529.0, 228.0))]
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
