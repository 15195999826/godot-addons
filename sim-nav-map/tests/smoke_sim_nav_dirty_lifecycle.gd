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
	_test_facade_dirty_lifecycle_updates_terrain_regions_and_long_cache()
	_test_facade_dirty_lifecycle_updates_static_obstruction_regions_and_long_cache()


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


func _test_facade_dirty_lifecycle_updates_terrain_regions_and_long_cache() -> void:
	var nav_map := SimNavMap.new(120, 8, 8.0, Vector2.ZERO, 1)
	var ground_mask := _register_terrain_ground(nav_map)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	var start := nav_map.navcell_center_world(Vector2i(10, 4))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(110, 4)))
	_assert_false(long_pathfinder.compute_path_immediate(start, goal.clone(), ground_mask).is_empty(), "open terrain path should populate long-path cache")

	for y in range(nav_map.height):
		nav_map.set_terrain_tile_data(Vector2i(60, y), 0x1)
	var dirty_report: Dictionary = facade.recompute_dirty([ground_mask])
	_assert_true(bool(dirty_report.get("invalidated_long_path_cache", false)), "terrain dirty lifecycle should invalidate long-path cache")
	_assert_true(int(dirty_report.get("rebuilt_chunks", 0)) > 0, "terrain dirty lifecycle should rebuild affected hierarchical chunks")
	_assert_false(nav_map.has_dirty_navcells(), "facade dirty lifecycle should clear terrain dirty navcells by default")
	_assert_false(hierarchical.is_navcell_reachable(Vector2i(10, 4), Vector2i(110, 4), ground_mask), "terrain wall should split regions after dirty recompute")
	_assert_true(long_pathfinder.compute_path_immediate(start, goal.clone(), ground_mask).is_empty(), "long path should observe terrain wall after cache invalidation")

	for y in range(nav_map.height):
		nav_map.set_terrain_tile_data(Vector2i(60, y), 0)
	dirty_report = facade.recompute_dirty([ground_mask])
	_assert_true(bool(dirty_report.get("invalidated_long_path_cache", false)), "clearing terrain wall should invalidate long-path cache")
	_assert_true(hierarchical.is_navcell_reachable(Vector2i(10, 4), Vector2i(110, 4), ground_mask), "cleared terrain wall should reconnect regions")
	_assert_false(long_pathfinder.compute_path_immediate(start, goal.clone(), ground_mask).is_empty(), "long path should reopen after terrain dirty lifecycle")


func _test_facade_dirty_lifecycle_updates_static_obstruction_regions_and_long_cache() -> void:
	var nav_map := SimNavMap.new(120, 8, 8.0, Vector2.ZERO, 1)
	var ground_mask := _register_ground(nav_map)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	var manager := SimNavObstructionManager.new(nav_map)
	var start := nav_map.navcell_center_world(Vector2i(10, 4))
	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(110, 4)))
	_assert_false(long_pathfinder.compute_path_immediate(start, goal.clone(), ground_mask).is_empty(), "open static-obstruction path should populate long-path cache")

	var wall_center := Vector2(nav_map.navcell_center_world(Vector2i(60, 0)).x, nav_map.origin.y + float(nav_map.height) * nav_map.navcell_size * 0.5)
	var tag := manager.add_static_shape(
		"static_wall",
		wall_center,
		0.0,
		nav_map.navcell_size,
		float(nav_map.height) * nav_map.navcell_size + nav_map.navcell_size,
		SimNavObstructionFlags.BLOCK_PATHFINDING
	)
	var dirty_report: Dictionary = facade.recompute_dirty([ground_mask])
	_assert_true(int(dirty_report.get("changed_obstruction_navcells", 0)) > 0, "static obstruction dirty lifecycle should rasterize dirty cells")
	_assert_true(bool(dirty_report.get("invalidated_long_path_cache", false)), "static obstruction dirty lifecycle should invalidate long-path cache")
	_assert_false(nav_map.has_dirty_navcells(), "facade dirty lifecycle should clear static obstruction dirty navcells by default")
	_assert_false(hierarchical.is_navcell_reachable(Vector2i(10, 4), Vector2i(110, 4), ground_mask), "static wall should split regions after dirty recompute")
	_assert_true(long_pathfinder.compute_path_immediate(start, goal.clone(), ground_mask).is_empty(), "long path should observe static wall after cache invalidation")

	_assert_true(manager.remove_shape(tag), "static wall should be removable by tag")
	dirty_report = facade.recompute_dirty([ground_mask])
	_assert_true(int(dirty_report.get("changed_obstruction_navcells", 0)) > 0, "static obstruction removal should rerasterize dirty cells")
	_assert_true(hierarchical.is_navcell_reachable(Vector2i(10, 4), Vector2i(110, 4), ground_mask), "removed static wall should reconnect regions")
	_assert_false(long_pathfinder.compute_path_immediate(start, goal.clone(), ground_mask).is_empty(), "long path should reopen after static obstruction dirty lifecycle")


func _register_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	return nav_map.register_passability_class(ground)


func _register_terrain_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	ground.terrain_mask = 0x1
	return nav_map.register_passability_class(ground)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])
