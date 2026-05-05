extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map long pathfinder")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_direct_path()
	_test_circle_goal_area_stops_at_first_goal_cell()
	_test_path_around_wall_gap()
	_test_unreachable_goal_canonicalized_by_hierarchy()
	_test_deterministic_repeated_path()


func _test_direct_path() -> void:
	var nav_map := SimNavMap.new(8, 3, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 1)))
	var path := long_pathfinder.compute_path_immediate(nav_map.navcell_center_world(Vector2i(1, 1)), goal, ground_mask)
	_assert_false(path.is_empty(), "direct path should not be empty")
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(6, 1)), path.waypoints[0], "direct path first stored waypoint should be goal")
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(2, 1)), path.back(), "direct path back() should be next step")


func _test_circle_goal_area_stops_at_first_goal_cell() -> void:
	var nav_map := SimNavMap.new(8, 3, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var goal := SimNavPathGoal.circle(nav_map.navcell_center_world(Vector2i(6, 1)), 10.0)
	var path := long_pathfinder.compute_path_immediate(nav_map.navcell_center_world(Vector2i(1, 1)), goal, ground_mask)
	_assert_false(path.is_empty(), "circle goal area path should not be empty")
	var final_cell := nav_map.world_to_navcell(path.waypoints[0])
	_assert_equal_int(5, final_cell.x, "circle goal should stop at first navcell intersecting goal area")
	_assert_equal_int(1, final_cell.y, "circle goal final navcell should stay on row")


func _test_path_around_wall_gap() -> void:
	var nav_map := SimNavMap.new(12, 8, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(1, 8):
		nav_map.or_navcell_data(Vector2i(5, y), ground_mask)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(9, 3)))
	var path := long_pathfinder.compute_path_immediate(nav_map.navcell_center_world(Vector2i(2, 3)), goal, ground_mask)
	_assert_false(path.is_empty(), "wall-gap path should not be empty")
	_assert_true(_path_uses_gap_row(nav_map, path), "wall-gap path should detour through the open gap row")
	_assert_path_cells_passable(nav_map, path, ground_mask, "wall-gap path")


func _test_unreachable_goal_canonicalized_by_hierarchy() -> void:
	var nav_map := SimNavMap.new(12, 8, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(nav_map.height):
		nav_map.or_navcell_data(Vector2i(5, y), ground_mask)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(9, 3)))
	var path := facade.compute_path_immediate(nav_map.navcell_center_world(Vector2i(2, 3)), goal, ground_mask)
	var canonical_cell := nav_map.world_to_navcell(goal.center)
	_assert_true(canonical_cell.x < 5, "unreachable goal should canonicalize to start side")
	_assert_false(path.is_empty(), "canonicalized unreachable goal should still produce a path")
	_assert_path_cells_passable(nav_map, path, ground_mask, "canonicalized path")


func _test_deterministic_repeated_path() -> void:
	var nav_map := SimNavMap.new(12, 8, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(1, 8):
		nav_map.or_navcell_data(Vector2i(5, y), ground_mask)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var start := nav_map.navcell_center_world(Vector2i(2, 3))
	var goal_a := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(9, 3)))
	var goal_b := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(9, 3)))
	var path_a := long_pathfinder.compute_path_immediate(start, goal_a, ground_mask)
	var path_b := long_pathfinder.compute_path_immediate(start, goal_b, ground_mask)
	_assert_equal(_path_signature(path_a), _path_signature(path_b), "repeated long path should be deterministic")


func _register_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	return nav_map.register_passability_class(ground)


func _assert_path_cells_passable(nav_map: SimNavMap, path: SimNavWaypointPath, pass_mask: int, label: String) -> void:
	for point in path.waypoints:
		var coord := nav_map.world_to_navcell(point)
		if not nav_map.is_passable_navcell(coord, pass_mask):
			_failures.append("%s contains blocked waypoint at %s" % [label, str(coord)])
			return


func _path_uses_gap_row(nav_map: SimNavMap, path: SimNavWaypointPath) -> bool:
	for point in path.waypoints:
		var coord := nav_map.world_to_navcell(point)
		if coord.y == 0:
			return true
	return false


func _path_signature(path: SimNavWaypointPath) -> String:
	var cells: Array[String] = []
	for point in path.waypoints:
		cells.append("%.1f,%.1f" % [point.x, point.y])
	return "|".join(cells)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal_int(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_vec(expected: Vector2, actual: Vector2, message: String) -> void:
	if expected.distance_to(actual) > 0.01:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
