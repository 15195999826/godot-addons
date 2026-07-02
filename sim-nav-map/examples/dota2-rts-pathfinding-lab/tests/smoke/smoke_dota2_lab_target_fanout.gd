extends Node

# Group-move target fanout: a multi-unit command spreads assigned targets
# around the clicked point so the group can actually settle. Single-unit
# commands never fan out. Rapid target switching (synchronous planning)
# always keeps the latest assignment.

const TICK_DELTA := 1.0 / 60.0
const DEFAULT_GROUP_TICKS := 2200
const RAPID_SWITCH_TICKS := 700


var _failures: Array[String] = []


func _ready() -> void:
	_test_default_group_move_fanout()
	_test_single_unit_command_has_no_fanout()
	_test_rapid_target_switch_keeps_latest()

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

	# Synchronous planning: every commanded unit is MOVING with an order now.
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		_assert_true(unit != null and unit.current_order != null, "default-fanout: %s missing order" % unit_id)
		if unit != null:
			_assert_eq(Dota2LabUnit.STATE_MOVING, unit.state, "default-fanout: %s should be MOVING" % unit_id)
	_assert_fanout_assignments(world, unit_ids.size(), "default-fanout")

	var ticks := _run_until_idle(world, DEFAULT_GROUP_TICKS, "default-fanout")
	var completed := 0
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit != null \
				and str(unit.last_order_snapshot().get("status", "")) == Dota2LabMoveOrder.STATUS_COMPLETED:
			completed += 1
	_assert_eq(8, completed, "default-fanout: all 8 orders should complete")
	print("DOTA2_FANOUT default: ticks=%d completed=%d" % [ticks, completed])


func _test_single_unit_command_has_no_fanout() -> void:
	var world := Dota2LabWorld.new()
	var target := Vector2(600.0, 200.0)
	var unit_id := world.get_mobile_unit_ids()[0]
	world.issue_move(unit_id, target)
	var unit := world.get_unit(unit_id)
	_assert_true(unit != null, "single-unit: missing %s" % unit_id)
	if unit == null:
		return
	_assert_eq(target, unit.move_target, "single-unit: move_target should stay exact")
	_assert_eq(Dota2LabUnit.STATE_MOVING, unit.state, "single-unit: MOVING immediately")
	var metrics := world.get_metrics()
	var assignments: Array = metrics.get("last_fanout_assignments", []) as Array
	_assert_eq(0, assignments.size(), "single-unit: should not record fanout assignments")


func _test_rapid_target_switch_keeps_latest() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("lane_0", "blue", Vector2(100.0, 140.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_1", "blue", Vector2(100.0, 220.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_2", "blue", Vector2(100.0, 300.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_3", "blue", Vector2(100.0, 380.0), 11.0, 110.0, true),
	]
	world.rebuild_navigation()
	var unit_ids: Array[String] = ["lane_0", "lane_1", "lane_2", "lane_3"]
	var final_targets: Dictionary = {}
	for switch_index in range(5):
		var goal := Vector2(320.0 + float(switch_index % 3) * 36.0, 250.0)
		world.issue_move_ids(unit_ids, goal)
		final_targets = _assignment_targets_by_unit(world)
		world.step(TICK_DELTA)

	var ticks := _run_until_idle(world, RAPID_SWITCH_TICKS, "rapid-fanout")
	print("DOTA2_FANOUT rapid: ticks=%d" % ticks)
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
		_assert_eq(
			Dota2LabMoveOrder.STATUS_COMPLETED,
			str(unit.last_order_snapshot().get("status", "")),
			"rapid-fanout: %s final order should complete" % unit_id
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


func _run_until_idle(world: Dota2LabWorld, max_ticks: int, label: String) -> int:
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		var all_idle := true
		for unit in world.units:
			if unit.state == Dota2LabUnit.STATE_MOVING:
				all_idle = false
				break
		if all_idle:
			return i + 1
	_failures.append("%s: units did not settle within %d ticks" % [label, max_ticks])
	return max_ticks


func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
