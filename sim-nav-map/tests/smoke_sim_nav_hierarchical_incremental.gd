extends Node

# Equality weld for hierarchical dirty recompute after the windowed chunk
# rebuild: recompute_dirty() must leave the per-cell global-region export
# byte-identical to a from-scratch recompute() on the same map, across edit
# rounds that split and rejoin regions, cross chunk borders, and touch map
# edges. (Region numbering is deterministic in both paths, so full equality
# — not just partition equivalence — is the contract.)


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map hierarchical incremental recompute")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	# 3x2 chunks (96-cell chunks): exercises borders and multi-chunk dirt.
	var nav_map := SimNavMap.new(200, 150, 8.0, Vector2.ZERO, 4)
	var mask := _register_ground(nav_map)
	for x in range(60, 80):
		nav_map.or_navcell_data(Vector2i(x, 40), mask)
	nav_map.clear_dirty_navcells()

	var incremental := SimNavHierarchicalPathfinder.new()
	incremental.recompute(nav_map, [mask])
	_assert_equal_connectivity(incremental, nav_map, mask, "baseline")

	# Round 1: full-height wall — splits the map into two global regions.
	for y in range(0, 150):
		nav_map.or_navcell_data(Vector2i(100, y), mask)
	_recompute_and_compare(incremental, nav_map, mask, "split wall")
	var split_regions := incremental.next_global_region(mask) - 1
	_assert_true(split_regions >= 2, "split wall should create at least two global regions")

	# Round 2: gap opens in the wall — regions rejoin.
	nav_map.and_navcell_data(Vector2i(100, 75), mask)
	_recompute_and_compare(incremental, nav_map, mask, "wall gap rejoin")

	# Round 3: chunk-border-crossing fissure (cells straddle ci=0/1 boundary).
	for x in range(90, 104):
		nav_map.or_navcell_data(Vector2i(x, 120), mask)
	_recompute_and_compare(incremental, nav_map, mask, "border-crossing fissure")

	# Round 4: map-edge and corner edits.
	for cell in [Vector2i(0, 0), Vector2i(199, 149), Vector2i(0, 149), Vector2i(199, 0), Vector2i(97, 0)]:
		nav_map.or_navcell_data(cell, mask)
	_recompute_and_compare(incremental, nav_map, mask, "map edges")

	# Round 5: fissure expiry (round 3 cells cleared).
	for x in range(90, 104):
		nav_map.and_navcell_data(Vector2i(x, 120), mask)
	_recompute_and_compare(incremental, nav_map, mask, "fissure expiry")

	_test_multi_mask_and_full_recompute_fallbacks()


# Coverage for the two full-recompute fallbacks inside recompute_dirty
# (fresh pathfinder / mask missing from a previous recompute) and for
# multi-mask incremental rounds where an edit only affects one class.
func _test_multi_mask_and_full_recompute_fallbacks() -> void:
	var nav_map := SimNavMap.new(120, 100, 8.0, Vector2.ZERO, 4)
	var ground_mask := _register_class(nav_map, "ground")
	var air_mask := _register_class(nav_map, "air")
	for x in range(20, 90):
		nav_map.or_navcell_data(Vector2i(x, 50), ground_mask)
	nav_map.clear_dirty_navcells()

	# Fresh pathfinder straight into recompute_dirty: not-recomputed fallback.
	var fresh := SimNavHierarchicalPathfinder.new()
	var rebuilt := fresh.recompute_dirty(nav_map, [ground_mask, air_mask])
	_assert_true(rebuilt > 0, "fresh recompute_dirty should fall back to a full recompute")
	_assert_equal_connectivity_masks(fresh, nav_map, [ground_mask, air_mask], "fresh fallback")

	# Mask missing from the previous recompute: missing-mask fallback.
	var partial := SimNavHierarchicalPathfinder.new()
	partial.recompute(nav_map, [ground_mask])
	nav_map.or_navcell_data(Vector2i(30, 30), ground_mask)
	var rebuilt_partial := partial.recompute_dirty(nav_map, [ground_mask, air_mask])
	nav_map.clear_dirty_navcells()
	_assert_true(rebuilt_partial > 0, "missing-mask recompute_dirty should fall back to a full recompute")
	_assert_equal_connectivity_masks(partial, nav_map, [ground_mask, air_mask], "missing-mask fallback")

	# Multi-mask incremental round: the edit only blocks ground; both masks
	# must stay welded to their full recomputes.
	nav_map.or_navcell_data(Vector2i(60, 70), ground_mask)
	partial.recompute_dirty(nav_map, [ground_mask, air_mask])
	nav_map.clear_dirty_navcells()
	_assert_equal_connectivity_masks(partial, nav_map, [ground_mask, air_mask], "multi-mask incremental")


func _recompute_and_compare(
	incremental: SimNavHierarchicalPathfinder,
	nav_map: SimNavMap,
	mask: int,
	label: String
) -> void:
	var rebuilt := incremental.recompute_dirty(nav_map, [mask])
	nav_map.clear_dirty_navcells()
	_assert_true(rebuilt > 0, "%s: dirty recompute should rebuild at least one chunk" % label)
	_assert_equal_connectivity(incremental, nav_map, mask, label)


func _assert_equal_connectivity(
	incremental: SimNavHierarchicalPathfinder,
	nav_map: SimNavMap,
	mask: int,
	label: String
) -> void:
	var truth := SimNavHierarchicalPathfinder.new()
	truth.recompute(nav_map, [mask])
	var incremental_export := incremental.export_connectivity(mask)
	var truth_export := truth.export_connectivity(mask)
	if incremental_export["regions"] != truth_export["regions"]:
		_failures.append("%s: incremental global-region export differs from full recompute" % label)
	if int(incremental_export["global_region_count"]) != int(truth_export["global_region_count"]):
		_failures.append("%s: global region count differs (%d vs %d)" % [
			label, int(incremental_export["global_region_count"]), int(truth_export["global_region_count"])])


func _assert_equal_connectivity_masks(
	incremental: SimNavHierarchicalPathfinder,
	nav_map: SimNavMap,
	masks: Array,
	label: String
) -> void:
	var truth := SimNavHierarchicalPathfinder.new()
	var typed_masks: Array[int] = []
	for mask_value in masks:
		typed_masks.append(int(mask_value))
	truth.recompute(nav_map, typed_masks)
	for mask_value in masks:
		var mask := int(mask_value)
		var incremental_export := incremental.export_connectivity(mask)
		var truth_export := truth.export_connectivity(mask)
		if incremental_export["regions"] != truth_export["regions"]:
			_failures.append("%s: mask %d export differs from full recompute" % [label, mask])


func _register_ground(nav_map: SimNavMap) -> int:
	return _register_class(nav_map, "ground")


func _register_class(nav_map: SimNavMap, class_id: String) -> int:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = class_id
	config.clearance = 0.0
	config.affects_pathfinding = true
	return nav_map.register_passability_class(config)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
