extends Node


const TERRAIN_WATER: int = 1

var _failures: Array[String] = []


func _ready() -> void:
	_test_lab_adapter_consumes_class_clearance()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab clearance adapter")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_lab_adapter_consumes_class_clearance() -> void:
	var pf := RtsPathfindingLabPathfinder.new(Vector2(72.0, 40.0), 8.0, 4.0)
	var small := _class_config("small", 0.0)
	var large := _class_config("large", 4.0)
	var configs: Array[SimNavPassabilityClassConfig] = [small, large]
	var terrain_tiles := {
		Vector2i(4, 0): TERRAIN_WATER,
		Vector2i(4, 1): TERRAIN_WATER,
		Vector2i(4, 3): TERRAIN_WATER,
		Vector2i(4, 4): TERRAIN_WATER,
	}
	var context := pf.build_terrain_nav_context(terrain_tiles, configs, 1)
	var nav_map := context["nav_map"] as SimNavMap
	var hierarchical := context["hierarchical"] as SimNavHierarchicalPathfinder
	var pass_masks: Dictionary = context["pass_masks"]
	var small_mask := int(pass_masks["small"])
	var large_mask := int(pass_masks["large"])
	var start_cell := Vector2i(1, 2)
	var goal_cell := Vector2i(7, 2)

	_assert_true(nav_map.is_passable_navcell(Vector2i(4, 2), small_mask), "small class should see terrain gap as passable")
	_assert_false(nav_map.is_passable_navcell(Vector2i(4, 2), large_mask), "large class clearance should close terrain gap")
	_assert_true(hierarchical.is_navcell_reachable(start_cell, goal_cell, small_mask), "small class should reach through lab terrain gap")
	_assert_false(hierarchical.is_navcell_reachable(start_cell, goal_cell, large_mask), "large class should not reach through lab terrain gap")

	var start := nav_map.navcell_center_world(start_cell)
	var goal := nav_map.navcell_center_world(goal_cell)
	var small_path := pf.plan_path_with_terrain_context(start, goal, context, "small")
	if small_path.is_empty():
		_failures.append("clearance adapter: expected small class path through terrain gap")


func _class_config(name_id: String, clearance: float) -> SimNavPassabilityClassConfig:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = name_id
	config.clearance = clearance
	config.terrain_mask = TERRAIN_WATER
	config.affects_pathfinding = true
	return config


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)
