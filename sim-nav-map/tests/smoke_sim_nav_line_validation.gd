extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map line validation")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_filtered_range_query()
	_test_movement_line_blocks_on_passability()
	_test_movement_line_obstruction_filter()
	_test_unit_only_line_validation()


func _test_filtered_range_query() -> void:
	var nav_map := _base_map()
	var manager := SimNavObstructionManager.new(nav_map)
	var static_tag := manager.add_static_shape(
		"wall",
		Vector2(48.0, 48.0),
		0.0,
		16.0,
		16.0,
		SimNavObstructionFlags.BLOCK_PATHFINDING
	)
	manager.add_unit_shape(
		"unit",
		Vector2(64.0, 48.0),
		8.0,
		SimNavObstructionFlags.BLOCK_MOVEMENT,
		"red"
	)
	var filter := SimNavObstructionFilter.units_only()
	var unit_shapes := manager.get_obstructions_in_range_filtered(Vector2(56.0, 48.0), 40.0, filter)
	_assert_equal(1, unit_shapes.size(), "units-only range filter should exclude static shapes")
	_assert_true(unit_shapes[0] is SimNavObstructionShapeUnit, "units-only range filter should return unit shape")
	filter = SimNavObstructionFilter.new()
	filter.ignored_tag = static_tag
	var filtered_shapes := manager.get_obstructions_in_range_filtered(Vector2(56.0, 48.0), 40.0, filter)
	_assert_equal(1, filtered_shapes.size(), "ignored tag filter should remove matching shape")
	_assert_true(filtered_shapes[0] is SimNavObstructionShapeUnit, "ignored tag filter should leave other shape types")


func _test_movement_line_blocks_on_passability() -> void:
	var nav_map := _base_map()
	nav_map.or_navcell_data(Vector2i(6, 6), 1)
	var facade := SimNavPathfinderFacade.new(nav_map)
	var result := facade.validate_movement_line(
		nav_map.navcell_center_world(Vector2i(1, 6)),
		nav_map.navcell_center_world(Vector2i(10, 6)),
		0.0,
		1
	)
	_assert_equal_str(SimNavMovementLineResult.STATUS_BLOCKED, result.status, "movement line should block on passability")
	_assert_equal_str(SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED, result.failure_reason, "movement line should expose passability reason")
	_assert_equal_vec2i(Vector2i(6, 6), result.blocked_navcell, "movement line should expose blocked navcell")


func _test_movement_line_obstruction_filter() -> void:
	var nav_map := _base_map()
	var manager := SimNavObstructionManager.new(nav_map)
	var static_tag := manager.add_static_shape(
		"wall",
		Vector2(48.0, 48.0),
		0.0,
		16.0,
		16.0,
		SimNavObstructionFlags.BLOCK_PATHFINDING
	)
	var facade := SimNavPathfinderFacade.new(nav_map)
	var blocked := facade.validate_movement_line(Vector2(8.0, 48.0), Vector2(104.0, 48.0), 0.0, 1)
	_assert_equal_str(SimNavMovementLineResult.FAILURE_STATIC_OBSTRUCTION_BLOCKED, blocked.failure_reason, "movement line should report static obstruction")
	_assert_equal(static_tag, blocked.blocked_obstruction_tag, "movement line should expose obstruction tag")
	var filter := SimNavObstructionFilter.new()
	filter.ignored_tag = static_tag
	var clear := facade.validate_movement_line(Vector2(8.0, 48.0), Vector2(104.0, 48.0), 0.0, 1, filter)
	_assert_true(clear.is_success(), "movement line should respect ignored tag filter")


func _test_unit_only_line_validation() -> void:
	var nav_map := _base_map()
	var manager := SimNavObstructionManager.new(nav_map)
	manager.add_static_shape(
		"wall",
		Vector2(48.0, 48.0),
		0.0,
		16.0,
		16.0,
		SimNavObstructionFlags.BLOCK_PATHFINDING
	)
	var unit_tag := manager.add_unit_shape(
		"unit",
		Vector2(64.0, 48.0),
		8.0,
		SimNavObstructionFlags.BLOCK_MOVEMENT,
		"blue"
	)
	var facade := SimNavPathfinderFacade.new(nav_map)
	var blocked := facade.validate_unit_line(Vector2(8.0, 48.0), Vector2(104.0, 48.0), 0.0)
	_assert_equal_str(SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED, blocked.failure_reason, "unit line should ignore static and report unit blocker")
	_assert_equal(unit_tag, blocked.blocked_obstruction_tag, "unit line should expose unit tag")
	var filter := SimNavObstructionFilter.units_only(true, "blue")
	var clear := facade.validate_unit_line(Vector2(8.0, 48.0), Vector2(104.0, 48.0), 0.0, filter)
	_assert_true(clear.is_success(), "unit line should respect control group filter")


func _base_map() -> SimNavMap:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	nav_map.register_passability_class(ground)
	return nav_map


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal_vec2i(expected: Vector2i, actual: Vector2i, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
