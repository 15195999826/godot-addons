class_name ZeroAdRtsLabWorld
extends RefCounted


const ObstacleScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_obstacle.gd")
const PathfinderScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_pathfinder.gd")
const MotionControllerScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_motion_controller.gd")
const UnitScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_unit.gd")

var map_size: Vector2 = Vector2(720.0, 420.0)
var obstacles: Array = []
var units: Array = []
var pathfinder: Variant = null
var motion: Variant = null
var tick_count: int = 0


func _init() -> void:
	pathfinder = PathfinderScript.new(map_size, 16.0, 11.0)
	motion = MotionControllerScript.new()
	setup_default()


func setup_default() -> void:
	obstacles = [
		ObstacleScript.new("center_block", Vector2(360.0, 210.0), Vector2(96.0, 128.0)),
		ObstacleScript.new("north_block", Vector2(360.0, 76.0), Vector2(132.0, 56.0)),
		ObstacleScript.new("south_block", Vector2(360.0, 344.0), Vector2(132.0, 56.0)),
	]
	units = [
		UnitScript.new("blue_0", "blue", Vector2(96.0, 190.0), 11.0, 96.0, true),
		UnitScript.new("blue_1", "blue", Vector2(96.0, 230.0), 11.0, 96.0, true),
		UnitScript.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	_rebuild_navigation()
	tick_count = 0


func issue_move_for_group(group_id: String, goal: Vector2) -> void:
	for unit in units:
		if unit.group_id != group_id or not unit.mobile:
			continue
		motion.issue_move_order(unit, goal, pathfinder)


func issue_move(unit_id: String, goal: Vector2) -> void:
	var unit := get_unit(unit_id)
	if unit == null:
		return
	motion.issue_move_order(unit, goal, pathfinder)


func step(delta: float) -> void:
	for unit in units:
		motion.step_unit(unit, delta, pathfinder, units)
	motion.apply_push_adjust(units, pathfinder)
	tick_count += 1


func get_unit(unit_id: String) -> Variant:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func get_metrics() -> Dictionary:
	var arrived_count := 0
	var active_count := 0
	var max_static_violation := 0.0
	for unit in units:
		if unit.arrived:
			arrived_count += 1
		if unit.has_move_order:
			active_count += 1
		for obstacle in obstacles:
			if obstacle.contains_point_with_clearance(unit.position, unit.radius):
				max_static_violation = maxf(max_static_violation, 1.0)
	return {
		"tick_count": tick_count,
		"arrived_count": arrived_count,
		"active_count": active_count,
		"short_path_requests": motion.short_path_requests,
		"long_path_requests": motion.long_path_requests,
		"blocked_moves": motion.blocked_moves,
		"applied_pushes": motion.applied_pushes,
		"rejected_pushes": motion.rejected_pushes,
		"static_violation": max_static_violation,
	}


func _rebuild_navigation() -> void:
	pathfinder.rebuild_context(obstacles)
