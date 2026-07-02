extends Node

# Layer 2 command source drives only public Dota2LabWorld commands; the
# scripted sequence terminates every unit (arrive or cancel) in bounded time.

const AiCommandSourceScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_ai_command_source.gd")

const TICK_DELTA := 1.0 / 60.0
const SCRIPT_TICKS := 80
const SETTLE_TICKS := 900
const EXPECTED_COMMAND_COUNT := 8


var _failures: Array[String] = []


func _ready() -> void:
	_test_ai_command_source_drives_public_commands()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab ai command source")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_ai_command_source_drives_public_commands() -> void:
	var world := _open_lane_world()
	var source = AiCommandSourceScript.build_smoke_driver()

	for i in range(SCRIPT_TICKS):
		source.tick(world)
		world.step(TICK_DELTA)

	_assert_true(source.is_finished(), "ai-source: script should finish")
	_assert_eq(EXPECTED_COMMAND_COUNT, source.emitted_count(), "ai-source: emitted command count")

	var commanded_ids: Array[String] = source.commanded_unit_ids() as Array[String]
	var settled := _run_until_terminal(world, commanded_ids, SETTLE_TICKS)
	var report := _terminal_report(world, commanded_ids, source)
	print("DOTA2_LAYER2_COMMAND_SOURCE: %s" % JSON.stringify(report))

	_assert_true(settled, "ai-source: commanded units should settle")
	_assert_latest_targets(world, source)
	_assert_expected_terminal_states(world)


func _open_lane_world() -> Dota2LabWorld:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("lane_0", "blue", Vector2(100.0, 160.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_1", "blue", Vector2(100.0, 240.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_2", "blue", Vector2(100.0, 320.0), 11.0, 110.0, true),
		Dota2LabUnit.new("chaser", "blue", Vector2(140.0, 450.0), 11.0, 110.0, true),
		Dota2LabUnit.new("cancelled", "blue", Vector2(140.0, 560.0), 11.0, 110.0, true),
	]
	world.rebuild_navigation()
	world.clear_traces()
	return world


func _run_until_terminal(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	max_ticks: int
) -> bool:
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		if _units_are_terminal(world, unit_ids):
			return true
	return false


func _terminal_report(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	source: Variant
) -> Dictionary:
	var metrics := world.get_metrics()
	return {
		"emitted_count": source.emitted_count(),
		"emitted": source.emitted_snapshots(),
		"commanded_unit_ids": source.commanded_unit_ids(),
		"cancelled_unit_ids": source.cancelled_unit_ids(),
		"latest_targets_by_unit": _target_snapshots(source.latest_targets_by_unit()),
		"state_counts": metrics.get("state_counts", {}),
		"orders_completed": int(metrics.get("orders_completed", 0)),
		"orders_failed": int(metrics.get("orders_failed", 0)),
		"unit_summaries": _unit_summaries(world, unit_ids),
	}


func _assert_latest_targets(world: Dota2LabWorld, source: Variant) -> void:
	var latest_targets: Dictionary = source.latest_targets_by_unit() as Dictionary
	for unit_id in ["lane_0", "lane_1", "lane_2", "chaser"]:
		var unit := world.get_unit(unit_id)
		_assert_true(unit != null, "latest-target: missing %s" % unit_id)
		if unit == null:
			continue
		var expected: Vector2 = latest_targets.get(unit_id, Vector2.ZERO) as Vector2
		_assert_true(
			unit.move_target.distance_to(expected) <= 0.001,
			"latest-target: %s should keep command source target" % unit_id
		)


func _assert_expected_terminal_states(world: Dota2LabWorld) -> void:
	for unit_id in ["lane_0", "lane_1", "lane_2", "chaser"]:
		var unit := world.get_unit(unit_id)
		_assert_true(unit != null, "terminal: missing %s" % unit_id)
		if unit == null:
			continue
		_assert_eq(Dota2LabUnit.STATE_IDLE, unit.state, "terminal: %s should reach IDLE" % unit_id)
		_assert_eq(
			Dota2LabMoveOrder.STATUS_COMPLETED,
			str(unit.last_order_snapshot().get("status", "")),
			"terminal: %s final order should complete" % unit_id
		)

	var cancelled_unit := world.get_unit("cancelled")
	_assert_true(cancelled_unit != null, "terminal: missing cancelled unit")
	if cancelled_unit == null:
		return
	_assert_eq(Dota2LabUnit.STATE_IDLE, cancelled_unit.state, "terminal: cancelled should end IDLE")
	_assert_true(cancelled_unit.current_order == null, "terminal: cancelled should have no current order")
	var last_order := cancelled_unit.last_order_snapshot()
	_assert_eq(
		Dota2LabMoveOrder.REASON_CANCELLED,
		str(last_order.get("reason", "")),
		"terminal: cancel reason"
	)


func _units_are_terminal(world: Dota2LabWorld, unit_ids: Array[String]) -> bool:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			return false
		if unit.state == Dota2LabUnit.STATE_MOVING:
			return false
	return true


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
			"position": _vector_snapshot(unit.position),
			"move_target": _vector_snapshot(unit.move_target),
			"last_order": unit.last_order_snapshot(),
			"current_order": unit.current_order_snapshot(),
		})
	return result


func _target_snapshots(targets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for unit_id in targets.keys():
		var target: Vector2 = targets.get(unit_id, Vector2.ZERO) as Vector2
		result[str(unit_id)] = _vector_snapshot(target)
	return result


func _vector_snapshot(point: Vector2) -> Dictionary:
	return {
		"x": point.x,
		"y": point.y,
	}


func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
