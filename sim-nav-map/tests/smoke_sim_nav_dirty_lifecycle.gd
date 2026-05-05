extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map dirty lifecycle")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_direct_navcell_writes_mark_dirty_only_on_change()
	_test_full_rasterize_marks_changed_old_and_new_cells()
	_test_dirty_rasterize_preserves_base_navcell_data()


func _test_direct_navcell_writes_mark_dirty_only_on_change() -> void:
	var nav_map := SimNavMap.new(4, 4, 8.0, Vector2.ZERO, 1)
	_assert_false(nav_map.has_dirty_navcells(), "new map should start clean")

	nav_map.set_navcell_data(Vector2i(1, 1), 0)
	_assert_false(nav_map.has_dirty_navcells(), "same-value set should not mark dirty")

	nav_map.or_navcell_data(Vector2i(1, 1), 0x1)
	_assert_true(nav_map.is_dirty_navcell(Vector2i(1, 1)), "or_data value change should mark cell dirty")
	_assert_equal(1, nav_map.collect_dirty_navcells().size(), "single write should mark one cell")

	nav_map.clear_dirty_navcells()
	_assert_false(nav_map.has_dirty_navcells(), "clear_dirty_navcells should reset dirtiness")
	nav_map.or_navcell_data(Vector2i(1, 1), 0x1)
	_assert_false(nav_map.has_dirty_navcells(), "same-value or_data should not mark dirty")

	nav_map.and_navcell_data(Vector2i(1, 1), 0x1)
	_assert_true(nav_map.is_dirty_navcell(Vector2i(1, 1)), "and_data value change should mark cell dirty")


func _test_full_rasterize_marks_changed_old_and_new_cells() -> void:
	var nav_map := SimNavMap.new(12, 12, 8.0, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var ground_mask := nav_map.register_passability_class(ground)
	var manager := SimNavObstructionManager.new(nav_map)
	var tag := manager.add_static_shape(
		"block",
		nav_map.navcell_center_world(Vector2i(3, 3)),
		0.0,
		8.0,
		8.0,
		SimNavObstructionFlags.BLOCK_PATHFINDING
	)

	manager.rasterize()
	_assert_false(nav_map.is_passable_navcell(Vector2i(3, 3), ground_mask), "initial rasterize should block first cell")
	_assert_true(nav_map.is_dirty_navcell(Vector2i(3, 3)), "initial rasterize should mark blocked cell dirty")

	nav_map.clear_dirty_navcells()
	manager.rasterize()
	_assert_false(nav_map.has_dirty_navcells(), "unchanged rasterize should not mark cells dirty")

	manager.move_shape(tag, nav_map.navcell_center_world(Vector2i(6, 3)))
	manager.rasterize()
	_assert_true(nav_map.is_passable_navcell(Vector2i(3, 3), ground_mask), "moved rasterize should clear old cell")
	_assert_false(nav_map.is_passable_navcell(Vector2i(6, 3), ground_mask), "moved rasterize should block new cell")
	_assert_true(nav_map.is_dirty_navcell(Vector2i(3, 3)), "moved rasterize should mark old cell dirty")
	_assert_true(nav_map.is_dirty_navcell(Vector2i(6, 3)), "moved rasterize should mark new cell dirty")


func _test_dirty_rasterize_preserves_base_navcell_data() -> void:
	var nav_map := SimNavMap.new(12, 12, 8.0, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var ground_mask := nav_map.register_passability_class(ground)
	var manager := SimNavObstructionManager.new(nav_map)
	var static_tag := manager.add_static_shape(
		"block",
		nav_map.navcell_center_world(Vector2i(3, 3)),
		0.0,
		8.0,
		8.0,
		SimNavObstructionFlags.BLOCK_PATHFINDING
	)

	nav_map.or_navcell_data(Vector2i(9, 9), ground_mask)
	manager.rasterize()
	_assert_false(nav_map.is_passable_navcell(Vector2i(3, 3), ground_mask), "static cell should be blocked")
	_assert_false(nav_map.is_passable_navcell(Vector2i(9, 9), ground_mask), "base blocked terrain should stay blocked")

	nav_map.clear_dirty_navcells()
	manager.move_shape(static_tag, nav_map.navcell_center_world(Vector2i(4, 3)))
	manager.rasterize()
	_assert_true(nav_map.is_passable_navcell(Vector2i(3, 3), ground_mask), "old static cell should clear after dirty rasterize")
	_assert_false(nav_map.is_passable_navcell(Vector2i(4, 3), ground_mask), "new static cell should be blocked")
	_assert_false(nav_map.is_passable_navcell(Vector2i(9, 9), ground_mask), "base terrain should not be cleared by dirty rasterize")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])
