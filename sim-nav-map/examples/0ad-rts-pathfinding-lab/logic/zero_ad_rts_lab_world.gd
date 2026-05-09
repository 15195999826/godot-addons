class_name ZeroAdRtsLabWorld
extends RefCounted


const MOBILE_GROUP_ID: String = "blue"
const DEFAULT_OBSTACLE_SIZE: Vector2 = Vector2(74.0, 74.0)
const DEFAULT_BLOCKER_RADIUS: float = 14.0
const PATH_REQUEST_BUDGET_PER_TICK: int = 2
const MAX_RECENT_MOTION_UPDATES: int = 160
const MAX_RECENT_PAIR_CONTACTS: int = 160
const CONTACT_EPSILON: float = 0.05

var map_size: Vector2 = Vector2(720.0, 420.0)
var obstacles: Array[ZeroAdRtsLabObstacle] = []
var units: Array[ZeroAdRtsLabUnit] = []
var pathfinder: ZeroAdRtsLabPathfinder = null
var motion: ZeroAdRtsLabMotionController = null
var recent_motion_updates: Array[Dictionary] = []
var recent_pair_contacts: Array[Dictionary] = []
var tick_count: int = 0
var current_target: Vector2 = Vector2(610.0, 210.0)
var _obstacle_seq: int = 0
var _blocker_seq: int = 0
var _control_group_seq: int = 0


func _init() -> void:
	setup_default()


func setup_default() -> void:
	_obstacle_seq = 0
	_blocker_seq = 0
	_control_group_seq = 0
	pathfinder = ZeroAdRtsLabPathfinder.new(map_size, 16.0, 11.0)
	motion = ZeroAdRtsLabMotionController.new()
	current_target = Vector2(610.0, 210.0)
	obstacles = [
		ZeroAdRtsLabObstacle.new("center_block", Vector2(360.0, 210.0), Vector2(48.0, 128.0)),
		ZeroAdRtsLabObstacle.new("north_block", Vector2(360.0, 76.0), Vector2(132.0, 56.0)),
		ZeroAdRtsLabObstacle.new("south_block", Vector2(360.0, 344.0), Vector2(132.0, 56.0)),
	]
	units = [
		ZeroAdRtsLabUnit.new("blue_2", "blue", Vector2(56.0, 170.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_3", "blue", Vector2(56.0, 250.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(96.0, 190.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(96.0, 230.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_4", "blue", Vector2(136.0, 170.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_5", "blue", Vector2(136.0, 250.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	_rebuild_navigation()
	tick_count = 0
	recent_motion_updates.clear()
	recent_pair_contacts.clear()
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
	var assigned_offsets := _assign_formation_offsets(target_units, target, offsets)
	var control_group_id := ""
	if target_units.size() > 1:
		_control_group_seq += 1
		control_group_id = "formation_%d" % _control_group_seq
	for i in range(target_units.size()):
		var unit := target_units[i]
		var unit_goal := _clamp_unit_point(target + assigned_offsets[i], unit.radius)
		unit.control_group_id = control_group_id
		unit.begin_move_order(unit_goal, tick_count)
		motion.start_move_order(unit, pathfinder, tick_count)


func issue_move(unit_id: String, goal: Vector2) -> void:
	var unit := get_unit(unit_id)
	if unit == null:
		return
	unit.control_group_id = ""
	unit.begin_move_order(goal, tick_count)
	motion.start_move_order(unit, pathfinder, tick_count)


func step(delta: float) -> void:
	var previous_positions := _unit_position_snapshot()
	var previous_move_orders := _unit_move_order_snapshot()
	pathfinder.process_path_budget(units, PATH_REQUEST_BUDGET_PER_TICK)
	motion.apply_path_results(units, pathfinder, tick_count)
	_dispatch_motion_updates()
	var has_active_mobile := _has_active_mobile()
	if has_active_mobile:
		pathfinder.refresh_dynamic_units(units)
		for unit in units:
			if not unit.mobile:
				continue
			motion.step_unit(unit, delta, pathfinder, units, tick_count)
		_dispatch_motion_updates()
		pathfinder.refresh_dynamic_units(units)
		motion.apply_push_adjust(units, pathfinder, previous_positions, previous_move_orders, tick_count, delta)
		_record_pair_contact_diagnostics(previous_positions, previous_move_orders)
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
	var pathless_active_count := 0
	var mobile_count := 0
	var max_static_violation := 0.0
	for unit in units:
		if unit.mobile:
			mobile_count += 1
			if unit.arrived:
				arrived_count += 1
		if unit.has_move_order:
			active_count += 1
			if not unit.has_path() and unit.pending_long_ticket == 0 and unit.pending_short_ticket == 0:
				pathless_active_count += 1
		for obstacle in obstacles:
			if obstacle.contains_point_with_clearance(unit.position, unit.radius):
				max_static_violation = maxf(max_static_violation, 1.0)
	return {
		"tick_count": tick_count,
		"arrived_count": arrived_count,
		"mobile_count": mobile_count,
		"active_count": active_count,
		"pathless_active_count": pathless_active_count,
		"short_path_requests": motion.short_path_requests,
		"long_path_requests": motion.long_path_requests,
		"path_results_applied": motion.path_results_applied,
		"path_result_failures": motion.path_result_failures,
		"path_queue_pending": int(pathfinder.path_queue_diagnostics().get("pending_count", 0)),
		"path_queue_results": int(pathfinder.path_queue_diagnostics().get("result_count", 0)),
		"path_queue_processed": int(pathfinder.path_queue_diagnostics().get("processed_count", 0)),
		"dynamic_refreshes": pathfinder.dynamic_refreshes,
		"blocked_moves": motion.blocked_moves,
		"move_failures": motion.move_failures,
		"obstructed_notifications": motion.obstructed_notifications,
		"very_obstructed_notifications": motion.very_obstructed_notifications,
		"repath_suppressed": motion.repath_suppressed,
		"obsolete_path_requests": motion.obsolete_path_requests,
		"known_imperfect_paths": motion.known_imperfect_paths,
		"known_imperfect_suppressed": motion.known_imperfect_suppressed,
		"applied_pushes": motion.applied_pushes,
		"rejected_pushes": motion.rejected_pushes,
		"crossing_nudges": motion.crossing_nudges,
		"goal_opposing_push_dampens": motion.goal_opposing_push_dampens,
		"push_pressure_obstructions": motion.push_pressure_obstructions,
		"push_pair_checks": motion.push_pair_checks,
		"push_grid_cells": motion.push_grid_cells,
		"pair_contact_events": recent_pair_contacts.size(),
		"static_violation": max_static_violation,
	}


func _rebuild_navigation() -> void:
	pathfinder.rebuild_context(obstacles)


func _replan_active_mobile() -> void:
	for unit in get_mobile_units():
		if unit.has_move_order:
			motion.replan_active_order(unit, pathfinder, tick_count)


func _has_active_mobile() -> bool:
	for unit in units:
		if unit.mobile and unit.has_move_order:
			return true
	return false


func _dispatch_motion_updates() -> void:
	var updates := motion.drain_motion_updates()
	for update in updates:
		var unit := get_unit(update.actor_id)
		if unit == null:
			continue
		unit.on_motion_update(update)
		recent_motion_updates.append(update.to_snapshot())
		while recent_motion_updates.size() > MAX_RECENT_MOTION_UPDATES:
			recent_motion_updates.pop_front()


func _unit_position_snapshot() -> Dictionary:
	var result := {}
	for unit in units:
		result[unit.id] = unit.position
	return result


func _unit_move_order_snapshot() -> Dictionary:
	var result := {}
	for unit in units:
		result[unit.id] = unit.has_move_order
	return result


func _record_pair_contact_diagnostics(previous_positions: Dictionary, previous_move_orders: Dictionary) -> void:
	for i in range(units.size()):
		var unit_a := units[i]
		if not unit_a.mobile or not unit_a.blocks_pathfinding:
			continue
		if not previous_positions.has(unit_a.id):
			continue
		for j in range(i + 1, units.size()):
			var unit_b := units[j]
			if not unit_b.mobile or not unit_b.blocks_pathfinding:
				continue
			if not previous_positions.has(unit_b.id):
				continue
			var previous_a: Vector2 = previous_positions[unit_a.id] as Vector2
			var previous_b: Vector2 = previous_positions[unit_b.id] as Vector2
			var moved_a := previous_a.distance_to(unit_a.position)
			var moved_b := previous_b.distance_to(unit_b.position)
			if moved_a <= CONTACT_EPSILON and moved_b <= CONTACT_EPSILON:
				continue
			var combined_radius := unit_a.radius + unit_b.radius
			var final_distance := unit_a.position.distance_to(unit_b.position)
			var closest_distance := _closest_segment_distance(
				previous_a,
				unit_a.position,
				previous_b,
				unit_b.position
			)
			if final_distance >= combined_radius and closest_distance >= combined_radius:
				continue
			var previous_delta := previous_a - previous_b
			var current_delta := unit_a.position - unit_b.position
			var contact_kind := "unit_overlap_after_step"
			if final_distance >= combined_radius:
				contact_kind = "unit_segment_overlap"
			if previous_delta.dot(current_delta) < 0.0:
				contact_kind = "unit_pass_through_risk"
			_record_pair_contact(unit_a, unit_b, contact_kind, {
				"previous_a": previous_a,
				"previous_b": previous_b,
				"current_a": unit_a.position,
				"current_b": unit_b.position,
				"moved_a": moved_a,
				"moved_b": moved_b,
				"combined_radius": combined_radius,
				"final_distance": final_distance,
				"closest_segment_distance": closest_distance,
				"a_has_move_order": unit_a.has_move_order,
				"b_has_move_order": unit_b.has_move_order,
				"a_was_moving_this_tick": bool(previous_move_orders.get(unit_a.id, unit_a.has_move_order)),
				"b_was_moving_this_tick": bool(previous_move_orders.get(unit_b.id, unit_b.has_move_order)),
				"a_control_group_id": unit_a.control_group_id,
				"b_control_group_id": unit_b.control_group_id,
				"a_pushing_pressure": unit_a.pushing_pressure,
				"b_pushing_pressure": unit_b.pushing_pressure,
			})


func _record_pair_contact(
	unit_a: ZeroAdRtsLabUnit,
	unit_b: ZeroAdRtsLabUnit,
	kind: String,
	details: Dictionary
) -> void:
	var entry := {
		"tick": tick_count,
		"kind": kind,
		"unit_a": unit_a.id,
		"unit_b": unit_b.id,
		"unit_a_order_id": unit_a.active_order_id(),
		"unit_b_order_id": unit_b.active_order_id(),
	}
	for key in details.keys():
		entry[key] = details[key]
	recent_pair_contacts.append(entry)
	while recent_pair_contacts.size() > MAX_RECENT_PAIR_CONTACTS:
		recent_pair_contacts.pop_front()


func _closest_segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	var best := INF
	best = minf(best, _point_segment_distance(a0, b0, b1))
	best = minf(best, _point_segment_distance(a1, b0, b1))
	best = minf(best, _point_segment_distance(b0, a0, a1))
	best = minf(best, _point_segment_distance(b1, a0, a1))
	if _segments_intersect(a0, a1, b0, b1):
		return 0.0
	return best


func _point_segment_distance(point: Vector2, segment_a: Vector2, segment_b: Vector2) -> float:
	var segment := segment_b - segment_a
	var length_sq := segment.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(segment_a)
	var t := clampf((point - segment_a).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(segment_a + segment * t)


func _segments_intersect(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var d1 := _cross_2d(a1 - a0, b0 - a0)
	var d2 := _cross_2d(a1 - a0, b1 - a0)
	var d3 := _cross_2d(b1 - b0, a0 - b0)
	var d4 := _cross_2d(b1 - b0, a1 - b0)
	return d1 * d2 <= 0.0 and d3 * d4 <= 0.0


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


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


func _assign_formation_offsets(
	target_units: Array[ZeroAdRtsLabUnit],
	target: Vector2,
	offsets: Array[Vector2]
) -> Array[Vector2]:
	if target_units.size() != offsets.size() or target_units.is_empty():
		return offsets
	if target_units.size() > 8:
		return _assign_formation_offsets_greedy(target_units, target, offsets)
	var used: Array[bool] = []
	for _i in range(offsets.size()):
		used.append(false)
	var current: Array[Vector2] = []
	var best := {
		"cost": INF,
		"offsets": [],
	}
	_search_formation_assignment(target_units, target, offsets, used, current, 0, 0.0, best)
	var best_offsets: Array = best.get("offsets", [])
	if best_offsets.size() != offsets.size():
		return offsets
	var result: Array[Vector2] = []
	for slot_offset in best_offsets:
		result.append(slot_offset as Vector2)
	return result


func _search_formation_assignment(
	target_units: Array[ZeroAdRtsLabUnit],
	target: Vector2,
	offsets: Array[Vector2],
	used: Array[bool],
	current: Array[Vector2],
	index: int,
	cost: float,
	best: Dictionary
) -> void:
	if index >= target_units.size():
		if cost < float(best.get("cost", INF)):
			best["cost"] = cost
			best["offsets"] = current.duplicate()
		return
	if cost >= float(best.get("cost", INF)):
		return
	var unit := target_units[index]
	for i in range(offsets.size()):
		if used[i]:
			continue
		var slot_offset := offsets[i]
		var slot_position := target + slot_offset
		used[i] = true
		current.append(slot_offset)
		_search_formation_assignment(
			target_units,
			target,
			offsets,
			used,
			current,
			index + 1,
			cost + unit.position.distance_squared_to(slot_position),
			best
		)
		current.pop_back()
		used[i] = false


func _assign_formation_offsets_greedy(
	target_units: Array[ZeroAdRtsLabUnit],
	target: Vector2,
	offsets: Array[Vector2]
) -> Array[Vector2]:
	var remaining: Array[Vector2] = offsets.duplicate()
	var result: Array[Vector2] = []
	for unit in target_units:
		var best_index := 0
		var best_cost := INF
		for i in range(remaining.size()):
			var slot_offset := remaining[i]
			var slot_cost := unit.position.distance_squared_to(target + slot_offset)
			if slot_cost < best_cost:
				best_cost = slot_cost
				best_index = i
		result.append(remaining[best_index])
		remaining.remove_at(best_index)
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
