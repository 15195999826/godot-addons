extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map jump point cache")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_goal_overrides_cached_obstruction()
	_test_cardinal_forced_jump_is_cached()


func _test_goal_overrides_cached_obstruction() -> void:
	var nav_map := SimNavMap.new(8, 3, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	nav_map.or_navcell_data(Vector2i(5, 1), ground_mask)
	var cache := SimNavJumpPointCache.new()
	cache.reset(nav_map, ground_mask)

	var blocked_behind_goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 1)))
	var hit := cache.find(Vector2i(1, 1), Vector2i(1, 0), blocked_behind_goal)
	_assert_equal(SimNavJumpPointHit.Kind.OBSTRUCTION, hit.kind, "goal behind obstruction should return obstruction hit")
	_assert_equal_vec(Vector2i(5, 1), hit.cell, "obstruction cell should be cached")
	_assert_equal(1, cache.cached_entry_count(), "first query should cache obstruction/boundary hit")

	var reachable_goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1)))
	hit = cache.find(Vector2i(1, 1), Vector2i(1, 0), reachable_goal)
	_assert_equal(SimNavJumpPointHit.Kind.GOAL, hit.kind, "goal before obstruction should override cached obstruction hit")
	_assert_equal_vec(Vector2i(4, 1), hit.cell, "goal hit cell should be returned")
	_assert_equal(1, cache.cached_entry_count(), "goal query should reuse obstruction/boundary cache")

	nav_map.and_navcell_data(Vector2i(5, 1), ground_mask)
	_assert_true(cache.invalidate_dirty_navcells(nav_map), "dirty navcell should invalidate jump point cache")
	_assert_true(cache.is_dirty(), "cache should be marked dirty")
	cache.reset(nav_map, ground_mask)
	hit = cache.find(Vector2i(1, 1), Vector2i(1, 0), blocked_behind_goal)
	_assert_equal(SimNavJumpPointHit.Kind.GOAL, hit.kind, "opened row should reach former behind-obstruction goal")


func _test_cardinal_forced_jump_is_cached() -> void:
	var nav_map := SimNavMap.new(8, 5, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_ground(nav_map)
	nav_map.or_navcell_data(Vector2i(1, 1), ground_mask)
	var cache := SimNavJumpPointCache.new()
	cache.reset(nav_map, ground_mask)

	var distant_goal := SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 2)))
	var hit := cache.find(Vector2i(1, 2), Vector2i(1, 0), distant_goal)
	_assert_equal(SimNavJumpPointHit.Kind.JUMP, hit.kind, "blocked predecessor side should produce a cardinal forced jump")
	_assert_equal_vec(Vector2i(2, 2), hit.cell, "forced jump cell should be cached before distant goal")
	_assert_equal(1, cache.cached_entry_count(), "forced jump query should cache one entry")


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


func _assert_equal_vec(expected: Vector2i, actual: Vector2i, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
