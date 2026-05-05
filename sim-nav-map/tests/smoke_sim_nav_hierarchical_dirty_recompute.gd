extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map hierarchical dirty recompute")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(200, 100, 4.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [ground_mask])
	var dirty_chunk_before := hierarchical.get_chunk(0, 0, ground_mask)
	var clean_chunk_before := hierarchical.get_chunk(1, 0, ground_mask)

	nav_map.or_navcell_data(Vector2i(10, 10), ground_mask)
	var rebuilt_count := hierarchical.recompute_dirty(nav_map, [ground_mask])
	var dirty_chunk_after := hierarchical.get_chunk(0, 0, ground_mask)
	var clean_chunk_after := hierarchical.get_chunk(1, 0, ground_mask)

	_assert_equal(1, rebuilt_count, "one dirty chunk should be rebuilt")
	_assert_false(dirty_chunk_before == dirty_chunk_after, "dirty chunk should be replaced")
	_assert_true(clean_chunk_before == clean_chunk_after, "clean chunk should not be replaced")
	_assert_false(hierarchical.is_navcell_reachable(Vector2i(1, 1), Vector2i(10, 10), ground_mask), "blocked dirty cell should become unreachable")

	nav_map.clear_dirty_navcells()
	rebuilt_count = hierarchical.recompute_dirty(nav_map, [ground_mask])
	_assert_equal(0, rebuilt_count, "clean map should not rebuild chunks")


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
