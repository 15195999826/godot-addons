extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map reachability query")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_point_canonicalization_metadata()
	_test_area_goal_types()
	_test_passability_mask_contract()
	_test_dirty_recompute_changes_canonical_target()


func _test_point_canonicalization_metadata() -> void:
	var nav_map := SimNavMap.new(120, 8, 8.0, Vector2.ZERO, 1)
	var ground_mask := _register_ground(nav_map, "ground")
	_block_vertical_navcells(nav_map, 60, ground_mask)
	var facade := _build_facade(nav_map, [ground_mask])
	var start := nav_map.navcell_center_world(Vector2i(10, 4))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(110, 4)))
	var result := facade.query_reachability(start, goal, ground_mask, "ground")

	_assert_false(result.is_reachable, "point behind wall should not report original goal reachable")
	_assert_true(result.canonicalized, "point behind wall should canonicalize")
	_assert_equal_str(SimNavReachabilityResult.FAILURE_ORIGINAL_GOAL_UNREACHABLE, result.failure_reason, "point canonicalization reason")
	_assert_equal_int(ground_mask, result.pass_mask, "reachability result should echo pass mask")
	_assert_equal_str("ground", result.passability_class_name, "reachability result should echo passability class name")
	_assert_true(result.has_canonical_goal(), "point canonicalization should return canonical goal")
	_assert_true(result.canonical_navcell.x < 60, "point canonical target should stay on start side")
	_assert_equal_int(result.start_global_region, result.canonical_global_region, "canonical target should stay in start global region")


func _test_area_goal_types() -> void:
	var nav_map := SimNavMap.new(80, 8, 8.0, Vector2.ZERO, 1)
	var ground_mask := _register_ground(nav_map, "ground")
	_block_vertical_navcells(nav_map, 40, ground_mask)
	var facade := _build_facade(nav_map, [ground_mask])
	var start := nav_map.navcell_center_world(Vector2i(10, 4))

	var circle_goal := SimNavPathGoal.circle(nav_map.navcell_center_world(Vector2i(44, 4)), 48.0)
	var circle_result := facade.query_reachability(start, circle_goal, ground_mask, "ground")
	_assert_true(circle_result.is_reachable, "circle crossing wall should have a reachable goal cell")
	_assert_false(circle_result.canonicalized, "reachable circle should not rewrite goal")
	_assert_true(circle_result.canonical_navcell.x < 40, "circle metadata should choose reachable side")

	var square_goal := SimNavPathGoal.square(nav_map.navcell_center_world(Vector2i(44, 4)), 48.0, 12.0)
	var square_result := facade.query_reachability(start, square_goal, ground_mask, "ground")
	_assert_true(square_result.is_reachable, "square crossing wall should have a reachable goal cell")
	_assert_false(square_result.canonicalized, "reachable square should not rewrite goal")
	_assert_true(square_result.canonical_navcell.x < 40, "square metadata should choose reachable side")

	var inverted_goal := SimNavPathGoal.inverted_circle(start, 16.0)
	var inverted_result := facade.query_reachability(start, inverted_goal, ground_mask, "ground")
	_assert_true(inverted_result.is_reachable, "inverted circle should find a reachable outside cell")
	_assert_false(inverted_result.canonicalized, "reachable inverted circle should not rewrite goal")
	_assert_true(inverted_goal.navcell_contains_goal(nav_map, inverted_result.canonical_navcell), "inverted canonical navcell should satisfy goal")


func _test_passability_mask_contract() -> void:
	var nav_map := SimNavMap.new(12, 6, 8.0, Vector2.ZERO, 1)
	var small_mask := _register_ground(nav_map, "small")
	var large := SimNavPassabilityClassConfig.new()
	large.class_name_id = "large"
	large.clearance = 0.0
	large.affects_pathfinding = true
	large.terrain_mask = 0x1
	var large_mask := nav_map.register_passability_class(large)
	for y in range(nav_map.height):
		nav_map.set_terrain_tile_data(Vector2i(5, y), 0x1)
	var facade := _build_facade(nav_map, [small_mask, large_mask])
	var start := nav_map.navcell_center_world(Vector2i(1, 3))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(10, 3)))

	var small_result := facade.query_reachability(start, goal, small_mask, "small")
	_assert_true(small_result.is_reachable, "small passability mask should ignore large-only terrain wall")
	_assert_equal_int(small_mask, small_result.pass_mask, "small result should echo small pass mask")
	_assert_equal_str("small", small_result.passability_class_name, "small result should echo class name")

	var large_result := facade.query_reachability(start, goal, large_mask, "large")
	_assert_false(large_result.is_reachable, "large passability mask should see terrain wall")
	_assert_true(large_result.canonicalized, "large passability mask should canonicalize blocked target")
	_assert_equal_int(large_mask, large_result.pass_mask, "large result should echo large pass mask")
	_assert_equal_str("large", large_result.passability_class_name, "large result should echo class name")


func _test_dirty_recompute_changes_canonical_target() -> void:
	var nav_map := SimNavMap.new(120, 8, 8.0, Vector2.ZERO, 1)
	var ground_mask := _register_terrain_ground(nav_map, "ground")
	for y in range(nav_map.height):
		nav_map.set_terrain_tile_data(Vector2i(60, y), 0x1)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, SimNavLongPathfinder.new(nav_map))
	var start := nav_map.navcell_center_world(Vector2i(10, 4))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(110, 4)))

	var blocked_result := facade.query_reachability(start, goal, ground_mask, "ground")
	_assert_true(blocked_result.canonicalized, "blocked terrain wall should canonicalize target before dirty edit")
	_assert_true(blocked_result.canonical_navcell.x < 60, "blocked canonical target should stay on start side")

	nav_map.set_terrain_tile_data(Vector2i(60, 4), 0)
	facade.recompute_dirty([ground_mask])
	var reopened_result := facade.query_reachability(start, goal, ground_mask, "ground")
	_assert_true(reopened_result.is_reachable, "dirty recompute should reconnect target through terrain gap")
	_assert_false(reopened_result.canonicalized, "reopened target should no longer canonicalize")
	_assert_equal_vec2i(Vector2i(110, 4), reopened_result.canonical_navcell, "reopened point target should keep original navcell")


func _build_facade(nav_map: SimNavMap, passability_masks: Array[int]) -> SimNavPathfinderFacade:
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, passability_masks)
	return SimNavPathfinderFacade.new(nav_map, hierarchical, SimNavLongPathfinder.new(nav_map))


func _register_ground(nav_map: SimNavMap, class_name_id: String) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = class_name_id
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	return nav_map.register_passability_class(ground)


func _register_terrain_ground(nav_map: SimNavMap, class_name_id: String) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = class_name_id
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	ground.terrain_mask = 0x1
	return nav_map.register_passability_class(ground)


func _block_vertical_navcells(nav_map: SimNavMap, x: int, pass_mask: int) -> void:
	for y in range(nav_map.height):
		nav_map.or_navcell_data(Vector2i(x, y), pass_mask)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal_int(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal_vec2i(expected: Vector2i, actual: Vector2i, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
