class_name Dota2LabAiCommandSource
extends RefCounted

# Deterministic Layer 2 command source for the Dota2 lab.
#
# This class only emits public Dota2LabWorld commands. It must not mutate unit
# motion state, controller state, paths, tickets, or sim-nav-map core objects.

const ACTION_MOVE_UNIT := "move_unit"
const ACTION_MOVE_IDS := "move_ids"
const ACTION_MOVE_ALL := "move_all"
const ACTION_CANCEL := "cancel"


var _commands: Array[Dictionary] = []
var _cursor: int = 0
var _finished: bool = false
var _emitted_snapshots: Array[Dictionary] = []
var _commanded_unit_ids: Dictionary = {}
var _cancelled_unit_ids: Dictionary = {}
var _latest_targets_by_unit: Dictionary = {}


func _init(p_commands: Array[Dictionary] = []) -> void:
	_commands = p_commands.duplicate(true)
	_commands.sort_custom(Callable(self, "_sort_commands_by_tick"))
	_finished = _commands.is_empty()


static func build_smoke_driver() -> Dota2LabAiCommandSource:
	return Dota2LabAiCommandSource.new([
		{
			"tick": 0,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(360.0, 240.0),
			"label": "lane_move_1",
		},
		{
			"tick": 8,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(450.0, 280.0),
			"label": "target_switch_1",
		},
		{
			"tick": 9,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(520.0, 220.0),
			"label": "target_switch_2",
		},
		{
			"tick": 10,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(620.0, 260.0),
			"label": "target_switch_final",
		},
		{
			"tick": 16,
			"action": ACTION_MOVE_UNIT,
			"unit_id": "chaser",
			"goal": Vector2(760.0, 450.0),
			"label": "chase",
		},
		{
			"tick": 28,
			"action": ACTION_MOVE_UNIT,
			"unit_id": "chaser",
			"goal": Vector2(220.0, 450.0),
			"label": "retreat",
		},
		{
			"tick": 34,
			"action": ACTION_MOVE_UNIT,
			"unit_id": "cancelled",
			"goal": Vector2(780.0, 560.0),
			"label": "cancel_setup",
		},
		{
			"tick": 38,
			"action": ACTION_CANCEL,
			"unit_id": "cancelled",
			"label": "cancel",
		},
	])


static func build_visual_demo_driver() -> Dota2LabAiCommandSource:
	return Dota2LabAiCommandSource.new([
		{
			"tick": 0,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(360.0, 240.0),
			"label": "lane_move_1",
		},
		{
			"tick": 120,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(450.0, 280.0),
			"label": "target_switch_1",
		},
		{
			"tick": 180,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(520.0, 220.0),
			"label": "target_switch_2",
		},
		{
			"tick": 240,
			"action": ACTION_MOVE_IDS,
			"unit_ids": ["lane_0", "lane_1", "lane_2"],
			"goal": Vector2(720.0, 260.0),
			"label": "lane_move_final",
		},
		{
			"tick": 300,
			"action": ACTION_MOVE_UNIT,
			"unit_id": "chaser",
			"goal": Vector2(860.0, 450.0),
			"label": "chase",
		},
		{
			"tick": 420,
			"action": ACTION_MOVE_UNIT,
			"unit_id": "chaser",
			"goal": Vector2(220.0, 450.0),
			"label": "retreat",
		},
		{
			"tick": 500,
			"action": ACTION_MOVE_UNIT,
			"unit_id": "cancelled",
			"goal": Vector2(860.0, 560.0),
			"label": "cancel_setup",
		},
		{
			"tick": 580,
			"action": ACTION_CANCEL,
			"unit_id": "cancelled",
			"label": "cancel",
		},
	])


func tick(world: Dota2LabWorld) -> void:
	while _cursor < _commands.size():
		var command: Dictionary = _commands[_cursor]
		var command_tick := int(command.get("tick", -1))
		if command_tick > world.tick_count:
			break
		_emit_command(world, command)
		_cursor += 1
	_finished = _cursor >= _commands.size()


func is_finished() -> bool:
	return _finished


func emitted_count() -> int:
	return _emitted_snapshots.size()


func emitted_snapshots() -> Array[Dictionary]:
	return _emitted_snapshots.duplicate(true)


func commanded_unit_ids() -> Array[String]:
	var result: Array[String] = []
	for unit_id in _commanded_unit_ids.keys():
		result.append(str(unit_id))
	result.sort()
	return result


func cancelled_unit_ids() -> Array[String]:
	var result: Array[String] = []
	for unit_id in _cancelled_unit_ids.keys():
		result.append(str(unit_id))
	result.sort()
	return result


func latest_targets_by_unit() -> Dictionary:
	return _latest_targets_by_unit.duplicate(true)


func _emit_command(world: Dota2LabWorld, command: Dictionary) -> void:
	var action := str(command.get("action", ""))
	match action:
		ACTION_MOVE_UNIT:
			_emit_move_unit(world, command)
		ACTION_MOVE_IDS:
			_emit_move_ids(world, command)
		ACTION_MOVE_ALL:
			_emit_move_all(world, command)
		ACTION_CANCEL:
			_emit_cancel(world, command)
		_:
			Log.assert_crash(false, "Dota2LabAiCommandSource", "Unknown command action: %s" % action)


func _emit_move_unit(world: Dota2LabWorld, command: Dictionary) -> void:
	var unit_id := str(command.get("unit_id", ""))
	var goal: Vector2 = command.get("goal", Vector2.ZERO) as Vector2
	world.issue_move(unit_id, goal)
	_record_commanded_unit(unit_id)
	_record_latest_target(unit_id, goal)
	_record_emitted_snapshot(world.tick_count, command)


func _emit_move_ids(world: Dota2LabWorld, command: Dictionary) -> void:
	var unit_ids := _string_array(command.get("unit_ids", []))
	var goal: Vector2 = command.get("goal", Vector2.ZERO) as Vector2
	world.issue_move_ids(unit_ids, goal)
	for unit_id in unit_ids:
		_record_commanded_unit(unit_id)
	_record_fanout_or_fallback_targets(world, unit_ids, goal)
	_record_emitted_snapshot(world.tick_count, command)


func _emit_move_all(world: Dota2LabWorld, command: Dictionary) -> void:
	var goal: Vector2 = command.get("goal", Vector2.ZERO) as Vector2
	var unit_ids := world.get_mobile_unit_ids()
	world.issue_move_all_mobile(goal)
	for unit_id in unit_ids:
		_record_commanded_unit(unit_id)
	_record_fanout_or_fallback_targets(world, unit_ids, goal)
	_record_emitted_snapshot(world.tick_count, command)


func _emit_cancel(world: Dota2LabWorld, command: Dictionary) -> void:
	var unit_id := str(command.get("unit_id", ""))
	world.cancel_move(unit_id)
	_record_commanded_unit(unit_id)
	_cancelled_unit_ids[unit_id] = true
	_record_emitted_snapshot(world.tick_count, command)


func _record_fanout_or_fallback_targets(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	fallback_goal: Vector2
) -> void:
	var metrics := world.get_metrics()
	var assignments: Array = metrics.get("last_fanout_assignments", []) as Array
	var seen: Dictionary = {}
	for item in assignments:
		var assignment: Dictionary = item as Dictionary
		var unit_id := str(assignment.get("unit_id", ""))
		if unit_id.is_empty():
			continue
		var assigned_target := _snapshot_to_vector(assignment.get("assigned_target", {}) as Dictionary)
		_record_latest_target(unit_id, assigned_target)
		seen[unit_id] = true
	for unit_id in unit_ids:
		if seen.has(unit_id):
			continue
		_record_latest_target(unit_id, fallback_goal)


func _record_commanded_unit(unit_id: String) -> void:
	if unit_id.is_empty():
		return
	_commanded_unit_ids[unit_id] = true


func _record_latest_target(unit_id: String, target: Vector2) -> void:
	if unit_id.is_empty():
		return
	_latest_targets_by_unit[unit_id] = target


func _record_emitted_snapshot(tick: int, command: Dictionary) -> void:
	var snapshot := {
		"tick": tick,
		"scheduled_tick": int(command.get("tick", -1)),
		"action": str(command.get("action", "")),
		"label": str(command.get("label", "")),
	}
	if command.has("unit_id"):
		snapshot["unit_id"] = str(command.get("unit_id", ""))
	if command.has("unit_ids"):
		snapshot["unit_ids"] = _string_array(command.get("unit_ids", []))
	if command.has("goal"):
		var goal: Vector2 = command.get("goal", Vector2.ZERO) as Vector2
		snapshot["goal"] = _vector_snapshot(goal)
	_emitted_snapshots.append(snapshot)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = value as Array
	for item in values:
		result.append(str(item))
	return result


func _snapshot_to_vector(snapshot: Dictionary) -> Vector2:
	return Vector2(
		float(snapshot.get("x", 0.0)),
		float(snapshot.get("y", 0.0))
	)


func _vector_snapshot(point: Vector2) -> Dictionary:
	return {
		"x": point.x,
		"y": point.y,
	}


func _sort_commands_by_tick(a: Dictionary, b: Dictionary) -> bool:
	var tick_a := int(a.get("tick", 0))
	var tick_b := int(b.get("tick", 0))
	if tick_a == tick_b:
		return str(a.get("label", "")) < str(b.get("label", ""))
	return tick_a < tick_b
