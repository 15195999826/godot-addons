extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_test_movement_line_blocks_static_crossing()
	_test_unit_line_blockage_requests_short_path()
	_test_push_adjust_does_not_cross_static_wall()
	_test_user_reported_repath_loop_converges()
	_test_blocker_contact_oscillation_converges()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - 0ad rts lab motion")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_movement_line_blocks_static_crossing() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var unit := world.get_unit("blue_0")
	if unit == null:
		_failures.append("static-crossing: missing blue_0")
		return
	var line_result := world.pathfinder.validate_movement_line(
		unit,
		Vector2(300.0, 210.0),
		Vector2(420.0, 210.0),
		world.units
	)
	_assert_equal_str(SimNavMovementLineResult.STATUS_BLOCKED, line_result.status, "static-crossing should be blocked")
	_assert_equal_str(SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED, line_result.failure_reason, "static-crossing should fail by passability")


func _test_unit_line_blockage_requests_short_path() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 80.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(120.0, 80.0), 12.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_0", Vector2(200.0, 80.0))
	var pre_line := world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units
	)
	if not pre_line.is_success() and pre_line.failure_reason != SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED:
		_failures.append("unit-line: unexpected line failure %s" % pre_line.failure_reason)
	var unit := world.get_unit("blue_0")
	for _i in range(80):
		world.step(0.1)
		if unit != null and unit.short_path != null and not unit.short_path.is_empty():
			break
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
		_failures.append("unit-line: expected active short path, pending=%d applied=%d failures=%d queue=%s" % [
			unit.pending_short_ticket,
			world.motion.path_results_applied,
			world.motion.path_result_failures,
			str(world.pathfinder.path_queue_diagnostics()),
		])


func _test_push_adjust_does_not_cross_static_wall() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = [
		ZeroAdRtsLabObstacle.new("thin_wall", Vector2(96.0, 80.0), Vector2(12.0, 120.0)),
	]
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(78.0, 80.0), 10.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(78.5, 80.0), 10.0, 0.0, true),
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


func _test_user_reported_repath_loop_converges() -> void:
	var world := ZeroAdRtsLabWorld.new()
	_run_world_steps(world, 67)
	var base_metrics := world.get_metrics()
	world.set_units_target(["blue_0", "blue_1"], Vector2(316.0, 326.0))
	_run_world_steps(world, 29)
	world.set_units_target(["blue_0", "blue_1"], Vector2(350.0, 311.0))
	_run_world_steps(world, 620)
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var long_delta := int(metrics.get("long_path_requests", 0)) - int(base_metrics.get("long_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	var request_delta := short_delta + long_delta
	var active_count := int(metrics.get("active_count", 0))
	var move_failures := int(metrics.get("move_failures", 0)) - int(base_metrics.get("move_failures", 0))
	if active_count > 0:
		_failures.append("runaway-repath: expected move order to converge, active=%d metrics=%s" % [
			active_count,
			str(metrics),
		])
	if request_delta >= 120:
		_failures.append("runaway-repath: expected bounded requests, short=%d long=%d blocked=%d" % [
			short_delta,
			long_delta,
			blocked_delta,
		])
	if move_failures <= 0 and int(metrics.get("arrived_count", 0)) < int(metrics.get("mobile_count", 0)):
		_failures.append("runaway-repath: expected arrival or explicit move failure, metrics=%s" % str(metrics))


func _test_blocker_contact_oscillation_converges() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(208.9639, 295.4086), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(283.9999, 211.2196), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_1", Vector2(280.0, 161.0))
	var last_distance := INF
	var sign_changes := 0
	var last_dy_sign := 0
	for _i in range(240):
		var unit := world.get_unit("blue_1")
		if unit == null:
			_failures.append("contact-oscillation: missing blue_1")
			return
		var before_y := unit.position.y
		world.step(1.0 / 60.0)
		var dy := unit.position.y - before_y
		var dy_sign := 0
		if dy > 0.001:
			dy_sign = 1
		elif dy < -0.001:
			dy_sign = -1
		if last_dy_sign != 0 and dy_sign != 0 and dy_sign != last_dy_sign:
			sign_changes += 1
		if dy_sign != 0:
			last_dy_sign = dy_sign
		last_distance = unit.position.distance_to(unit.path_target)
		if not unit.has_move_order:
			break
	var final_unit := world.get_unit("blue_1")
	if final_unit == null:
		_failures.append("contact-oscillation: missing blue_1 after run")
		return
	if final_unit.has_move_order:
		_failures.append("contact-oscillation: expected arrival or failure, distance=%.2f sign_changes=%d metrics=%s" % [
			last_distance,
			sign_changes,
			str(world.get_metrics()),
		])
	if sign_changes > 8:
		_failures.append("contact-oscillation: expected bounded back-and-forth, sign_changes=%d metrics=%s" % [
			sign_changes,
			str(world.get_metrics()),
		])


func _run_world_steps(world: ZeroAdRtsLabWorld, count: int) -> void:
	for _i in range(count):
		world.step(0.1)


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])
