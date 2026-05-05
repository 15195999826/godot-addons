extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map hierarchical reachability")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_wall_split_and_goal_canonicalization()
	_test_isolated_region_gets_global_id()


func _test_wall_split_and_goal_canonicalization() -> void:
	var nav_map := SimNavMap.new(120, 12, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(nav_map.height):
		nav_map.or_navcell_data(Vector2i(60, y), ground_mask)

	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])

	_assert_true(
		hierarchical.is_navcell_reachable(Vector2i(10, 4), Vector2i(20, 4), ground_mask),
		"same-side navcells should be reachable"
	)
	_assert_false(
		hierarchical.is_navcell_reachable(Vector2i(10, 4), Vector2i(100, 4), ground_mask),
		"wall split should make opposite side unreachable"
	)

	var canonical := hierarchical.make_goal_reachable_navcell(Vector2i(10, 4), Vector2i(100, 4), ground_mask)
	_assert_true(canonical.x < 60, "canonicalized goal should stay on start side of wall")
	_assert_true(nav_map.is_passable_navcell(canonical, ground_mask), "canonicalized goal should be passable")
	_assert_true(
		hierarchical.is_navcell_reachable(Vector2i(10, 4), canonical, ground_mask),
		"canonicalized goal should be reachable from start"
	)


func _test_isolated_region_gets_global_id() -> void:
	var nav_map := SimNavMap.new(8, 8, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	for y in range(nav_map.height):
		for x in range(nav_map.width):
			nav_map.or_navcell_data(Vector2i(x, y), ground_mask)
	nav_map.and_navcell_data(Vector2i(3, 3), ground_mask)

	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])

	var isolated_global := hierarchical.get_global_region(Vector2i(3, 3), ground_mask)
	_assert_true(isolated_global != 0, "isolated passable region should get a global region id")
	_assert_equal(2, hierarchical.next_global_region(ground_mask), "isolated map should allocate one global region")


func _register_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
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
