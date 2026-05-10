extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map diagnostics exports")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_dirtiness_and_connectivity_exports()
	_test_scale_diagnostics_scenario_shape()


func _test_dirtiness_and_connectivity_exports() -> void:
	var nav_map := SimNavMap.new(24, 16, 8.0, Vector2.ZERO, 1)
	var pass_mask := _register_ground(nav_map)
	var static_shape := SimNavObstructionShapeStatic.new()
	static_shape.entity_id = "wall"
	static_shape.center = nav_map.navcell_center_world(Vector2i(5, 5))
	static_shape.width = 16.0
	static_shape.height = 16.0
	static_shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(static_shape)
	var pre_raster_dirty := nav_map.get_dirtiness_snapshot()
	_assert_true(int(pre_raster_dirty.get("dirty_obstruction_navcell_count", 0)) > 0, "dirtiness export should expose obstruction dirty cells")
	nav_map.rasterize_dirty_obstructions()
	var map_diagnostics := nav_map.get_diagnostics()
	_assert_equal(24, int(map_diagnostics.get("width", 0)), "map diagnostics should expose width")
	_assert_equal(1, int(map_diagnostics.get("static_obstruction_count", 0)), "map diagnostics should expose static obstruction count")
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [pass_mask])
	var connectivity := hierarchical.export_connectivity(pass_mask, "ground")
	var regions: PackedInt32Array = connectivity.get("regions", PackedInt32Array()) as PackedInt32Array
	_assert_equal(nav_map.width * nav_map.height, regions.size(), "connectivity export should snapshot all navcells")
	_assert_true(int(connectivity.get("global_region_count", 0)) > 0, "connectivity export should expose global regions")
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, SimNavLongPathfinder.new(nav_map))
	var diagnostics := facade.get_navigation_diagnostics([pass_mask])
	_assert_true(diagnostics.has("map"), "facade diagnostics should include map snapshot")
	_assert_true(diagnostics.has("hierarchical"), "facade diagnostics should include hierarchical snapshot")


func _test_scale_diagnostics_scenario_shape() -> void:
	var nav_map := SimNavMap.new(64, 64, 4.0, Vector2.ZERO, 1)
	var pass_mask := _register_ground(nav_map)
	for y in range(8, 56):
		if y == 32:
			continue
		nav_map.or_navcell_data(Vector2i(30, y), pass_mask)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	var start_usec := Time.get_ticks_usec()
	hierarchical.recompute(nav_map, [pass_mask])
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var query := SimNavLongPathQuery.from_values(
		nav_map.navcell_center_world(Vector2i(4, 32)),
		SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(58, 32))),
		pass_mask,
		"ground"
	)
	var result := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder).compute_path_result(query)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	_assert_true(result.is_success(), "scale diagnostics scenario should keep correctness smoke green")
	_assert_true(elapsed_usec >= 0, "scale diagnostics scenario should record elapsed time without threshold gating")
	var connectivity := hierarchical.export_connectivity(pass_mask, "ground")
	_assert_equal(64 * 64, (connectivity.get("regions", PackedInt32Array()) as PackedInt32Array).size(), "scale connectivity export should preserve shape")


func _register_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	return nav_map.register_passability_class(ground)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])
