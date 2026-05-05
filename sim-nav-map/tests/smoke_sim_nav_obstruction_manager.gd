extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map obstruction manager")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(12, 12, 8.0, Vector2.ZERO, 1)
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 4.0, true))
	var manager := SimNavObstructionManager.new(nav_map)

	var static_tag := manager.add_static_shape(
		"wall",
		nav_map.navcell_center_world(Vector2i(4, 4)),
		0.0,
		8.0,
		8.0,
		SimNavObstructionFlags.BLOCK_PATHFINDING,
		"team_a"
	)
	var unit_tag := manager.add_unit_shape(
		"unit",
		nav_map.navcell_center_world(Vector2i(6, 4)),
		6.0,
		SimNavObstructionFlags.BLOCK_MOVEMENT,
		"team_b"
	)
	var far_unit_tag := manager.add_unit_shape(
		"far_unit",
		nav_map.navcell_center_world(Vector2i(11, 11)),
		6.0,
		SimNavObstructionFlags.BLOCK_MOVEMENT,
		"team_c"
	)

	_assert_equal(1, static_tag, "first obstruction tag should be deterministic")
	_assert_equal(2, unit_tag, "second obstruction tag should be deterministic")
	_assert_equal(3, far_unit_tag, "third obstruction tag should be deterministic")
	_assert_true(manager.get_shape(static_tag) is SimNavObstructionShapeStatic, "static tag should resolve static shape")
	_assert_true(manager.get_shape(unit_tag) is SimNavObstructionShapeUnit, "unit tag should resolve unit shape")

	manager.rasterize()
	_assert_false(
		nav_map.is_passable_navcell(Vector2i(4, 4), ground_mask),
		"static manager shape should rasterize into navcell data"
	)
	_assert_true(
		nav_map.is_passable_navcell(Vector2i(6, 4), ground_mask),
		"unit manager shape should not rasterize into navcell data"
	)

	var nearby := manager.get_obstructions_in_range(nav_map.navcell_center_world(Vector2i(5, 4)), 24.0)
	_assert_equal(2, nearby.size(), "range query should return static and unit shapes")
	_assert_equal(static_tag, nearby[0].tag, "range query should be sorted by tag")
	_assert_equal(unit_tag, nearby[1].tag, "range query should keep deterministic tag order")

	_assert_true(manager.move_shape(far_unit_tag, nav_map.navcell_center_world(Vector2i(5, 5))), "move_shape should update spatial index for unit shape")
	nearby = manager.get_obstructions_in_range(nav_map.navcell_center_world(Vector2i(5, 4)), 24.0)
	_assert_equal(3, nearby.size(), "range query should include moved unit spatial candidate")
	_assert_equal(far_unit_tag, nearby[2].tag, "range query should keep moved unit in deterministic order")

	_assert_true(manager.set_unit_moving_flag(unit_tag, true), "set_unit_moving_flag should update unit")
	var unit_shape := manager.get_shape(unit_tag) as SimNavObstructionShapeUnit
	_assert_true(unit_shape.moving, "unit moving flag should be set")
	_assert_true((unit_shape.flags & SimNavObstructionFlags.MOVING) != 0, "unit MOVING bit should be set")

	_assert_true(manager.move_shape(static_tag, nav_map.navcell_center_world(Vector2i(8, 4))), "move_shape should update static shape")
	manager.rasterize()
	_assert_true(
		nav_map.is_passable_navcell(Vector2i(4, 4), ground_mask),
		"moved static shape should clear old rasterized cell on rebuild"
	)
	_assert_false(
		nav_map.is_passable_navcell(Vector2i(8, 4), ground_mask),
		"moved static shape should block new rasterized cell"
	)

	_assert_true(manager.remove_shape(static_tag), "remove_shape should remove existing static")
	_assert_false(manager.remove_shape(static_tag), "remove_shape should be idempotent for missing tags")
	manager.rasterize()
	_assert_true(
		nav_map.is_passable_navcell(Vector2i(8, 4), ground_mask),
		"removed static shape should clear rasterized cells"
	)


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


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])
