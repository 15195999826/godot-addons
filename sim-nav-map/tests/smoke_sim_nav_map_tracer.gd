extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map tracer bullet")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(12, 12, 8.0, Vector2.ZERO, 4)

	var infantry := SimNavPassabilityClassConfig.new()
	infantry.class_name_id = "infantry"
	infantry.clearance = 8.0
	infantry.affects_pathfinding = true
	var infantry_mask: int = nav_map.register_passability_class(infantry)

	var air := SimNavPassabilityClassConfig.new()
	air.class_name_id = "air"
	air.clearance = 0.0
	air.affects_pathfinding = false
	var air_mask: int = nav_map.register_passability_class(air)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "stone_wall"
	blocker.center = nav_map.navcell_center_world(Vector2i(5, 5))
	blocker.width = 8.0
	blocker.height = 8.0
	blocker.rotation_rad = 0.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	var blocker_tag: int = nav_map.add_static_obstruction(blocker)

	nav_map.rebuild_dirty()

	_assert_false(
		nav_map.is_passable_navcell(Vector2i(5, 5), infantry_mask),
		"infantry center navcell should be blocked by static obstruction"
	)
	_assert_false(
		nav_map.is_passable_navcell(Vector2i(4, 5), infantry_mask),
		"infantry adjacent navcell should be blocked by clearance rasterization"
	)
	_assert_true(
		nav_map.is_passable_navcell(Vector2i(5, 5), air_mask),
		"air passability class should ignore pathfinding obstructions"
	)

	var stored_shape := nav_map.get_obstruction_shape(blocker_tag) as SimNavObstructionShapeStatic
	_assert_true(stored_shape != null, "static obstruction shape should remain queryable")
	_assert_true(
		stored_shape.contains_point(blocker.center),
		"stored static obstruction should keep high precision shape data"
	)

	var dynamic_cell := Vector2i(1, 1)
	var before_dynamic: int = nav_map.get_navcell_data(dynamic_cell)
	var unit_shape := SimNavObstructionShapeUnit.new()
	unit_shape.entity_id = "moving_unit"
	unit_shape.center = nav_map.navcell_center_world(dynamic_cell)
	unit_shape.clearance = 8.0
	unit_shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	nav_map.add_dynamic_obstruction(unit_shape)
	nav_map.rebuild_dirty()
	_assert_equal(
		before_dynamic,
		nav_map.get_navcell_data(dynamic_cell),
		"dynamic unit obstruction should not be rasterized into navcell data"
	)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])
