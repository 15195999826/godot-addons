class_name RtsPathfindingLabWorld
extends RefCounted


const LabObstacle := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

const MOBILE_GROUP_ID: String = "blue"
const REPLAN_INTERVAL: float = 0.45
const ARRIVE_EPSILON: float = 8.0

var map_size: Vector2 = Vector2(720.0, 420.0)
var obstacles: Array[RtsPathfindingLabObstacle] = []
var units: Array[RtsPathfindingLabUnit] = []
var pathfinder: RtsPathfindingLabPathfinder = null
var group_filter_enabled: bool = true
var avoid_moving_units_enabled: bool = true
var current_target: Vector2 = Vector2(610.0, 210.0)
var tick_count: int = 0
var _obstacle_seq: int = 0
var _blocker_seq: int = 0


func _init() -> void:
	pathfinder = LabPathfinder.new(map_size, 16.0, 11.0)


func setup_default() -> void:
	_obstacle_seq = 0
	_blocker_seq = 0
	obstacles = [
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("south_wall", Vector2(340.0, 345.0), Vector2(120.0, 80.0)),
	]
	units = []
	var starts: Array[Vector2] = [
		Vector2(74.0, 162.0),
		Vector2(104.0, 162.0),
		Vector2(74.0, 202.0),
		Vector2(104.0, 202.0),
		Vector2(74.0, 242.0),
		Vector2(104.0, 242.0),
	]
	for i in range(starts.size()):
		units.append(LabUnit.new("blue_%d" % i, MOBILE_GROUP_ID, starts[i], 11.0, 98.0, true))
	units.append(LabUnit.new("red_blocker_n", "red", Vector2(455.0, 145.0), 14.0, 0.0, false))
	units.append(LabUnit.new("red_blocker_s", "red", Vector2(455.0, 275.0), 14.0, 0.0, false))
	current_target = Vector2(610.0, 210.0)
	tick_count = 0
	set_group_target(current_target)


func set_group_target(target: Vector2) -> void:
	var unit_ids: Array[String] = []
	for unit in get_mobile_units():
		unit_ids.append(unit.id)
	set_units_target(unit_ids, target)


func set_units_target(unit_ids: Array[String], target: Vector2) -> void:
	current_target = target
	var target_units: Array[RtsPathfindingLabUnit] = []
	for unit_id in unit_ids:
		var unit := get_unit_by_id(unit_id)
		if unit != null and unit.mobile:
			target_units.append(unit)
	target_units.sort_custom(func(a: RtsPathfindingLabUnit, b: RtsPathfindingLabUnit) -> bool:
		return a.id < b.id
	)
	var offsets := _formation_offsets(target_units.size())
	for i in range(target_units.size()):
		var unit := target_units[i]
		unit.target = _clamp_to_map(target + offsets[i])
		unit.arrived = false
		unit.replan_timer = REPLAN_INTERVAL
		_plan_unit(unit)


func step(delta: float) -> void:
	tick_count += 1
	var mobile_units := get_mobile_units()
	mobile_units.sort_custom(func(a: RtsPathfindingLabUnit, b: RtsPathfindingLabUnit) -> bool:
		return a.id < b.id
	)
	for unit in mobile_units:
		if unit.arrived:
			continue
		unit.replan_timer += delta
		if unit.replan_timer >= REPLAN_INTERVAL or unit.path_index >= unit.path.size():
			_plan_unit(unit)
		_move_unit(unit, delta)
	_resolve_overlaps()
	for unit in mobile_units:
		_push_out_static_obstacles(unit)
		if unit.position.distance_to(unit.target) > ARRIVE_EPSILON:
			unit.arrived = false
		unit.append_trace_point()


func get_mobile_units() -> Array[RtsPathfindingLabUnit]:
	var result: Array[RtsPathfindingLabUnit] = []
	for unit in units:
		if unit.mobile:
			result.append(unit)
	return result


func get_unit_by_id(unit_id: String) -> RtsPathfindingLabUnit:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func get_mobile_unit_ids() -> Array[String]:
	var result: Array[String] = []
	for unit in get_mobile_units():
		result.append(unit.id)
	return result


func get_mobile_unit_at(point: Vector2, pick_radius: float = 18.0) -> String:
	var best_id: String = ""
	var best_dist_sq := pick_radius * pick_radius
	for unit in get_mobile_units():
		var dist_sq := unit.position.distance_squared_to(point)
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


func add_static_obstacle(center: Vector2, size: Vector2 = Vector2(74.0, 74.0)) -> String:
	_obstacle_seq += 1
	var obstacle_id := "custom_obstacle_%d" % _obstacle_seq
	obstacles.append(LabObstacle.new(obstacle_id, _clamp_to_map(center), size))
	_replan_all_mobile()
	return obstacle_id


func add_blocker(center: Vector2, radius: float = 14.0) -> String:
	_blocker_seq += 1
	var blocker_id := "custom_blocker_%d" % _blocker_seq
	units.append(LabUnit.new(blocker_id, "red", _clamp_to_map(center), radius, 0.0, false))
	_replan_all_mobile()
	return blocker_id


func remove_nearest_editable(point: Vector2, max_distance: float = 44.0) -> String:
	var best_kind := ""
	var best_index := -1
	var best_dist_sq := max_distance * max_distance
	for i in range(obstacles.size()):
		var obstacle := obstacles[i]
		var dist_sq := obstacle.center.distance_squared_to(point)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_kind = "obstacle"
			best_index = i
	for i in range(units.size()):
		var unit := units[i]
		if unit.mobile:
			continue
		var dist_sq := unit.position.distance_squared_to(point)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_kind = "blocker"
			best_index = i
	if best_index < 0:
		return ""
	if best_kind == "obstacle":
		var removed_obstacle := obstacles[best_index]
		obstacles.remove_at(best_index)
		_replan_all_mobile()
		return removed_obstacle.id
	var removed_unit := units[best_index]
	units.remove_at(best_index)
	_replan_all_mobile()
	return removed_unit.id


func clear_traces() -> void:
	for unit in units:
		unit.trace = [unit.position]


func all_mobile_arrived() -> bool:
	for unit in get_mobile_units():
		if not unit.arrived:
			return false
	return true


func analyze_movement() -> Dictionary:
	var mobile_units := get_mobile_units()
	var arrived_count := 0
	var max_final_error := 0.0
	var min_pair_distance := INF
	var max_overlap := 0.0
	var obstacle_violations := 0
	var trace_points := 0
	for unit in mobile_units:
		if unit.arrived:
			arrived_count += 1
		max_final_error = maxf(max_final_error, unit.position.distance_to(unit.target))
		trace_points += unit.trace.size()
		for point in unit.trace:
			for obstacle in obstacles:
				if obstacle.get_inflated_rect(unit.radius).has_point(point):
					obstacle_violations += 1

	for i in range(mobile_units.size()):
		for j in range(i + 1, mobile_units.size()):
			var a := mobile_units[i]
			var b := mobile_units[j]
			var dist := a.position.distance_to(b.position)
			min_pair_distance = minf(min_pair_distance, dist)
			max_overlap = maxf(max_overlap, a.radius + b.radius - dist)

	return {
		"mobile_count": mobile_units.size(),
		"arrived_count": arrived_count,
		"max_final_error": max_final_error,
		"min_pair_distance": min_pair_distance,
		"max_overlap": maxf(max_overlap, 0.0),
		"obstacle_violations": obstacle_violations,
		"trace_points": trace_points,
		"ticks": tick_count,
	}


func _plan_unit(unit: RtsPathfindingLabUnit) -> void:
	var others: Array[RtsPathfindingLabUnit] = []
	for candidate in units:
		if candidate.id != unit.id:
			others.append(candidate)
	var planned_path := pathfinder.plan_path(
		unit.position,
		unit.target,
		obstacles,
		others,
		unit.group_id,
		avoid_moving_units_enabled,
		group_filter_enabled
	)
	unit.set_path(planned_path)
	unit.replan_timer = 0.0


func _replan_all_mobile() -> void:
	for unit in get_mobile_units():
		unit.replan_timer = REPLAN_INTERVAL
		_plan_unit(unit)


func _move_unit(unit: RtsPathfindingLabUnit, delta: float) -> void:
	if unit.path.is_empty():
		unit.arrived = unit.position.distance_to(unit.target) <= ARRIVE_EPSILON
		return
	var waypoint := unit.current_waypoint()
	var to_waypoint := waypoint - unit.position
	var max_step := unit.speed * delta
	if to_waypoint.length() <= max_step:
		unit.position = waypoint
		unit.path_index += 1
	else:
		unit.position += to_waypoint.normalized() * max_step

	if unit.path_index >= unit.path.size() and unit.position.distance_to(unit.target) <= ARRIVE_EPSILON:
		unit.position = unit.target
		unit.arrived = true


func _resolve_overlaps() -> void:
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			var a := units[i]
			var b := units[j]
			var min_dist := a.radius + b.radius
			var delta := b.position - a.position
			var dist := delta.length()
			if dist >= min_dist or dist <= 0.0001:
				continue
			var dir := delta / dist
			var push := (min_dist - dist) + 0.1
			if a.mobile and b.mobile:
				a.position -= dir * push * 0.5
				b.position += dir * push * 0.5
			elif a.mobile:
				a.position -= dir * push
			elif b.mobile:
				b.position += dir * push
			a.position = _clamp_to_map(a.position)
			b.position = _clamp_to_map(b.position)


func _push_out_static_obstacles(unit: RtsPathfindingLabUnit) -> void:
	for obstacle in obstacles:
		var rect := obstacle.get_inflated_rect(unit.radius)
		if not rect.has_point(unit.position):
			continue
		var left := absf(unit.position.x - rect.position.x)
		var right := absf(rect.position.x + rect.size.x - unit.position.x)
		var top := absf(unit.position.y - rect.position.y)
		var bottom := absf(rect.position.y + rect.size.y - unit.position.y)
		var min_side := minf(minf(left, right), minf(top, bottom))
		if is_equal_approx(min_side, left):
			unit.position.x = rect.position.x - 0.5
		elif is_equal_approx(min_side, right):
			unit.position.x = rect.position.x + rect.size.x + 0.5
		elif is_equal_approx(min_side, top):
			unit.position.y = rect.position.y - 0.5
		else:
			unit.position.y = rect.position.y + rect.size.y + 0.5
		unit.position = _clamp_to_map(unit.position)


func _formation_offsets(count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var spacing := 30.0
	var columns := 3
	for i in range(count):
		@warning_ignore("integer_division")
		var row := i / columns
		var col := i % columns
		result.append(Vector2((float(col) - 1.0) * spacing, (float(row) - 0.5) * spacing))
	return result


func _clamp_to_map(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 0.0, map_size.x), clampf(point.y, 0.0, map_size.y))
