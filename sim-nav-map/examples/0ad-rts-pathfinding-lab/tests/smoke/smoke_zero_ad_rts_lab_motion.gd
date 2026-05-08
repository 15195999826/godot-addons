extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_test_movement_line_blocks_static_crossing()
	_test_same_team_units_block_movement_line()
	_test_unit_line_blockage_requests_short_path()
	_test_push_adjust_does_not_cross_static_wall()
	_test_user_reported_repath_loop_converges()
	_test_blocker_contact_oscillation_converges()
	_test_user_reported_short_recovery_stays_bounded()
	_test_default_corridor_allows_group_move()
	_test_static_corner_replay_keeps_executable_long_path()
	_test_logged_narrow_passage_replay_stays_static_clear()
	_test_opposing_same_team_units_do_not_cross_in_narrow_passage()
	_test_logged_overlap_can_move_away_from_trailing_unit()
	_test_unit_actor_tracks_move_order()

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


func _test_same_team_units_block_movement_line() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(120.0, 80.0), 10.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	var line_result := world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units
	)
	_assert_equal_str(
		SimNavMovementLineResult.STATUS_BLOCKED,
		line_result.status,
		"same-team-unit-line should be blocked"
	)
	_assert_equal_str(
		SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED,
		line_result.failure_reason,
		"same-team-unit-line should fail by unit obstruction"
	)


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


func _test_user_reported_short_recovery_stays_bounded() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(45.2867, 323.9132), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(270.7062, 359.0760), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_1", Vector2(258.0, 112.0))
	var base_metrics := world.get_metrics()
	for _i in range(260):
		world.step(1.0 / 60.0)
		var unit := world.get_unit("blue_1")
		if unit != null and not unit.has_move_order:
			break
	var final_unit := world.get_unit("blue_1")
	if final_unit == null:
		_failures.append("short-recovery: missing blue_1")
		return
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	if final_unit.has_move_order:
		_failures.append("short-recovery: expected final command to arrive or fail, metrics=%s" % str(metrics))
	if short_delta > 1:
		_failures.append("short-recovery: expected one blocker-avoidance short path, got %d metrics=%s" % [
			short_delta,
			str(metrics),
		])
	if blocked_delta > 1:
		_failures.append("short-recovery: expected bounded blocker contact, blocked=%d metrics=%s" % [
			blocked_delta,
			str(metrics),
		])


func _test_default_corridor_allows_group_move() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(world.current_target)
	for _i in range(480):
		world.step(1.0 / 60.0)
		if int(world.get_metrics().get("active_count", 0)) == 0:
			break
	var metrics := world.get_metrics()
	if int(metrics.get("active_count", 0)) > 0:
		_failures.append("default-corridor: expected default move to finish, metrics=%s units=%s" % [
			str(metrics),
			str(_mobile_unit_summary(world)),
		])
	if int(metrics.get("arrived_count", 0)) < int(metrics.get("mobile_count", 0)):
		_failures.append("default-corridor: expected all mobile units to arrive, metrics=%s units=%s" % [
			str(metrics),
			str(_mobile_unit_summary(world)),
		])


func _test_static_corner_replay_keeps_executable_long_path() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("static-corner-replay: missing mobile units")
		return
	blue_0.position = Vector2(435.033, 168.285)
	blue_1.position = Vector2(188.858, 291.965)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)
	world.issue_move("blue_0", Vector2(368.0, 130.0))
	var base_metrics := world.get_metrics()
	for _i in range(160):
		world.step(1.0 / 60.0)
		if not blue_0.has_move_order:
			break
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	if blue_0.has_move_order:
		_failures.append("static-corner-replay: expected blue_0 to arrive, metrics=%s trace=%s" % [
			str(metrics),
			str(blue_0.trace),
		])
	if short_delta != 0 or blocked_delta != 0:
		_failures.append("static-corner-replay: expected executable long path without short recovery, short=%d blocked=%d trace=%s" % [
			short_delta,
			blocked_delta,
			str(blue_0.trace),
		])


func _test_logged_narrow_passage_replay_stays_static_clear() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("logged-narrow-passage: missing mobile units")
		return
	blue_0.position = Vector2(350.1046, 127.1347)
	# This replay checks the static corridor geometry; unit-unit blocking has a dedicated test.
	blue_1.position = Vector2(620.0, 360.0)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)

	var logged_points := [
		{"tick": 1743, "point": Vector2(350.1046, 127.1347)},
		{"tick": 1744, "point": Vector2(351.6926, 126.9390)},
		{"tick": 1745, "point": Vector2(353.2805, 126.7433)},
		{"tick": 1746, "point": Vector2(354.8685, 126.5476)},
		{"tick": 1747, "point": Vector2(356.4565, 126.3519)},
		{"tick": 1748, "point": Vector2(358.0445, 126.1562)},
		{"tick": 1749, "point": Vector2(359.6325, 125.9605)},
		{"tick": 1750, "point": Vector2(361.2205, 125.7648)},
		{"tick": 1751, "point": Vector2(362.8084, 125.5691)},
		{"tick": 1752, "point": Vector2(364.3964, 125.3734)},
		{"tick": 1753, "point": Vector2(365.9844, 125.1777)},
		{"tick": 1754, "point": Vector2(367.5724, 124.9820)},
		{"tick": 1755, "point": Vector2(369.1604, 124.7863)},
		{"tick": 1756, "point": Vector2(370.7484, 124.5906)},
		{"tick": 1757, "point": Vector2(372.3363, 124.3950)},
		{"tick": 1758, "point": Vector2(373.9243, 124.1993)},
		{"tick": 1760, "point": Vector2(380.6025, 126.9265)},
		{"tick": 1800, "point": Vector2(437.0, 141.0)},
	]
	for i in range(1, logged_points.size()):
		var prev_tick := int(logged_points[i - 1]["tick"])
		var next_tick := int(logged_points[i]["tick"])
		if next_tick - prev_tick > 2:
			continue
		var prev_point: Vector2 = logged_points[i - 1]["point"]
		var next_point: Vector2 = logged_points[i]["point"]
		var line_result := world.pathfinder.validate_movement_line(
			blue_0,
			prev_point,
			next_point,
			world.units,
			false
		)
		if not line_result.is_success():
			_failures.append("logged-narrow-passage: exported segment should stay clear %s -> %s (%s/%s)" % [
				str(prev_point),
				str(next_point),
				line_result.status,
				line_result.failure_reason,
			])
			return

	world.issue_move("blue_0", Vector2(437.0, 141.0))
	var base_metrics := world.get_metrics()
	var static_violation := false
	for _i in range(220):
		world.step(1.0 / 60.0)
		if world.pathfinder.point_inside_static(blue_0.position, blue_0.radius):
			static_violation = true
			break
		if not blue_0.has_move_order:
			break
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	if static_violation:
		_failures.append("logged-narrow-passage: unit entered inflated static obstacle, trace=%s" % str(blue_0.trace))
	if blue_0.has_move_order:
		_failures.append("logged-narrow-passage: expected logged target to remain reachable, metrics=%s trace=%s" % [
			str(metrics),
			str(blue_0.trace),
		])
	if short_delta > 2 or blocked_delta > 2:
		_failures.append("logged-narrow-passage: expected bounded local recovery, short=%d blocked=%d metrics=%s" % [
			short_delta,
			blocked_delta,
			str(metrics),
		])


func _test_opposing_same_team_units_do_not_cross_in_narrow_passage() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(300.0, 125.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(430.0, 125.0), 11.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	world.issue_move("blue_0", Vector2(430.0, 125.0))
	world.issue_move("blue_1", Vector2(300.0, 125.0))
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("opposing-narrow: missing mobile units")
		return

	var previous_blue_0 := blue_0.position
	var previous_blue_1 := blue_1.position
	var crossed_in_passage := false
	var crossing_tick := -1
	for _i in range(180):
		world.step(1.0 / 60.0)
		var current_blue_0 := blue_0.position
		var current_blue_1 := blue_1.position
		var previous_order: float = previous_blue_0.x - previous_blue_1.x
		var current_order: float = current_blue_0.x - current_blue_1.x
		if previous_order < 0.0 and current_order > 0.0:
			crossed_in_passage = (
				_inside_default_top_passage(previous_blue_0)
				and _inside_default_top_passage(previous_blue_1)
				and _inside_default_top_passage(current_blue_0)
				and _inside_default_top_passage(current_blue_1)
			)
			crossing_tick = world.tick_count
			break
		previous_blue_0 = current_blue_0
		previous_blue_1 = current_blue_1
	if crossed_in_passage:
		_failures.append("opposing-narrow: same-team units crossed through each other at tick=%d metrics=%s traces=%s/%s" % [
			crossing_tick,
			str(world.get_metrics()),
			str(blue_0.trace),
			str(blue_1.trace),
		])


func _test_logged_overlap_can_move_away_from_trailing_unit() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("logged-overlap-escape: missing mobile units")
		return
	blue_0.position = Vector2(379.2110, 124.5985)
	blue_1.position = Vector2(358.5816, 124.3004)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)
	var left_target := Vector2(216.0, 136.0)
	var line_result := world.pathfinder.validate_movement_line(
		blue_1,
		blue_1.position,
		left_target,
		world.units,
		false
	)
	if not line_result.is_success():
		_failures.append("logged-overlap-escape: expected moving away from trailing unit to be clear, got %s/%s blocker=%s" % [
			line_result.status,
			line_result.failure_reason,
			line_result.blocked_obstruction_entity_id,
		])
		return

	world.issue_move("blue_1", left_target)
	var start_x := blue_1.position.x
	for _i in range(20):
		world.step(1.0 / 60.0)
	if blue_1.position.x >= start_x - 1.0:
		_failures.append("logged-overlap-escape: expected blue_1 to move left, start=%.2f pos=%s metrics=%s" % [
			start_x,
			str(blue_1.position),
			str(world.get_metrics()),
		])


func _test_unit_actor_tracks_move_order() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	world.issue_move("blue_0", Vector2(120.0, 80.0))
	var unit := world.get_unit("blue_0")
	if unit == null:
		_failures.append("order-track: missing blue_0")
		return
	var order_id := unit.active_order_id()
	if order_id <= 0:
		_failures.append("order-track: expected active order id")
		return
	for _i in range(80):
		world.step(0.1)
		if not unit.has_move_order:
			break
	if unit.has_move_order:
		_failures.append("order-track: expected order completion, metrics=%s" % str(world.get_metrics()))
		return
	if unit.last_order == null:
		_failures.append("order-track: expected last order snapshot")
		return
	if unit.last_order.order_id != order_id:
		_failures.append("order-track: last order id mismatch")
	if unit.last_order.status != "completed":
		_failures.append("order-track: expected completed last order, got %s" % unit.last_order.status)
	if int(unit.last_order.metrics.get("long_path_requests", 0)) <= 0:
		_failures.append("order-track: expected per-order long path metric")
	if world.recent_motion_updates.is_empty():
		_failures.append("order-track: expected world motion update log")
	if world.recent_motion_updates.size() > 2:
		_failures.append("order-track: expected semantic motion updates only, got %d updates=%s" % [
			world.recent_motion_updates.size(),
			str(world.recent_motion_updates),
		])


func _run_world_steps(world: ZeroAdRtsLabWorld, count: int) -> void:
	for _i in range(count):
		world.step(0.1)


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _mobile_unit_summary(world: ZeroAdRtsLabWorld) -> Array[String]:
	var result: Array[String] = []
	for unit in world.get_mobile_units():
		result.append("%s pos=%s target=%s failed=%s last=%s" % [
			unit.id,
			str(unit.position),
			str(unit.path_target),
			str(unit.move_failed),
			str(unit.last_order_snapshot()),
		])
	return result


func _inside_default_top_passage(point: Vector2) -> bool:
	return point.x >= 260.0 and point.x <= 470.0 and point.y >= 110.0 and point.y <= 140.0
