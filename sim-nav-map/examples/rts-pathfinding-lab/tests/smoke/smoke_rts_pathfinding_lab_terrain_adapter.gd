extends Node


const TERRAIN_WATER: int = 1

var _failures: Array[String] = []


func _ready() -> void:
	_test_lab_adapter_consumes_terrain_passability()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab terrain adapter")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_lab_adapter_consumes_terrain_passability() -> void:
	var pf := RtsPathfindingLabPathfinder.new(Vector2(96.0, 64.0), 8.0, 4.0)
	var ground := _class_config("ground", TERRAIN_WATER)
	var ship := _class_config("ship", 0)
	var configs: Array[SimNavPassabilityClassConfig] = [ground, ship]
	var terrain_tiles := {
		Vector2i(2, 0): TERRAIN_WATER,
		Vector2i(2, 1): TERRAIN_WATER,
		Vector2i(2, 2): TERRAIN_WATER,
	}
	var context := pf.build_terrain_nav_context(terrain_tiles, configs, 2)
	var nav_map := context["nav_map"] as SimNavMap
	var pass_masks: Dictionary = context["pass_masks"]
	var ground_mask := int(pass_masks["ground"])
	var ship_mask := int(pass_masks["ship"])
	var blocked_cell := Vector2i(4, 3)
	_assert_false(nav_map.is_passable_navcell(blocked_cell, ground_mask), "terrain preset should block ground class")
	_assert_true(nav_map.is_passable_navcell(blocked_cell, ship_mask), "same terrain preset should allow ship class")

	var start := nav_map.navcell_center_world(Vector2i(1, 3))
	var goal := nav_map.navcell_center_world(Vector2i(10, 3))
	var ground_path := pf.plan_path_with_terrain_context(start, goal, context, "ground")
	var ship_path := pf.plan_path_with_terrain_context(start, goal, context, "ship")
	if ground_path.is_empty():
		_failures.append("terrain adapter: expected ground path through terrain gap")
	if ship_path.is_empty():
		_failures.append("terrain adapter: expected ship path across water terrain")
	if not ground_path.is_empty() and not ship_path.is_empty() and ground_path.size() <= ship_path.size():
		_failures.append("terrain adapter: expected ground detour to have more waypoints than ship path")


func _class_config(name_id: String, terrain_mask: int) -> SimNavPassabilityClassConfig:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = name_id
	config.terrain_mask = terrain_mask
	config.affects_pathfinding = true
	return config


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)
