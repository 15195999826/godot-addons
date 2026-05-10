extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map public API contract")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_constructor_defaults()
	_test_map_projection_entry_points()
	_test_long_path_dirty_cache_boundary()
	_test_short_path_boundary()
	_test_request_queue_clones_public_request_data()


func _test_constructor_defaults() -> void:
	var empty_map := SimNavMap.new()
	_assert_equal_int(0, empty_map.width, "default map width should be 0")
	_assert_equal_int(0, empty_map.height, "default map height should be 0")
	_assert_float(1.0, empty_map.navcell_size, "default map navcell_size should be 1")
	_assert_equal_vec2(Vector2.ZERO, empty_map.origin, "default map origin should be zero")
	_assert_equal_int(1, empty_map.navcells_per_tile, "default map navcells_per_tile should be 1")
	_assert_false(empty_map.has_dirty_navcells(), "default map should start without dirty navcells")
	_assert_false(empty_map.is_valid_navcell(Vector2i.ZERO), "default empty map should have no valid navcells")

	var nav_map := SimNavMap.new(5, 4, 8.0, Vector2(16.0, 24.0), 0)
	_assert_equal_int(1, nav_map.navcells_per_tile, "map constructor should clamp navcells_per_tile to at least 1")
	_assert_equal_vec2(Vector2(28.0, 36.0), nav_map.navcell_center_world(Vector2i(1, 1)), "navcell center should apply origin and cell size")
	_assert_equal_vec2i(Vector2i(1, 1), nav_map.world_to_navcell(Vector2(28.0, 36.0)), "world_to_navcell should invert navcell_center_world for cell centers")

	var config := SimNavPassabilityClassConfig.new()
	_assert_equal_str("", config.class_name_id, "passability config default class_name_id should be empty")
	_assert_equal_int(-1, config.bit_index, "passability config bit_index should start unassigned")
	_assert_float(0.0, config.clearance, "passability config clearance should default to zero")
	_assert_true(config.affects_pathfinding, "passability config should affect pathfinding by default")
	_assert_equal_int(0, config.terrain_mask, "passability config terrain_mask should default to zero")

	var static_shape := SimNavObstructionShapeStatic.new()
	_assert_equal_int(SimNavObstructionShape.Type.STATIC, static_shape.type, "static obstruction should set base type")
	_assert_true(static_shape.contains_point(Vector2.ZERO), "zero-size static obstruction should contain its center")
	_assert_false(static_shape.contains_point(Vector2(1.0, 0.0)), "zero-size static obstruction should not contain off-center points")
	var unit_shape := SimNavObstructionShapeUnit.new()
	_assert_equal_int(SimNavObstructionShape.Type.UNIT, unit_shape.type, "unit obstruction should set base type")
	_assert_true(unit_shape.contains_point(Vector2.ZERO), "zero-clearance unit should contain its center")

	var request := SimNavShortPathRequest.new()
	_assert_null(request.goal, "short path request goal should default to null")
	_assert_float(256.0, request.range_px, "short path request range should default to 256 px")
	_assert_true(request.avoid_moving_units, "short path request should avoid moving units by default")
	var default_filter := request.get_obstruction_filter()
	_assert_true(default_filter.include_static, "short path default filter should include static obstructions")
	_assert_true(default_filter.include_units, "short path default filter should include unit obstructions")

	var short_result := SimNavShortPathResult.new()
	short_result.configure_query(request)
	_assert_equal_str(SimNavShortPathResult.STATUS_INVALID_QUERY, short_result.status, "short path result default status should be invalid_query")
	_assert_float(256.0, short_result.range_px, "short path result should snapshot query range")

	var movement_line := SimNavMovementLineResult.new()
	movement_line.configure_query(Vector2.ZERO, Vector2(8.0, 0.0), 2.0, 1, SimNavObstructionFilter.units_only(), true)
	_assert_equal_str(SimNavMovementLineResult.STATUS_INVALID_QUERY, movement_line.status, "movement line result default status should be invalid_query")
	_assert_true(movement_line.unit_only, "movement line result should snapshot unit-only query mode")

	var path := SimNavWaypointPath.new()
	_assert_true(path.is_empty(), "new waypoint path should be empty")
	path.push_back(Vector2(3.0, 4.0))
	_assert_equal_int(1, path.size(), "waypoint path push_back should append")
	_assert_equal_vec2(Vector2(3.0, 4.0), path.back(), "waypoint path back should return last point")
	_assert_equal_vec2(Vector2(3.0, 4.0), path.pop_back(), "waypoint path pop_back should remove last point")
	_assert_true(path.is_empty(), "waypoint path should be empty after pop")

	var long_query := SimNavLongPathQuery.from_values(Vector2(1.0, 2.0), SimNavPathGoal.point(Vector2(16.0, 16.0)), 1, "ground")
	long_query.add_excluded_circle(Vector2(8.0, 8.0), 4.0)
	long_query.post_process = SimNavLongPathQuery.POST_PROCESS_MAX_SPACING
	long_query.waypoint_spacing = 12.0
	var cloned_query := long_query.clone()
	long_query.goal.center = Vector2(80.0, 80.0)
	_assert_equal_vec2(Vector2(16.0, 16.0), cloned_query.goal.center, "long path query clone should own goal data")
	_assert_equal_int(1, cloned_query.excluded_regions.size(), "long path query should clone excluded regions")
	_assert_float(12.0, cloned_query.waypoint_spacing, "long path query should expose waypoint spacing preference")

	var long_result := SimNavLongPathResult.new()
	long_result.configure_query(cloned_query)
	_assert_equal_str(SimNavLongPathResult.STATUS_INVALID_QUERY, long_result.status, "long path result default status should be invalid_query")
	_assert_equal_str("ground", long_result.passability_class_name, "long path result should echo query class name")
	_assert_equal_int(1, long_result.excluded_regions.size(), "long path result should snapshot excluded region metadata")


func _test_map_projection_entry_points() -> void:
	var nav_map := SimNavMap.new(8, 6, 8.0, Vector2.ZERO, 2)
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 0.0, true))
	_assert_equal_int(1, ground_mask, "map should register first passability mask")
	var terrain_ground := _class_config("terrain_ground", 0.0, true)
	terrain_ground.terrain_mask = 0x20
	var terrain_ground_mask := nav_map.register_passability_class(terrain_ground)
	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0x20)
	_assert_equal_int(0x20, nav_map.get_navcell_terrain_data(Vector2i(2, 1)), "map should expose terrain tile data through navcells")
	_assert_false(nav_map.is_passable_navcell(Vector2i(2, 1), terrain_ground_mask), "map should derive terrain passability from terrain_mask")
	_assert_equal_int(0, nav_map.rebuild_terrain_passability(), "unchanged terrain passability rebuild should be stable")

	var static_shape := SimNavObstructionShapeStatic.new()
	static_shape.entity_id = "wall"
	static_shape.center = nav_map.navcell_center_world(Vector2i(2, 2))
	static_shape.width = 8.0
	static_shape.height = 8.0
	static_shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	var static_tag := nav_map.add_static_obstruction(static_shape)
	_assert_equal_int(1, static_tag, "first obstruction tag should be stable")
	_assert_true(nav_map.get_obstruction_shape(static_tag) is SimNavObstructionShapeStatic, "static tag should return base obstruction shape typed as static")
	_assert_true(nav_map.has_dirty_obstruction_navcells(), "adding static obstruction should mark obstruction dirtiness")
	nav_map.rebuild_dirty()
	_assert_false(nav_map.is_passable_navcell(Vector2i(2, 2), ground_mask), "rebuild_dirty should rasterize static obstruction")

	var dynamic_shape := SimNavObstructionShapeUnit.new()
	dynamic_shape.entity_id = "unit"
	dynamic_shape.center = nav_map.navcell_center_world(Vector2i(4, 2))
	dynamic_shape.clearance = 6.0
	dynamic_shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	var dynamic_tag := nav_map.add_dynamic_obstruction(dynamic_shape)
	_assert_equal_int(2, dynamic_tag, "dynamic obstruction tags should share the map tag sequence")
	_assert_true(nav_map.get_obstruction_shape(dynamic_tag) is SimNavObstructionShapeUnit, "dynamic tag should return base obstruction shape typed as unit")

	var nearby := nav_map.get_obstruction_shapes_in_range(nav_map.navcell_center_world(Vector2i(3, 2)), 24.0)
	_assert_equal_int(2, nearby.size(), "range query should include nearby static and dynamic projections")
	_assert_equal_int(static_tag, nearby[0].tag, "range query should be sorted by tag")
	_assert_equal_int(dynamic_tag, nearby[1].tag, "range query should keep deterministic tag order")

	_assert_true(nav_map.move_obstruction(static_tag, nav_map.navcell_center_world(Vector2i(5, 2))), "move_obstruction should move static shape")
	nav_map.rasterize_dirty_obstructions()
	_assert_true(nav_map.is_passable_navcell(Vector2i(2, 2), ground_mask), "dirty rasterize should clear old static navcell")
	_assert_false(nav_map.is_passable_navcell(Vector2i(5, 2), ground_mask), "dirty rasterize should block moved static navcell")

	var replacement := SimNavObstructionShapeUnit.new()
	replacement.entity_id = "replacement"
	replacement.center = nav_map.navcell_center_world(Vector2i(6, 2))
	replacement.clearance = 6.0
	replacement.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	var replacements: Array[SimNavObstructionShapeUnit] = [replacement]
	nav_map.replace_dynamic_obstructions(replacements)
	_assert_equal_int(1, nav_map.get_dynamic_obstruction_shapes().size(), "replace_dynamic_obstructions should replace existing dynamic projections")
	_assert_equal_str("replacement", nav_map.get_dynamic_obstruction_shapes()[0].entity_id, "replacement dynamic projection should be stored")
	_assert_true(nav_map.remove_obstruction(static_tag), "remove_obstruction should remove static projection")
	nav_map.rasterize_dirty_obstructions()
	_assert_true(nav_map.is_passable_navcell(Vector2i(5, 2), ground_mask), "removing static projection should clear rasterized navcell")


func _test_long_path_dirty_cache_boundary() -> void:
	var nav_map := SimNavMap.new(8, 3, 8.0, Vector2.ZERO, 1)
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 0.0, true))
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 1)))
	var open_path := long_pathfinder.compute_path_immediate(start, goal, ground_mask)
	_assert_false(open_path.is_empty(), "long path should find an open row")

	for y in range(nav_map.height):
		nav_map.or_navcell_data(Vector2i(3, y), ground_mask)
	var blocked_path := long_pathfinder.compute_path_immediate(start, goal, ground_mask)
	_assert_true(blocked_path.is_empty(), "long path cache should observe dirty navcells before re-query")

	long_pathfinder.invalidate_jump_point_cache()
	for y in range(nav_map.height):
		nav_map.and_navcell_data(Vector2i(3, y), ground_mask)
	var reopened_path := long_pathfinder.compute_path_immediate(start, goal, ground_mask)
	_assert_false(reopened_path.is_empty(), "manual cache invalidation plus cleared cells should reopen the path")


func _test_short_path_boundary() -> void:
	var empty_vertex := SimNavVertexPathfinder.new()
	var null_result := empty_vertex.compute_short_path_immediate(null)
	_assert_true(null_result.is_empty(), "short pathfinder without map/request should return empty path")

	var nav_map := SimNavMap.new(8, 8, 8.0, Vector2.ZERO, 1)
	nav_map.register_passability_class(_class_config("ground", 0.0, true))
	var request := SimNavShortPathRequest.new()
	request.start = Vector2(16.0, 16.0)
	request.goal = SimNavPathGoal.circle(Vector2(16.0, 16.0), 8.0)
	request.clearance = 4.0
	request.pass_mask = 1
	var same_goal_path := SimNavVertexPathfinder.new(nav_map).compute_short_path_immediate(request)
	_assert_equal_int(1, same_goal_path.size(), "short path should return a single waypoint when start is already inside goal")
	_assert_equal_vec2(request.start, same_goal_path.waypoints[0], "same-goal short path should preserve start point")


func _test_request_queue_clones_public_request_data() -> void:
	var nav_map := SimNavMap.new(12, 4, 8.0, Vector2.ZERO, 1)
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 0.0, true))
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, null, long_pathfinder)
	var queue := SimNavPathRequestQueue.new(facade, SimNavVertexPathfinder.new(nav_map))
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var original_long_goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1)))
	var long_ticket := queue.enqueue_long_path(start, original_long_goal, ground_mask)
	original_long_goal.center = nav_map.navcell_center_world(Vector2i(9, 1))

	var short_request := SimNavShortPathRequest.new()
	short_request.start = Vector2(16.0, 24.0)
	short_request.goal = SimNavPathGoal.point(Vector2(40.0, 24.0))
	short_request.clearance = 2.0
	short_request.pass_mask = ground_mask
	var short_ticket := queue.enqueue_short_path(short_request)
	short_request.goal.center = Vector2(80.0, 24.0)
	short_request.start = Vector2(8.0, 24.0)

	_assert_equal_int(2, queue.process_budget(2), "queue should process both cloned requests")
	var long_path := queue.take_result(long_ticket)
	_assert_false(long_path.is_empty(), "queued long path should produce a result")
	_assert_equal_vec2(nav_map.navcell_center_world(Vector2i(4, 1)), long_path.waypoints[0], "queued long path should use goal cloned at enqueue time")

	var short_path := queue.take_result(short_ticket)
	_assert_equal_int(1, short_path.size(), "queued short path should produce direct path")
	_assert_equal_vec2(Vector2(40.0, 24.0), short_path.waypoints[0], "queued short path should use request cloned at enqueue time")


func _class_config(name_id: String, clearance: float, affects_pathfinding: bool) -> SimNavPassabilityClassConfig:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = name_id
	config.clearance = clearance
	config.affects_pathfinding = affects_pathfinding
	return config


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_null(value: Variant, message: String) -> void:
	if value != null:
		_failures.append(message)


func _assert_equal_int(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_float(expected: float, actual: float, message: String) -> void:
	if absf(expected - actual) > 0.001:
		_failures.append("%s (expected=%.3f actual=%.3f)" % [message, expected, actual])


func _assert_equal_vec2(expected: Vector2, actual: Vector2, message: String) -> void:
	if expected.distance_to(actual) > 0.01:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _assert_equal_vec2i(expected: Vector2i, actual: Vector2i, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
