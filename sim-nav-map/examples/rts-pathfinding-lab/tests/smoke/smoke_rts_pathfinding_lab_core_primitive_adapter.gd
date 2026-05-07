extends Node


const LabPathfinder := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_adapter_exposes_line_and_short_metadata()
	_test_adapter_respects_group_filter_metadata()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab core primitive adapter")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_adapter_exposes_line_and_short_metadata() -> void:
	var pf := LabPathfinder.new(Vector2(240.0, 160.0), 8.0, 10.0)
	var units: Array[RtsPathfindingLabUnit] = [
		LabUnit.new("red_blocker", "red", Vector2(120.0, 80.0), 12.0, 95.0, true),
	]
	var report := pf.inspect_core_primitives(Vector2(40.0, 80.0), Vector2(200.0, 80.0), [], units, "blue", true, true)
	if int(report.get("path_size", 0)) <= 0:
		_failures.append("core primitive adapter: expected path")
		return
	var short_report: Dictionary = report.get("short_path_result", {})
	var movement_line: Dictionary = report.get("movement_line_validation", {})
	var unit_line: Dictionary = report.get("unit_line_validation", {})
	_assert_true(short_report.has("status"), "adapter should expose short result status")
	_assert_true(int(short_report.get("path_size", 0)) > 0, "adapter should expose short result path size")
	_assert_equal_str(SimNavMovementLineResult.STATUS_BLOCKED, str(movement_line.get("status", "")), "adapter should expose direct movement-line blockage")
	_assert_equal_str(SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED, str(unit_line.get("failure_reason", "")), "adapter should expose unit-only line blockage")
	_assert_equal_str("red_blocker", str(unit_line.get("blocked_obstruction_entity_id", "")), "adapter should expose blocker identity")


func _test_adapter_respects_group_filter_metadata() -> void:
	var pf := LabPathfinder.new(Vector2(240.0, 160.0), 8.0, 10.0)
	var units: Array[RtsPathfindingLabUnit] = [
		LabUnit.new("blue_friend", "blue", Vector2(120.0, 80.0), 12.0, 95.0, true),
	]
	var report := pf.inspect_core_primitives(Vector2(40.0, 80.0), Vector2(200.0, 80.0), [], units, "blue", true, true)
	if int(report.get("path_size", 0)) <= 0:
		_failures.append("core primitive group adapter: expected path")
		return
	var unit_line: Dictionary = report.get("unit_line_validation", {})
	_assert_equal_str(SimNavMovementLineResult.STATUS_CLEAR, str(unit_line.get("status", "")), "adapter should consume group-filtered unit-line result")
	var short_report: Dictionary = report.get("short_path_result", {})
	_assert_equal_str(SimNavShortPathResult.STATUS_DIRECT_GOAL, str(short_report.get("status", "")), "adapter should consume direct short-path metadata")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])
