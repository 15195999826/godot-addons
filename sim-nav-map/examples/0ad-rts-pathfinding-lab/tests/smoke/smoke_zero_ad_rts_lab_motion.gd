extends Node


const LabObstacleScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_obstacle.gd")
const LabUnitScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_unit.gd")
const LabWorldScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_world.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_movement_line_blocks_static_crossing()
	_test_unit_line_blockage_requests_short_path()
	_test_push_adjust_does_not_cross_static_wall()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - 0ad rts lab motion")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_movement_line_blocks_static_crossing() -> void:
	var world: Variant = LabWorldScript.new()
	var unit: Variant = world.get_unit("blue_0")
	if unit == null:
		_failures.append("static-crossing: missing blue_0")
		return
	var line_result: SimNavMovementLineResult = world.pathfinder.validate_movement_line(
		unit,
		Vector2(300.0, 210.0),
		Vector2(420.0, 210.0),
		world.units
	)
	_assert_equal_str(SimNavMovementLineResult.STATUS_BLOCKED, line_result.status, "static-crossing should be blocked")
	_assert_equal_str(SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED, line_result.failure_reason, "static-crossing should fail by passability")


func _test_unit_line_blockage_requests_short_path() -> void:
	var world: Variant = LabWorldScript.new()
	world.obstacles = []
	world.units = [
		LabUnitScript.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 80.0, true),
		LabUnitScript.new("red_blocker", "red", Vector2(120.0, 80.0), 12.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_0", Vector2(200.0, 80.0))
	var pre_line: SimNavMovementLineResult = world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units
	)
	if not pre_line.is_success() and pre_line.failure_reason != SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED:
		_failures.append("unit-line: unexpected line failure %s" % pre_line.failure_reason)
	for _i in range(40):
		world.step(0.1)
		if world.motion.short_path_requests > 0:
			break
	var unit: Variant = world.get_unit("blue_0")
	if unit == null:
		_failures.append("unit-line: missing blue_0")
		return
	if world.motion.short_path_requests <= 0:
		_failures.append("unit-line: expected short-path request, long_path=%d line=%s/%s report=%s" % [
			unit.long_path.size() if unit != null and unit.long_path != null else -1,
			pre_line.status,
			pre_line.failure_reason,
			str(world.pathfinder.last_report),
		])
	if unit.short_path == null or unit.short_path.is_empty():
		_failures.append("unit-line: expected active short path")


func _test_push_adjust_does_not_cross_static_wall() -> void:
	var world: Variant = LabWorldScript.new()
	world.obstacles = [
		LabObstacleScript.new("thin_wall", Vector2(96.0, 80.0), Vector2(12.0, 120.0)),
	]
	world.units = [
		LabUnitScript.new("blue_0", "blue", Vector2(78.0, 80.0), 10.0, 0.0, true),
		LabUnitScript.new("blue_1", "blue", Vector2(78.5, 80.0), 10.0, 0.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	for unit in world.units:
		unit.has_move_order = true
	world.motion.apply_push_adjust(world.units, world.pathfinder)
	for unit in world.units:
		if world.pathfinder.point_inside_static(unit.position, unit.radius):
			_failures.append("push-wall: unit entered static obstacle")
	if world.motion.rejected_pushes <= 0:
		_failures.append("push-wall: expected at least one rejected push")


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])
