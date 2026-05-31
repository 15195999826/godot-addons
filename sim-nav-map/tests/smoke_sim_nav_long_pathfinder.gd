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
	_test_result_contract_status_and_canonicalization_metadata()
	_test_raw_refined_boundary_and_max_spacing()
	_test_start_recovery_status()
	_test_excluded_region_query_isolation()
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


func _test_result_contract_status_and_canonicalization_metadata() -> void:
	var nav_map := SimNavMap.new(12, 8, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(nav_map.height):
		nav_map.or_navcell_data(Vector2i(5, y), ground_mask)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, SimNavLongPathfinder.new(nav_map))
	var start := nav_map.navcell_center_world(Vector2i(2, 3))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(9, 3)))
	var query := SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground")
	var result := facade.compute_path_result(query)

	_assert_equal_str(SimNavLongPathResult.STATUS_CANONICALIZED, result.status, "blocked goal should report canonicalized long-path status")
	_assert_true(result.is_success(), "canonicalized long-path result should still be a navigable success")
	_assert_true(result.canonicalized, "result should expose canonicalized metadata")
	_assert_equal_str(SimNavReachabilityResult.FAILURE_ORIGINAL_GOAL_UNREACHABLE, result.canonicalization_reason, "result should preserve reachability canonicalization reason")
	_assert_equal_int(ground_mask, result.pass_mask, "result should echo passability mask")
	_assert_equal_str("ground", result.passability_class_name, "result should echo passability class name")
	_assert_true(result.query_goal.center.distance_to(goal.center) < 0.01, "result should preserve original query goal")
	_assert_true(result.canonical_goal != null, "result should expose canonical goal")
	_assert_true(result.canonical_navcell.x < 5, "canonical navcell should stay on start side")
	_assert_false(result.path.is_empty(), "canonicalized result should carry refined waypoint path")
	_assert_true(result.path_cost > 0, "result should expose path cost")
	_assert_true(result.path_length > 0.0, "result should expose path length")


func _test_raw_refined_boundary_and_max_spacing() -> void:
	var nav_map := SimNavMap.new(24, 3, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(20, 1)))

	var compressed_query := SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground")
	compressed_query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	var compressed_result := long_pathfinder.compute_path_result(compressed_query)
	_assert_equal_str(SimNavLongPathResult.STATUS_SUCCESS, compressed_result.status, "open row should report success")
	_assert_equal_str("jps", compressed_result.search_algorithm, "ordinary result queries should use JPS search")
	_assert_true(compressed_result.search_expansion_count > 0, "JPS result should expose expansion diagnostics")
	_assert_true(compressed_result.raw_navcell_count > compressed_result.refined_waypoint_count, "line-of-sight post-process should reduce raw waypoints")
	_assert_true(compressed_result.raw_waypoint_count > compressed_result.refined_waypoint_count, "raw waypoint count should remain visible after refinement")
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(1, 1)), nav_map.navcell_center_world(compressed_result.raw_navcell_path[0]), "raw navcell path should start at start cell")
	_assert_equal_vec(goal.center, compressed_result.path.waypoints[0], "stored refined path should keep reverse-consumption goal-first order")

	var spaced_query := SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground")
	spaced_query.post_process = SimNavLongPathQuery.POST_PROCESS_MAX_SPACING
	spaced_query.waypoint_spacing = 16.0
	var spaced_result := long_pathfinder.compute_path_result(spaced_query)
	_assert_equal_str(SimNavLongPathResult.STATUS_SUCCESS, spaced_result.status, "max-spacing query should still succeed")
	_assert_true(spaced_result.refined_waypoint_count > 1, "max spacing should add intermediate waypoints")
	_assert_max_spacing(start, spaced_result.path, 16.01, "max-spacing refined path")


func _test_start_recovery_status() -> void:
	var nav_map := SimNavMap.new(8, 3, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	nav_map.or_navcell_data(Vector2i(1, 1), ground_mask)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, SimNavLongPathfinder.new(nav_map))
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 1)))
	var result := facade.compute_path_result(SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground"))
	_assert_equal_str(SimNavLongPathResult.STATUS_START_RECOVERED, result.status, "blocked start should recover through reachability metadata")
	_assert_true(result.start_recovered, "result should expose start recovery")
	_assert_false(result.effective_start_navcell == result.start_navcell, "effective start navcell should differ from invalid start")
	_assert_false(result.path.is_empty(), "start-recovered result should still produce a path")


func _test_excluded_region_query_isolation() -> void:
	var nav_map := SimNavMap.new(12, 7, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(nav_map.height):
		if y == 1 or y == 5:
			continue
		nav_map.or_navcell_data(Vector2i(5, y), ground_mask)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var start := nav_map.navcell_center_world(Vector2i(2, 5))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(9, 5)))
	var lower_gap := Vector2i(5, 5)
	var upper_gap := Vector2i(5, 1)

	var base_result := long_pathfinder.compute_path_result(SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground"))
	_assert_equal_str(SimNavLongPathResult.STATUS_SUCCESS, base_result.status, "base query should use lower gap")
	_assert_true(_path_uses_cell(base_result.raw_navcell_path, lower_gap), "base query should use unexcluded lower gap")

	var excluded_query := SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground")
	excluded_query.add_excluded_circle(nav_map.navcell_center_world(lower_gap), 8.1)
	var excluded_result := long_pathfinder.compute_path_result(excluded_query)
	_assert_equal_str(SimNavLongPathResult.STATUS_SUCCESS, excluded_result.status, "excluded-region query should still find alternate gap")
	_assert_equal_str("astar_excluded", excluded_result.search_algorithm, "excluded-region query should keep request-scoped A* semantics")
	_assert_true(excluded_result.search_expansion_count > 0, "excluded-region result should expose A* expansion diagnostics")
	_assert_false(_path_uses_cell(excluded_result.raw_navcell_path, lower_gap), "excluded query should avoid request-scoped lower gap")
	_assert_true(_path_uses_cell(excluded_result.raw_navcell_path, upper_gap), "excluded query should detour through upper gap")
	_assert_true(nav_map.is_passable_navcell(lower_gap, ground_mask), "excluded region should not mutate map passability")

	var followup_result := long_pathfinder.compute_path_result(SimNavLongPathQuery.from_values(start, goal, ground_mask, "ground"))
	_assert_true(_path_uses_cell(followup_result.raw_navcell_path, lower_gap), "follow-up query should not inherit excluded region")


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


func _path_uses_cell(cells: Array[Vector2i], target: Vector2i) -> bool:
	for cell in cells:
		if cell == target:
			return true
	return false


func _assert_max_spacing(start: Vector2, path: SimNavWaypointPath, max_spacing: float, label: String) -> void:
	var previous := start
	for i in range(path.waypoints.size() - 1, -1, -1):
		var point := path.waypoints[i]
		if previous.distance_to(point) > max_spacing:
			_failures.append("%s segment exceeds max spacing: %.2f > %.2f" % [label, previous.distance_to(point), max_spacing])
			return
		previous = point


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal_int(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_vec(expected: Vector2, actual: Vector2, message: String) -> void:
	if expected.distance_to(actual) > 0.01:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
