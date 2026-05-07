class_name ZeroAdRtsLabWorld
extends RefCounted


const MOBILE_GROUP_ID: String = "blue"
const DEFAULT_OBSTACLE_SIZE: Vector2 = Vector2(74.0, 74.0)
const DEFAULT_BLOCKER_RADIUS: float = 14.0
const PATH_REQUEST_BUDGET_PER_TICK: int = 2

var map_size: Vector2 = Vector2(720.0, 420.0)
var obstacles: Array[ZeroAdRtsLabObstacle] = []
var units: Array[ZeroAdRtsLabUnit] = []
var pathfinder: ZeroAdRtsLabPathfinder = null
var motion: ZeroAdRtsLabMotionController = null
var tick_count: int = 0
var current_target: Vector2 = Vector2(610.0, 210.0)
var _obstacle_seq: int = 0
var _blocker_seq: int = 0


func _init() -> void:
	setup_default()


func setup_default() -> void:
	_obstacle_seq = 0
	_blocker_seq = 0
	pathfinder = ZeroAdRtsLabPathfinder.new(map_size, 16.0, 11.0)
	motion = ZeroAdRtsLabMotionController.new()
	current_target = Vector2(610.0, 210.0)
	obstacles = [
		ZeroAdRtsLabObstacle.new("center_block", Vector2(360.0, 210.0), Vector2(96.0, 128.0)),
		ZeroAdRtsLabObstacle.new("north_block", Vector2(360.0, 76.0), Vector2(132.0, 56.0)),
		ZeroAdRtsLabObstacle.new("south_block", Vector2(360.0, 344.0), Vector2(132.0, 56.0)),
	]
	units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(96.0, 190.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(96.0, 230.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	_rebuild_navigation()
	tick_count = 0
	clear_traces()


func issue_move_for_group(group_id: String, goal: Vector2) -> void:
	var unit_ids: Array[String] = []
	for unit in get_mobile_units():
		if unit.group_id == group_id:
			unit_ids.append(unit.id)
	set_units_target(unit_ids, goal)


func set_group_target(target: Vector2) -> void:
	issue_move_for_group(MOBILE_GROUP_ID, target)


func set_units_target(unit_ids: Array[String], target: Vector2) -> void:
	current_target = target
	var target_units: Array[ZeroAdRtsLabUnit] = []
	for unit_id in unit_ids:
		var unit := get_unit(unit_id)
		if unit == null or not unit.mobile:
			continue
		target_units.append(unit)
	target_units.sort_custom(func(a: ZeroAdRtsLabUnit, b: ZeroAdRtsLabUnit) -> bool:
		return a.id < b.id
	)
	var offsets := _formation_offsets(target_units.size())
	for i in range(target_units.size()):
		var unit := target_units[i]
		var unit_goal := _clamp_unit_point(target + offsets[i], unit.radius)
		motion.issue_move_order(unit, unit_goal, pathfinder)


func issue_move(unit_id: String, goal: Vector2) -> void:
	var unit := get_unit(unit_id)
	if unit == null:
		return
	motion.issue_move_order(unit, goal, pathfinder)


func step(delta: float) -> void:
	pathfinder.process_path_budget(units, PATH_REQUEST_BUDGET_PER_TICK)
	motion.apply_path_results(units, pathfinder)
	var has_active_mobile := _has_active_mobile()
	if has_active_mobile:
		pathfinder.refresh_dynamic_units(units)
	for unit in get_mobile_units():
		motion.step_unit(unit, delta, pathfinder, units)
	pathfinder.refresh_dynamic_units(units)
	motion.apply_push_adjust(units, pathfinder)
	tick_count += 1


func get_mobile_units() -> Array[ZeroAdRtsLabUnit]:
	var result: Array[ZeroAdRtsLabUnit] = []
	for unit in units:
		if unit.mobile:
			result.append(unit)
	return result


func get_mobile_unit_ids() -> Array[String]:
	var result: Array[String] = []
	for unit in get_mobile_units():
		result.append(unit.id)
	return result


func get_mobile_unit_at(point: Vector2, pick_radius: float = 18.0) -> String:
	var best_id := ""
	var best_dist_sq := pick_radius * pick_radius
	for unit in get_mobile_units():
		var dist_sq: float = unit.position.distance_squared_to(point)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_id = unit.id
	return best_id


func get_mobile_units_in_rect(rect: Rect2) -> Array[String]:
	var result: Array[String] = []
	for unit in get_mobile_units():
		if rect.has_point(unit.position):
			result.append(unit.id)
	return result


func get_unit(unit_id: String) -> ZeroAdRtsLabUnit:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func add_static_obstacle(center: Vector2, size: Vector2 = DEFAULT_OBSTACLE_SIZE) -> String:
	_obstacle_seq += 1
	var obstacle_id := "custom_obstacle_%d" % _obstacle_seq
	obstacles.append(ZeroAdRtsLabObstacle.new(obstacle_id, _clamp_point_to_map(center), size))
	_rebuild_navigation()
	_replan_active_mobile()
	return obstacle_id


func add_blocker(center: Vector2, radius: float = DEFAULT_BLOCKER_RADIUS) -> String:
	_blocker_seq += 1
	var blocker_id := "custom_blocker_%d" % _blocker_seq
	units.append(ZeroAdRtsLabUnit.new(blocker_id, "red", _clamp_unit_point(center, radius), radius, 0.0, false))
	_replan_active_mobile()
	return blocker_id


func remove_nearest_editable(point: Vector2, max_distance: float = 44.0) -> String:
	var best_kind := ""
	var best_index := -1
	var best_dist_sq := max_distance * max_distance
	for i in range(obstacles.size()):
		var obstacle := obstacles[i]
		var obstacle_dist_sq: float = obstacle.center.distance_squared_to(point)
		if obstacle_dist_sq <= best_dist_sq:
			best_dist_sq = obstacle_dist_sq
			best_kind = "obstacle"
			best_index = i
	for i in range(units.size()):
		var unit := units[i]
		if unit.mobile:
			continue
		var unit_dist_sq: float = unit.position.distance_squared_to(point)
		if unit_dist_sq <= best_dist_sq:
			best_dist_sq = unit_dist_sq
			best_kind = "blocker"
			best_index = i
	if best_index < 0:
		return ""
	if best_kind == "obstacle":
		var removed_obstacle := obstacles[best_index]
		obstacles.remove_at(best_index)
		_rebuild_navigation()
		_replan_active_mobile()
		return removed_obstacle.id
	var removed_unit := units[best_index]
	units.remove_at(best_index)
	_replan_active_mobile()
	return removed_unit.id


func clear_traces() -> void:
	for unit in units:
		var next_trace := PackedVector2Array()
		next_trace.append(unit.position)
		unit.trace = next_trace


func get_metrics() -> Dictionary:
	var arrived_count := 0
	var active_count := 0
	var mobile_count := 0
	var max_static_violation := 0.0
	for unit in units:
		if unit.mobile:
			mobile_count += 1
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
		"mobile_count": mobile_count,
		"active_count": active_count,
		"short_path_requests": motion.short_path_requests,
		"long_path_requests": motion.long_path_requests,
		"path_results_applied": motion.path_results_applied,
		"path_result_failures": motion.path_result_failures,
		"path_queue_pending": int(pathfinder.path_queue_diagnostics().get("pending_count", 0)),
		"path_queue_results": int(pathfinder.path_queue_diagnostics().get("result_count", 0)),
		"path_queue_processed": int(pathfinder.path_queue_diagnostics().get("processed_count", 0)),
		"dynamic_refreshes": pathfinder.dynamic_refreshes,
		"blocked_moves": motion.blocked_moves,
		"applied_pushes": motion.applied_pushes,
		"rejected_pushes": motion.rejected_pushes,
		"push_pair_checks": motion.push_pair_checks,
		"push_grid_cells": motion.push_grid_cells,
		"static_violation": max_static_violation,
	}


func _rebuild_navigation() -> void:
	pathfinder.rebuild_context(obstacles)


func _replan_active_mobile() -> void:
	for unit in get_mobile_units():
		if unit.has_move_order:
			motion.issue_move_order(unit, unit.target, pathfinder)


func _has_active_mobile() -> bool:
	for unit in get_mobile_units():
		if unit.has_move_order:
			return true
	return false


func _formation_offsets(count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var spacing := 30.0
	var columns := int(ceil(sqrt(float(count))))
	for i in range(count):
		@warning_ignore("integer_division")
		var row: int = i / columns
		var col := i % columns
		var centered_col := float(col) - float(columns - 1) * 0.5
		var centered_row := float(row) - float(ceil(float(count) / float(columns)) - 1.0) * 0.5
		result.append(Vector2(centered_col * spacing, centered_row * spacing))
	return result


func _clamp_point_to_map(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, 0.0, map_size.x),
		clampf(point.y, 0.0, map_size.y)
	)


func _clamp_unit_point(point: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(point.x, radius, map_size.x - radius),
		clampf(point.y, radius, map_size.y - radius)
	)
