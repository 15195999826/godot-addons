extends Node

# Phase B behavior baseline smoke for Dota2 RTS Pathfinding Lab.
# This test accepts hard-block terminal failures only when the exported order
# reason makes that explicit. Unexpected FAILED reasons are reported as defects.

const TICK_DELTA := 1.0 / 60.0
const DEFAULT_GROUP_TICKS := 1200
const NARROW_GAP_TICKS := 900
const MIXED_OBSTACLE_TICKS := 1200
const STABLE_TAIL_TICKS := 12
const POSITION_STABLE_EPSILON := 4.0


var _failures: Array[String] = []
var _reports: Array[Dictionary] = []


func _ready() -> void:
	_test_default_group_move_baseline()
	_test_narrow_gap_bounded_terminal()
	_test_mixed_static_dynamic_obstacle()

	for report in _reports:
		print("DOTA2_PHASE_B_BASELINE: %s" % JSON.stringify(report))

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab behavior baseline")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ─────────────────────────── Test cases ──────────────────────────────────────

func _test_default_group_move_baseline() -> void:
	var world := Dota2LabWorld.new()
	var unit_ids := world.get_mobile_unit_ids()
	world.issue_move_all_mobile(world.current_target)

	var report := _run_until_terminal(
		"default_group_move",
		world,
		unit_ids,
		DEFAULT_GROUP_TICKS,
		PackedStringArray(["max_retry_exceeded"])
	)
	_reports.append(report)
	_assert_terminal_report(report)
	_assert_true(
		_state_count(report, Dota2LabUnit.STATE_IDLE) + _state_count(report, Dota2LabUnit.STATE_FAILED) == unit_ids.size(),
		"default-group: all mobile units should be terminal"
	)


func _test_narrow_gap_bounded_terminal() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = [
		Dota2LabObstacle.new("gap_wall_top", Vector2(660.0, 390.0), Vector2(1320.0, 64.0)),
		Dota2LabObstacle.new("gap_wall_bottom", Vector2(660.0, 510.0), Vector2(1320.0, 64.0)),
	]
	world.units = [
		Dota2LabUnit.new("gap_left", "blue", Vector2(500.0, 450.0), 11.0, 110.0, true),
		Dota2LabUnit.new("gap_right", "red", Vector2(820.0, 450.0), 11.0, 110.0, true),
	]
	world._rebuild_navigation()
	world.clear_traces()
	world.issue_move("gap_left", Vector2(820.0, 450.0))
	world.issue_move("gap_right", Vector2(500.0, 450.0))

	var unit_ids: Array[String] = ["gap_left", "gap_right"]
	var report := _run_until_terminal(
		"narrow_gap_bounded_terminal",
		world,
		unit_ids,
		NARROW_GAP_TICKS,
		PackedStringArray(["max_retry_exceeded", "long_path_unreachable:"])
	)
	_reports.append(report)
	_assert_terminal_report(report)
	_assert_true(
		_state_count(report, Dota2LabUnit.STATE_FAILED) > 0,
		"narrow-gap: expected at least one clean FAILED terminal under hard-block policy"
	)
	_assert_true(
		int(report.get("blocked_by_unit_count", 0)) > 0 or int(report.get("short_path_requests", 0)) > 0,
		"narrow-gap: expected dynamic unit block evidence"
	)


func _test_mixed_static_dynamic_obstacle() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = [
		Dota2LabObstacle.new("mixed_north_static", Vector2(520.0, 290.0), Vector2(120.0, 220.0)),
		Dota2LabObstacle.new("mixed_south_static", Vector2(520.0, 610.0), Vector2(120.0, 220.0)),
	]
	world.units = [
		Dota2LabUnit.new("mixed_0", "blue", Vector2(260.0, 365.0), 11.0, 110.0, true),
		Dota2LabUnit.new("mixed_1", "blue", Vector2(260.0, 415.0), 11.0, 110.0, true),
		Dota2LabUnit.new("mixed_2", "blue", Vector2(260.0, 485.0), 11.0, 110.0, true),
		Dota2LabUnit.new("mixed_3", "blue", Vector2(260.0, 535.0), 11.0, 110.0, true),
		Dota2LabUnit.new("mixed_blocker", "red", Vector2(520.0, 450.0), 14.0, 0.0, false),
	]
	world._rebuild_navigation()
	world.clear_traces()
	var unit_ids: Array[String] = ["mixed_0", "mixed_1", "mixed_2", "mixed_3"]
	for unit_id in unit_ids:
		world.issue_move(unit_id, Vector2(820.0, 450.0))

	var report := _run_until_terminal(
		"mixed_static_dynamic_obstacle",
		world,
		unit_ids,
		MIXED_OBSTACLE_TICKS,
		PackedStringArray(["max_retry_exceeded", "long_path_unreachable:"])
	)
	_reports.append(report)
	_assert_terminal_report(report)
	_assert_true(
		int(report.get("static_obstacle_count", 0)) > 0,
		"mixed-obstacle: expected static obstacle fixture"
	)
	_assert_true(
		int(report.get("blocked_by_unit_count", 0)) > 0 or int(report.get("short_path_requests", 0)) > 0,
		"mixed-obstacle: expected dynamic blocker evidence"
	)


# ─────────────────────────── Scenario runner ─────────────────────────────────

func _run_until_terminal(
	scenario_id: String,
	world: Dota2LabWorld,
	unit_ids: Array[String],
	max_ticks: int,
	allowed_failure_prefixes: PackedStringArray
) -> Dictionary:
	var position_tail: Dictionary = {}
	var waiting_long_counts: Dictionary = {}
	var waiting_short_counts: Dictionary = {}
	for unit_id in unit_ids:
		position_tail[unit_id] = []
		waiting_long_counts[unit_id] = 0
		waiting_short_counts[unit_id] = 0

	var settled := false
	var ticks_run := 0
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		ticks_run = i + 1
		_record_positions(world, unit_ids, position_tail)
		_record_waiting_counts(world, unit_ids, waiting_long_counts, waiting_short_counts)
		if _units_are_terminal(world, unit_ids) and _queue_is_drained(world):
			settled = true
			break

	var metrics := world.get_metrics()
	var pathfinder_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	var state_counts: Dictionary = _state_counts_for_ids(world, unit_ids)
	var failure_details := _classify_failed_units(
		world,
		unit_ids,
		allowed_failure_prefixes,
		metrics,
		position_tail
	)

	return {
		"scenario": scenario_id,
		"settled": settled,
		"ticks_run": ticks_run,
		"max_ticks": max_ticks,
		"state_counts": state_counts,
		"terminal_failure_details": failure_details.get("details", []),
		"has_unexpected_failure": failure_details.get("has_unexpected_failure", false),
		"pending_count": int(pathfinder_metrics.get("pending_count", -1)),
		"result_count": int(pathfinder_metrics.get("result_count", -1)),
		"pending_count_peak": int(metrics.get("pending_count_peak", -1)),
		"long_path_requests": int(metrics.get("long_path_requests", 0)),
		"short_path_requests": int(metrics.get("short_path_requests", 0)),
		"blocked_by_unit_count": int(metrics.get("blocked_by_unit_count", 0)),
		"blocked_by_static_count": int(metrics.get("blocked_by_static_count", 0)),
		"move_failed_count": int(metrics.get("move_failed_count", 0)),
		"reached_goal_count": int(metrics.get("reached_goal_count", 0)),
		"retry_count_max": int(metrics.get("retry_count_max", 0)),
		"static_obstacle_count": world.obstacles.size(),
		"waiting_long_counts": waiting_long_counts.duplicate(true),
		"waiting_short_counts": waiting_short_counts.duplicate(true),
		"unit_summaries": _unit_summaries(world, unit_ids),
	}


func _assert_terminal_report(report: Dictionary) -> void:
	var scenario_id := str(report.get("scenario", "unknown"))
	_assert_true(bool(report.get("settled", false)), "%s: did not settle within bounded ticks" % scenario_id)
	_assert_eq(0, int(report.get("pending_count", -1)), "%s: pending queue should drain" % scenario_id)
	_assert_eq(0, int(report.get("result_count", -1)), "%s: result queue should drain" % scenario_id)
	_assert_true(
		not bool(report.get("has_unexpected_failure", true)),
		"%s: unexpected FAILED classification %s" % [
			scenario_id,
			str(report.get("terminal_failure_details", [])),
		]
	)


func _classify_failed_units(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	allowed_failure_prefixes: PackedStringArray,
	metrics: Dictionary,
	position_tail: Dictionary
) -> Dictionary:
	var details: Array[String] = []
	var has_unexpected_failure := false
	var has_block_evidence := (
		int(metrics.get("blocked_by_unit_count", 0)) > 0
		or int(metrics.get("blocked_by_static_count", 0)) > 0
		or int(metrics.get("short_path_requests", 0)) > 0
	)
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null or unit.state != Dota2LabUnit.STATE_FAILED:
			continue
		var order_snapshot := unit.last_order_snapshot()
		var reason := str(order_snapshot.get("failure_reason", ""))
		var allowed_reason := _has_allowed_prefix(reason, allowed_failure_prefixes)
		var stable_terminal := _tail_is_stable(position_tail.get(unit_id, []))
		if allowed_reason and has_block_evidence and stable_terminal:
			details.append("%s allowed hard-block terminal: %s" % [unit_id, reason])
		else:
			has_unexpected_failure = true
			details.append(
				"%s defect: reason=%s allowed=%s block_evidence=%s stable=%s"
					% [unit_id, reason, str(allowed_reason), str(has_block_evidence), str(stable_terminal)]
			)
	return {
		"details": details,
		"has_unexpected_failure": has_unexpected_failure,
	}


# ─────────────────────────── Helpers ─────────────────────────────────────────

func _record_positions(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	position_tail: Dictionary
) -> void:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			continue
		var positions: Array = position_tail.get(unit_id, []) as Array
		positions.append(unit.position)
		while positions.size() > STABLE_TAIL_TICKS:
			positions.pop_front()
		position_tail[unit_id] = positions


func _record_waiting_counts(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	waiting_long_counts: Dictionary,
	waiting_short_counts: Dictionary
) -> void:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			continue
		if unit.state == Dota2LabUnit.STATE_WAITING_LONG:
			waiting_long_counts[unit_id] = int(waiting_long_counts.get(unit_id, 0)) + 1
		elif unit.state == Dota2LabUnit.STATE_WAITING_SHORT:
			waiting_short_counts[unit_id] = int(waiting_short_counts.get(unit_id, 0)) + 1


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
		var last_order := unit.last_order_snapshot()
		result.append({
			"id": unit.id,
			"state": unit.state,
			"position": {"x": unit.position.x, "y": unit.position.y},
			"move_target": {"x": unit.move_target.x, "y": unit.move_target.y},
			"retry_count": unit.retry_count,
			"pending_long_ticket": unit.pending_long_ticket,
			"pending_short_ticket": unit.pending_short_ticket,
			"last_order_status": str(last_order.get("status", "")),
			"failure_reason": str(last_order.get("failure_reason", "")),
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
	)


func _has_allowed_prefix(reason: String, prefixes: PackedStringArray) -> bool:
	for prefix in prefixes:
		if reason.begins_with(prefix):
			return true
	return false


func _tail_is_stable(tail: Array) -> bool:
	if tail.size() < 2:
		return true
	var anchor: Vector2 = tail[tail.size() - 1] as Vector2
	for item in tail:
		var point: Vector2 = item as Vector2
		if point.distance_to(anchor) > POSITION_STABLE_EPSILON:
			return false
	return true


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
