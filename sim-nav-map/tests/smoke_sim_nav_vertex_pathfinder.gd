extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map vertex pathfinder")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_static_obb_corner_path()
	_test_dynamic_blocker_reroute()
	_test_blocked_navcell_terrain_edge_reroute()
	_test_circle_goal_lands_on_nearest_goal_point()
	_test_circle_goal_uses_alternate_boundary_candidate()
	_test_avoid_moving_units_false_allows_direct_path()
	_test_group_filter_allows_direct_path()


func _test_static_obb_corner_path() -> void:
	var nav_map := _base_map()
	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "stone"
	blocker.center = Vector2(50.0, 50.0)
	blocker.width = 20.0
	blocker.height = 30.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)

	var req := _request(Vector2(10.0, 50.0), Vector2(90.0, 50.0))
	var static_obstacles: Array = nav_map.get_static_obstruction_shapes()
	_assert_equal(1, static_obstacles.size(), "static OBB should be stored in nav map")
	_assert_false(
		SimNavLineOfSight.segment_clear(req.start, req.goal.center, static_obstacles, req.clearance),
		"static OBB should block direct line"
	)
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_true(path.size() >= 2, "static OBB should produce corner path")
	_assert_segments_clear(req.start, path, nav_map, req.clearance, "static OBB path")


func _test_dynamic_blocker_reroute() -> void:
	var nav_map := _base_map()
	var blocker := SimNavObstructionShapeUnit.new()
	blocker.entity_id = "red_blocker"
	blocker.center = Vector2(50.0, 50.0)
	blocker.clearance = 12.0
	blocker.flags = SimNavObstructionFlags.BLOCK_MOVEMENT | SimNavObstructionFlags.MOVING
	blocker.moving = true
	nav_map.add_dynamic_obstruction(blocker)

	var req := _request(Vector2(10.0, 50.0), Vector2(90.0, 50.0))
	var dynamic_obstacles: Array = nav_map.get_dynamic_obstruction_shapes()
	_assert_equal(1, dynamic_obstacles.size(), "dynamic blocker should be stored in nav map")
	_assert_false(
		SimNavLineOfSight.segment_clear(req.start, req.goal.center, dynamic_obstacles, req.clearance),
		"dynamic blocker should block direct line"
	)
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_true(path.size() >= 2, "dynamic blocker should produce reroute path")
	_assert_segments_clear(req.start, path, nav_map, req.clearance, "dynamic blocker path")


func _test_blocked_navcell_terrain_edge_reroute() -> void:
	var nav_map := _base_map()
	nav_map.or_navcell_data(Vector2i(6, 6), 1)
	var req := _request(Vector2(20.0, 52.0), Vector2(92.0, 52.0))
	req.clearance = 2.0
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_true(path.size() >= 2, "blocked navcell should produce terrain-edge reroute")
	_assert_path_waypoints_passable(path, nav_map, req.pass_mask, "terrain-edge path")


func _test_circle_goal_lands_on_nearest_goal_point() -> void:
	var nav_map := _base_map()
	var req := _request(Vector2(10.0, 50.0), Vector2(90.0, 50.0))
	req.goal = SimNavPathGoal.circle(Vector2(90.0, 50.0), 12.0)
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_equal(1, path.size(), "clear circle goal should produce direct short path")
	_assert_equal_vec(Vector2(78.0, 50.0), path.waypoints[0], "circle goal should land on nearest goal boundary")


func _test_circle_goal_uses_alternate_boundary_candidate() -> void:
	var nav_map := _base_map()
	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "goal_edge_blocker"
	blocker.center = Vector2(78.0, 50.0)
	blocker.width = 8.0
	blocker.height = 20.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)
	var req := _request(Vector2(10.0, 50.0), Vector2(90.0, 50.0))
	req.goal = SimNavPathGoal.circle(Vector2(90.0, 50.0), 12.0)
	req.clearance = 2.0
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_false(path.is_empty(), "blocked nearest circle boundary should still find alternate goal candidate")
	_assert_true(req.goal.contains_point(path.waypoints[0]), "alternate final waypoint should be on circle goal")
	_assert_true(path.waypoints[0].distance_to(Vector2(78.0, 50.0)) > 1.0, "alternate final waypoint should not use blocked nearest boundary")


func _test_avoid_moving_units_false_allows_direct_path() -> void:
	var nav_map := _base_map()
	var blocker := SimNavObstructionShapeUnit.new()
	blocker.entity_id = "moving_blocker"
	blocker.center = Vector2(50.0, 50.0)
	blocker.clearance = 12.0
	blocker.flags = SimNavObstructionFlags.BLOCK_MOVEMENT | SimNavObstructionFlags.MOVING
	blocker.moving = true
	nav_map.add_dynamic_obstruction(blocker)

	var req := _request(Vector2(10.0, 50.0), Vector2(90.0, 50.0))
	req.avoid_moving_units = false
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_equal(1, path.size(), "avoid_moving_units=false should ignore moving dynamic blocker")


func _test_group_filter_allows_direct_path() -> void:
	var nav_map := _base_map()
	var blocker := SimNavObstructionShapeUnit.new()
	blocker.entity_id = "blue_friend"
	blocker.center = Vector2(50.0, 50.0)
	blocker.clearance = 12.0
	blocker.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blocker.control_group = "blue"
	nav_map.add_dynamic_obstruction(blocker)

	var req := _request(Vector2(10.0, 50.0), Vector2(90.0, 50.0))
	req.control_group = "blue"
	var path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(req)
	_assert_equal(1, path.size(), "same control group should be filtered from dynamic blockers")


func _base_map() -> SimNavMap:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	nav_map.register_passability_class(ground)
	return nav_map


func _request(start: Vector2, goal: Vector2) -> SimNavShortPathRequest:
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal)
	req.clearance = 6.0
	req.range_px = 160.0
	req.pass_mask = 1
	req.avoid_moving_units = true
	return req


func _assert_segments_clear(start: Vector2, path: SimNavWaypointPath, nav_map: SimNavMap, clearance: float, label: String) -> void:
	var obstacles: Array = []
	obstacles.append_array(nav_map.get_static_obstruction_shapes())
	obstacles.append_array(nav_map.get_dynamic_obstruction_shapes())
	var prev := start
	for i in range(path.waypoints.size() - 1, -1, -1):
		var point := path.waypoints[i]
		if not SimNavLineOfSight.segment_clear(prev, point, obstacles, clearance):
			_failures.append("%s segment intersects obstacle: %s -> %s" % [label, str(prev), str(point)])
			return
		prev = point


func _assert_path_waypoints_passable(path: SimNavWaypointPath, nav_map: SimNavMap, pass_mask: int, label: String) -> void:
	for point in path.waypoints:
		var coord := nav_map.world_to_navcell(point)
		if not nav_map.is_passable_navcell(coord, pass_mask):
			_failures.append("%s contains blocked waypoint at %s" % [label, str(coord)])
			return


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_vec(expected: Vector2, actual: Vector2, message: String) -> void:
	if expected.distance_to(actual) > 0.01:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
