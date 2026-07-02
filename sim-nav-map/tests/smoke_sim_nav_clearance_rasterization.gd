extends Node


const TERRAIN_WATER: int = 1

var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map clearance rasterization")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_static_obstruction_clearance_masks_are_class_aware()
	_test_terrain_clearance_masks_are_class_aware()
	_test_static_gap_path_depends_on_clearance()
	_test_terrain_gap_path_depends_on_clearance()


func _test_static_obstruction_clearance_masks_are_class_aware() -> void:
	# Static rasterization adds CLEARANCE_EXTENSION_RADIUS (+1 navcell = 8.0
	# here, 0 A.D. parity; CORE-005), so effective raster radii are
	# small = 0 + 8 = 8 and large = 16 + 8 = 24. Cell (4, 2) center sits 4 px
	# from the blocker edge (both classes blocked); cell (5, 2) center sits
	# 12 px away (only large blocked).
	var nav_map := SimNavMap.new(8, 5, 8.0, Vector2.ZERO, 1)
	var small_mask := nav_map.register_passability_class(_class_config("small", 0.0, 0))
	var large_mask := nav_map.register_passability_class(_class_config("large", 16.0, 0))
	_add_static_cell_blocker(nav_map, Vector2i(3, 2))
	nav_map.rebuild_dirty()

	var center_mask := nav_map.get_navcell_data(Vector2i(3, 2)) & (small_mask | large_mask)
	var far_mask := nav_map.get_navcell_data(Vector2i(5, 2)) & (small_mask | large_mask)
	_assert_equal_int(small_mask | large_mask, center_mask, "static blocker center should block every pathfinding class")
	_assert_equal_int(large_mask, far_mask, "static blocker clearance should block only the large class two navcells out")
	_assert_true(nav_map.is_passable_navcell(Vector2i(5, 2), small_mask), "small class should pass two navcells from static blocker")
	_assert_false(nav_map.is_passable_navcell(Vector2i(5, 2), large_mask), "large class should not pass two navcells from static blocker")


func _test_terrain_clearance_masks_are_class_aware() -> void:
	var nav_map := SimNavMap.new(8, 5, 8.0, Vector2.ZERO, 1)
	var small_mask := nav_map.register_passability_class(_class_config("small", 0.0, TERRAIN_WATER))
	var large_mask := nav_map.register_passability_class(_class_config("large", 4.0, TERRAIN_WATER))
	nav_map.set_terrain_tile_data(Vector2i(3, 2), TERRAIN_WATER)

	var center_mask := nav_map.get_navcell_data(Vector2i(3, 2)) & (small_mask | large_mask)
	var adjacent_mask := nav_map.get_navcell_data(Vector2i(4, 2)) & (small_mask | large_mask)
	_assert_equal_int(small_mask | large_mask, center_mask, "terrain center should block every matching terrain class")
	_assert_equal_int(large_mask, adjacent_mask, "terrain clearance should block only the large class in adjacent navcell")
	_assert_true(nav_map.is_passable_navcell(Vector2i(4, 2), small_mask), "small class should pass beside blocked terrain")
	_assert_false(nav_map.is_passable_navcell(Vector2i(4, 2), large_mask), "large class should not pass beside blocked terrain")

	nav_map.clear_dirty_navcells()
	nav_map.set_terrain_tile_data(Vector2i(3, 2), 0)
	_assert_true(nav_map.is_passable_navcell(Vector2i(4, 2), large_mask), "clearing terrain should clear clearance-expanded adjacent mask")
	_assert_true(nav_map.is_dirty_navcell(Vector2i(4, 2)), "clearing terrain should dirty clearance-expanded adjacent navcell")


func _test_static_gap_path_depends_on_clearance() -> void:
	# With the +1 navcell raster extension, small (0 + 8) needs a wide gap:
	# wall cells at y 0 and 6 leave a 5-cell gap whose middle row (y = 3) has
	# cell centers 20 px from either blocker edge — small (8) passes, large
	# (18 + 8 = 26) is blocked across the whole column.
	var nav_map := SimNavMap.new(9, 7, 8.0, Vector2.ZERO, 1)
	var small_mask := nav_map.register_passability_class(_class_config("small", 0.0, 0))
	var large_mask := nav_map.register_passability_class(_class_config("large", 18.0, 0))
	for y in [0, 6]:
		_add_static_cell_blocker(nav_map, Vector2i(4, y))
	nav_map.rebuild_dirty()

	_assert_true(_has_long_path(nav_map, small_mask, 3), "small class should pass through wide static gap")
	_assert_false(_has_long_path(nav_map, large_mask, 3), "large class should not pass through wide static gap")


func _test_terrain_gap_path_depends_on_clearance() -> void:
	var nav_map := SimNavMap.new(9, 5, 8.0, Vector2.ZERO, 1)
	var small_mask := nav_map.register_passability_class(_class_config("small", 0.0, TERRAIN_WATER))
	var large_mask := nav_map.register_passability_class(_class_config("large", 4.0, TERRAIN_WATER))
	for y in [0, 1, 3, 4]:
		nav_map.set_terrain_tile_data(Vector2i(4, y), TERRAIN_WATER)

	_assert_true(_has_long_path(nav_map, small_mask), "small class should pass through one-navcell terrain gap")
	_assert_false(_has_long_path(nav_map, large_mask), "large class should not pass through one-navcell terrain gap")


func _has_long_path(nav_map: SimNavMap, pass_mask: int, row: int = 2) -> bool:
	var start := nav_map.navcell_center_world(Vector2i(1, row))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(7, row)))
	var path := SimNavLongPathfinder.new(nav_map).compute_path_immediate(start, goal, pass_mask)
	return not path.is_empty()


func _add_static_cell_blocker(nav_map: SimNavMap, coord: Vector2i) -> void:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = "block_%d_%d" % [coord.x, coord.y]
	shape.center = nav_map.navcell_center_world(coord)
	shape.width = nav_map.navcell_size
	shape.height = nav_map.navcell_size
	shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(shape)


func _class_config(name_id: String, clearance: float, terrain_mask: int) -> SimNavPassabilityClassConfig:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = name_id
	config.clearance = clearance
	config.terrain_mask = terrain_mask
	config.affects_pathfinding = true
	return config


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal_int(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])
