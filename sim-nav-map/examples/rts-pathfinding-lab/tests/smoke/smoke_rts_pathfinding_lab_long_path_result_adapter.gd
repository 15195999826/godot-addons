extends Node


const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_grid_fallback_exposes_long_path_metadata()
	_test_terrain_adapter_exposes_canonicalized_result()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab long path result adapter")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_grid_fallback_exposes_long_path_metadata() -> void:
	var pf := LabPathfinder.new(Vector2(640.0, 360.0), 16.0, 12.0)
	var obstacles: Array[RtsPathfindingLabObstacle] = [
		LabObstacle.new("top_a", Vector2(160.0, 40.0), Vector2(32.0, 32.0)),
		LabObstacle.new("top_b", Vector2(260.0, 40.0), Vector2(32.0, 32.0)),
		LabObstacle.new("bottom_a", Vector2(360.0, 320.0), Vector2(32.0, 32.0)),
		LabObstacle.new("bottom_b", Vector2(460.0, 320.0), Vector2(32.0, 32.0)),
	]
	var units: Array[RtsPathfindingLabUnit] = []
	var path := pf.plan_path(Vector2(80.0, 180.0), Vector2(560.0, 180.0), obstacles, units, "blue", true, true)
	if path.is_empty():
		_failures.append("grid fallback adapter: expected path")
		return
	if not bool(pf.last_report.get("used_grid_fallback", false)):
		_failures.append("grid fallback adapter: expected grid fallback branch")
		return
	var long_report: Dictionary = pf.last_report.get("long_path_result", {})
	_assert_equal_str(SimNavLongPathResult.STATUS_SUCCESS, str(long_report.get("status", "")), "grid fallback adapter should expose success status")
	_assert_true(float(long_report.get("path_length", 0.0)) > 0.0, "grid fallback adapter should expose path length")
	_assert_true(int(long_report.get("path_cost", 0)) > 0, "grid fallback adapter should expose path cost")
	_assert_true(int(long_report.get("raw_navcell_count", 0)) >= int(long_report.get("refined_waypoint_count", 0)), "grid fallback adapter should expose raw/refined counts")
	_assert_equal_str(SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, str(long_report.get("post_process", "")), "grid fallback adapter should expose core post-process preference")


func _test_terrain_adapter_exposes_canonicalized_result() -> void:
	var pf := LabPathfinder.new(Vector2(96.0, 48.0), 8.0, 4.0)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.terrain_mask = 0x1
	ground.affects_pathfinding = true
	var terrain_tiles := {}
	for y in range(6):
		terrain_tiles[Vector2i(5, y)] = 0x1
	var context := pf.build_terrain_nav_context(terrain_tiles, [ground], 1)
	var nav_map: SimNavMap = context["nav_map"]
	var start := nav_map.navcell_center_world(Vector2i(1, 3))
	var goal := nav_map.navcell_center_world(Vector2i(10, 3))
	var path := pf.plan_path_with_terrain_context(start, goal, context, "ground")
	if path.is_empty():
		_failures.append("terrain adapter: expected canonicalized fallback path")
		return
	var long_report: Dictionary = pf.last_report.get("long_path_result", {})
	_assert_equal_str(SimNavLongPathResult.STATUS_CANONICALIZED, str(long_report.get("status", "")), "terrain adapter should expose canonicalized status")
	_assert_true(bool(long_report.get("canonicalized", false)), "terrain adapter should expose canonicalized metadata")
	_assert_equal_str(SimNavReachabilityResult.FAILURE_ORIGINAL_GOAL_UNREACHABLE, str(long_report.get("canonicalization_reason", "")), "terrain adapter should expose canonicalization reason")
	_assert_true(int(long_report.get("raw_waypoint_count", 0)) > 0, "terrain adapter should expose raw waypoint count")
	_assert_true(float(long_report.get("path_length", 0.0)) > 0.0, "terrain adapter should expose canonicalized path length")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])
