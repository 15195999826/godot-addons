extends Node


const TICK_DELTA := 1.0 / 60.0
const DEFAULT_GROUP_TICKS := 1200
const RAPID_SWITCH_TICKS := 500


var _failures: Array[String] = []


func _ready() -> void:
	_test_default_group_move_fanout()
	_test_single_unit_command_has_no_fanout()
	_test_rapid_target_switch_with_fanout_drains_queue()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab target fanout")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_default_group_move_fanout() -> void:
	var world := Dota2LabWorld.new()
	var unit_ids := world.get_mobile_unit_ids()
	world.issue_move_all_mobile(world.current_target)
	var report := _run_until_terminal("default_group_move_fanout", world, unit_ids, DEFAULT_GROUP_TICKS)
	print("DOTA2_PHASE_C_FANOUT: %s" % JSON.stringify(report))

	_assert_terminal_report(report)
	_assert_true(
		_state_count(report, Dota2LabUnit.STATE_IDLE) >= 6,
		"default-fanout: expected at least 6/8 IDLE, got %s"
			% str(report.get("state_counts", {}))
	)
	_assert_true(
		_state_count(report, Dota2LabUnit.STATE_FAILED) <= 2,
		"default-fanout: expected at most 2/8 FAILED, got %s"
			% str(report.get("state_counts", {}))
	)
	_assert_fanout_assignments(world, unit_ids.size(), "default-fanout")


func _test_single_unit_command_has_no_fanout() -> void:
	var world := Dota2LabWorld.new()
	var target := Vector2(600.0, 200.0)
	world.issue_move("blue_0", target)
	var unit := world.get_unit("blue_0")
	_assert_true(unit != null, "single-unit: missing blue_0")
	if unit == null:
		return
	_assert_eq(target, unit.move_target, "single-unit: move_target should stay exact")
	_assert_eq(Dota2LabUnit.STATE_WAITING_LONG, unit.state, "single-unit: should still use normal move path")
	var metrics := world.get_metrics()
	var assignments: Array = metrics.get("last_fanout_assignments", []) as Array
	_assert_eq(0, assignments.size(), "single-unit: should not record fanout assignments")


func _test_rapid_target_switch_with_fanout_drains_queue() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("lane_0", "blue", Vector2(100.0, 140.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_1", "blue", Vector2(100.0, 220.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_2", "blue", Vector2(100.0, 300.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_3", "blue", Vector2(100.0, 380.0), 11.0, 110.0, true),
	]
	world._rebuild_navigation()
	var unit_ids: Array[String] = ["lane_0", "lane_1", "lane_2", "lane_3"]
	var final_targets: Dictionary = {}
	for switch_index in range(5):
		var goal := Vector2(320.0 + float(switch_index % 3) * 36.0, 250.0)
		world.issue_move_ids(unit_ids, goal)
		final_targets = _assignment_targets_by_unit(world)
		world.step(TICK_DELTA)

	var settled := false
	for i in range(RAPID_SWITCH_TICKS):
		world.step(TICK_DELTA)
		if _units_are_terminal(world, unit_ids) and _queue_is_drained(world):
			settled = true
			break

	var metrics := world.get_metrics()
	var pathfinder_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	_assert_true(settled, "rapid-fanout: units and queue should settle")
	_assert_eq(0, int(pathfinder_metrics.get("pending_count", -1)), "rapid-fanout: pending_count should drain")
	_assert_eq(0, int(pathfinder_metrics.get("result_count", -1)), "rapid-fanout: result_count should drain")
	_assert_eq(0, _result_ticket_count(pathfinder_metrics), "rapid-fanout: result_tickets should drain")
	_assert_true(int(pathfinder_metrics.get("cancelled_count", 0)) > 0, "rapid-fanout: cancelled_count should increase")
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		_assert_true(unit != null, "rapid-fanout: missing unit %s" % unit_id)
		if unit == null:
			continue
		var expected_target: Vector2 = final_targets.get(unit_id, unit.move_target) as Vector2
		_assert_true(
			unit.move_target.distance_to(expected_target) <= 0.001,
			"rapid-fanout: %s should keep latest assigned target" % unit_id
		)


func _run_until_terminal(
	scenario_id: String,
	world: Dota2LabWorld,
	unit_ids: Array[String],
	max_ticks: int
) -> Dictionary:
	var settled := false
	var ticks_run := 0
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		ticks_run = i + 1
		if _units_are_terminal(world, unit_ids) and _queue_is_drained(world):
			settled = true
			break

	var metrics := world.get_metrics()
	var pathfinder_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	return {
		"scenario": scenario_id,
		"settled": settled,
		"ticks_run": ticks_run,
		"state_counts": _state_counts_for_ids(world, unit_ids),
		"pending_count": int(pathfinder_metrics.get("pending_count", -1)),
		"result_count": int(pathfinder_metrics.get("result_count", -1)),
		"result_ticket_count": _result_ticket_count(pathfinder_metrics),
		"pending_command_release_count": int(metrics.get("pending_command_release_count", -1)),
		"blocked_by_unit_count": int(metrics.get("blocked_by_unit_count", 0)),
		"short_path_requests": int(metrics.get("short_path_requests", 0)),
		"fanout_assignment_count": int(metrics.get("fanout_assignment_count", 0)),
		"last_fanout_assignments": metrics.get("last_fanout_assignments", []),
		"unit_summaries": _unit_summaries(world, unit_ids),
	}


func _assert_terminal_report(report: Dictionary) -> void:
	var scenario_id := str(report.get("scenario", "unknown"))
	_assert_true(bool(report.get("settled", false)), "%s: did not settle within bounded ticks" % scenario_id)
	_assert_eq(0, int(report.get("pending_count", -1)), "%s: pending queue should drain" % scenario_id)
	_assert_eq(0, int(report.get("result_count", -1)), "%s: result queue should drain" % scenario_id)
	_assert_eq(0, int(report.get("result_ticket_count", -1)), "%s: result_tickets should drain" % scenario_id)
	_assert_eq(
		0,
		int(report.get("pending_command_release_count", -1)),
		"%s: command releases should drain" % scenario_id
	)


func _assert_fanout_assignments(world: Dota2LabWorld, expected_count: int, label: String) -> void:
	var metrics := world.get_metrics()
	var assignments: Array = metrics.get("last_fanout_assignments", []) as Array
	_assert_eq(expected_count, assignments.size(), "%s: assignment count" % label)
	var assigned_targets: Dictionary = {}
	for item in assignments:
		var assignment: Dictionary = item as Dictionary
		_assert_true(assignment.has("original_target"), "%s: missing original_target" % label)
		_assert_true(assignment.has("assigned_target"), "%s: missing assigned_target" % label)
		_assert_true(assignment.has("status"), "%s: missing status" % label)
		var status := str(assignment.get("status", ""))
		_assert_true(
			status == "assigned_original" or status == "assigned_offset" or status == "no_slot",
			"%s: unexpected fanout status %s" % [label, status]
		)
		var assigned: Dictionary = assignment.get("assigned_target", {}) as Dictionary
		assigned_targets["%.2f,%.2f" % [float(assigned.get("x", 0.0)), float(assigned.get("y", 0.0))]] = true
	_assert_true(assigned_targets.size() > 1, "%s: assignments should not all share one target" % label)


func _assignment_targets_by_unit(world: Dota2LabWorld) -> Dictionary:
	var result: Dictionary = {}
	var metrics := world.get_metrics()
	var assignments: Array = metrics.get("last_fanout_assignments", []) as Array
	for item in assignments:
		var assignment: Dictionary = item as Dictionary
		var assigned: Dictionary = assignment.get("assigned_target", {}) as Dictionary
		result[str(assignment.get("unit_id", ""))] = Vector2(
			float(assigned.get("x", 0.0)),
			float(assigned.get("y", 0.0))
		)
	return result


func _state_counts_for_ids(world: Dota2LabWorld, unit_ids: Array[String]) -> Dictionary:
	var state_counts := {
		Dota2LabUnit.STATE_IDLE: 0,
		Dota2LabUnit.STATE_WAITING_LONG: 0,
		Dota2LabUnit.STATE_FOLLOWING: 0,
		Dota2LabUnit.STATE_WAITING_SHORT: 0,
		Dota2LabUnit.STATE_FAILED: 0,
	}
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			continue
		state_counts[unit.state] = int(state_counts.get(unit.state, 0)) + 1
	return state_counts


func _unit_summaries(world: Dota2LabWorld, unit_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			result.append({"id": unit_id, "missing": true})
			continue
		result.append({
			"id": unit.id,
			"state": unit.state,
			"position": {"x": unit.position.x, "y": unit.position.y},
			"move_target": {"x": unit.move_target.x, "y": unit.move_target.y},
			"failure_reason": str(unit.last_order_snapshot().get("failure_reason", "")),
		})
	return result


func _units_are_terminal(world: Dota2LabWorld, unit_ids: Array[String]) -> bool:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			return false
		if unit.state != Dota2LabUnit.STATE_IDLE and unit.state != Dota2LabUnit.STATE_FAILED:
			return false
	return true


func _queue_is_drained(world: Dota2LabWorld) -> bool:
	var metrics := world.get_metrics()
	var pathfinder_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	return (
		int(metrics.get("pending_command_release_count", 0)) == 0
		and int(pathfinder_metrics.get("pending_count", 0)) == 0
		and int(pathfinder_metrics.get("result_count", 0)) == 0
		and _result_ticket_count(pathfinder_metrics) == 0
	)


func _result_ticket_count(pathfinder_metrics: Dictionary) -> int:
	var tickets: Array = pathfinder_metrics.get("result_tickets", []) as Array
	return tickets.size()


func _state_count(report: Dictionary, state: String) -> int:
	var state_counts: Dictionary = report.get("state_counts", {}) as Dictionary
	return int(state_counts.get(state, 0))


func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
