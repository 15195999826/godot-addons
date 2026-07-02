extends Node

# Equality weld for incremental jump-table repair: after any set of navcell
# mutations, repair_dirty_cells() must leave the baked grid and all four ray
# tables byte-identical to a from-scratch reset() on the same map — and the
# repair path (not the full-reset fallback) must actually be the one taken
# for fissure-scale edits. Also checks the facade dirty-flush wiring end to
# end: a repaired pathfinder must plan exactly like a freshly built one.


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map jump table repair")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_repair_matches_full_rebuild_across_edit_rounds()
	_test_mass_edit_falls_back_to_full_reset()
	_test_facade_flush_repairs_and_replans_like_fresh()
	_test_query_side_dirty_handling()


func _test_repair_matches_full_rebuild_across_edit_rounds() -> void:
	var nav_map := SimNavMap.new(32, 20, 8.0, Vector2.ZERO, 4)
	var mask := _register_ground(nav_map)
	# Static baseline: a wall stub and a lone block to seed forced neighbors.
	for cell in [Vector2i(10, 6), Vector2i(10, 7), Vector2i(10, 8), Vector2i(20, 12)]:
		nav_map.or_navcell_data(cell, mask)
	nav_map.clear_dirty_navcells()

	var repaired := SimNavJumpPointCache.new()
	repaired.reset(nav_map, mask)

	var rounds: Array = [
		# L-shaped fissure mid-map.
		{"or": [
			Vector2i(14, 4), Vector2i(14, 5), Vector2i(14, 6), Vector2i(14, 7),
			Vector2i(14, 8), Vector2i(15, 8), Vector2i(16, 8), Vector2i(17, 8),
		], "and": []},
		# Fissure partially expires.
		{"or": [], "and": [Vector2i(14, 6), Vector2i(14, 7), Vector2i(15, 8)]},
		# Map-edge and corner edits (boundary rows/cols of every table).
		{"or": [Vector2i(0, 0), Vector2i(31, 19), Vector2i(5, 0), Vector2i(0, 12), Vector2i(31, 3)], "and": []},
		# Churn next to the baseline wall: forced-neighbor status flips.
		{"or": [Vector2i(9, 6), Vector2i(11, 8)], "and": [Vector2i(10, 7), Vector2i(0, 0)]},
	]
	for round_index in range(rounds.size()):
		var round_edits: Dictionary = rounds[round_index]
		for cell in round_edits["or"]:
			nav_map.or_navcell_data(cell as Vector2i, mask)
		for cell in round_edits["and"]:
			nav_map.and_navcell_data(cell as Vector2i, mask)
		var repairs_before := repaired.repair_count
		repaired.repair_dirty_cells(nav_map.collect_dirty_navcells())
		nav_map.clear_dirty_navcells()
		_assert_true(
			repaired.repair_count == repairs_before + 1,
			"round %d should take the repair path" % round_index
		)
		var truth := SimNavJumpPointCache.new()
		truth.reset(nav_map, mask)
		_assert_true(
			repaired.tables_equal(truth),
			"round %d: repaired tables should equal a full rebuild" % round_index
		)


func _test_mass_edit_falls_back_to_full_reset() -> void:
	var nav_map := SimNavMap.new(24, 16, 8.0, Vector2.ZERO, 4)
	var mask := _register_ground(nav_map)
	nav_map.clear_dirty_navcells()
	var cache := SimNavJumpPointCache.new()
	cache.reset(nav_map, mask)
	var resets_before := cache.full_reset_count
	# Dirty most of the grid: affected band cost exceeds the repair threshold.
	for y in range(2, 14):
		for x in range(2, 22):
			nav_map.or_navcell_data(Vector2i(x, y), mask if (x + y) % 3 == 0 else 0)
	cache.repair_dirty_cells(nav_map.collect_dirty_navcells())
	nav_map.clear_dirty_navcells()
	_assert_true(cache.full_reset_count == resets_before + 1, "mass edit should fall back to a full reset")
	var truth := SimNavJumpPointCache.new()
	truth.reset(nav_map, mask)
	_assert_true(cache.tables_equal(truth), "fallback reset should equal a full rebuild")


func _test_facade_flush_repairs_and_replans_like_fresh() -> void:
	var nav_map := SimNavMap.new(40, 12, 8.0, Vector2.ZERO, 4)
	var mask := _register_ground(nav_map)
	nav_map.clear_dirty_navcells()
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	long_pathfinder.prewarm_jump_point_cache(mask)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [mask])
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)

	var start := nav_map.navcell_center_world(Vector2i(2, 6))
	var goal_cell := Vector2i(37, 6)
	var before := long_pathfinder.compute_path_result(_point_query(nav_map, goal_cell, start, mask))
	_assert_true(before.is_success(), "baseline plan should succeed")

	# A wall drops across the corridor mid-session (fissure analog).
	for y in range(1, 11):
		nav_map.or_navcell_data(Vector2i(20, y), mask)
	var report := facade.recompute_dirty([mask])
	_assert_true(bool(report.get("invalidated_long_path_cache", false)), "flush should refresh the long-path cache")
	_assert_true(not nav_map.has_dirty_navcells(), "flush should clear dirty flags")

	var repaired_result := long_pathfinder.compute_path_result(_point_query(nav_map, goal_cell, start, mask))
	var fresh_pathfinder := SimNavLongPathfinder.new(nav_map)
	var fresh_result := fresh_pathfinder.compute_path_result(_point_query(nav_map, goal_cell, start, mask))
	_assert_true(repaired_result.is_success(), "post-wall plan should still find the gap route")
	_assert_true(
		repaired_result.raw_navcell_path == fresh_result.raw_navcell_path,
		"repaired pathfinder should plan exactly like a freshly built one"
	)
	_assert_true(
		repaired_result.raw_navcell_path != before.raw_navcell_path,
		"the new wall should actually change the route"
	)


# Query-side dirty handling without a facade flush: a fresh cache build must
# not pay a redundant repair, repeat touches of an UNCHANGED dirty set must
# not re-repair (dirty-revision guard — this path runs per tick per moving
# unit via movement_raster_clear), new dirt repairs exactly once, and clean
# maps touch nothing.
func _test_query_side_dirty_handling() -> void:
	var nav_map := SimNavMap.new(24, 12, 8.0, Vector2.ZERO, 4)
	var mask := _register_ground(nav_map)
	nav_map.clear_dirty_navcells()
	nav_map.or_navcell_data(Vector2i(10, 5), mask)
	var pathfinder := SimNavLongPathfinder.new(nav_map)
	var cache: SimNavJumpPointCache = pathfinder._jump_point_cache(mask)
	_assert_true(
		cache.full_reset_count == 1 and cache.repair_count == 0,
		"fresh build with dirty flags should pay one reset and no redundant repair"
	)
	var cache_again: SimNavJumpPointCache = pathfinder._jump_point_cache(mask)
	_assert_true(cache_again == cache, "cache instance should be reused per pass mask")
	_assert_true(
		cache.repair_count == 0,
		"repeat touch of the dirty set the fresh build already covers should not repair"
	)
	nav_map.or_navcell_data(Vector2i(4, 4), mask)
	pathfinder._jump_point_cache(mask)
	pathfinder._jump_point_cache(mask)
	_assert_true(
		cache.repair_count == 1,
		"new dirt should repair exactly once across repeat touches"
	)
	var truth := SimNavJumpPointCache.new()
	truth.reset(nav_map, mask)
	_assert_true(cache.tables_equal(truth), "query-side repair should equal a full rebuild")
	nav_map.clear_dirty_navcells()
	pathfinder._jump_point_cache(mask)
	_assert_true(
		cache.repair_count == 1 and cache.full_reset_count == 1,
		"clean map touches should neither repair nor reset"
	)


func _point_query(nav_map: SimNavMap, goal_cell: Vector2i, start: Vector2, mask: int) -> SimNavLongPathQuery:
	return SimNavLongPathQuery.from_values(
		start,
		SimNavPathGoal.point(nav_map.navcell_center_world(goal_cell)),
		mask,
		"ground"
	)


func _register_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	return nav_map.register_passability_class(ground)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
