class_name ZeroAdRtsLabMotionController
extends RefCounted


const ARRIVE_EPSILON: float = 8.0
const SHORT_PATH_RANGE: float = 192.0
const LONG_SEGMENT_LOOKAHEAD_RADIUS: float = 32.0
const FAILED_BEFORE_SHORT_PATH: int = 2
const FAILED_BEFORE_LONG_REFRESH: int = 12
const PUSH_RADIUS_MULTIPLIER: float = 1.05
const PUSH_MAX_PER_FRAME: float = 6.0
const MIN_PUSH: float = 0.05
const PUSH_BUCKET_SIZE: float = 48.0
const SHORT_REPATH_COOLDOWN_SEC: float = 0.22

var short_path_requests: int = 0
var long_path_requests: int = 0
var blocked_moves: int = 0
var rejected_pushes: int = 0
var applied_pushes: int = 0
var path_results_applied: int = 0
var path_result_failures: int = 0
var push_pair_checks: int = 0
var push_grid_cells: int = 0


func issue_move_order(
	unit: ZeroAdRtsLabUnit,
	goal: Vector2,
	pathfinder: ZeroAdRtsLabPathfinder
) -> void:
	_cancel_pending_path_requests(unit, pathfinder)
	unit.begin_move_order(goal)
	_request_long_path(unit, goal, pathfinder)


func apply_path_results(
	units: Array[ZeroAdRtsLabUnit],
	pathfinder: ZeroAdRtsLabPathfinder
) -> void:
	for unit in units:
		if unit.pending_long_ticket > 0:
			var long_result := pathfinder.take_long_path_result(unit.pending_long_ticket)
			if long_result != null:
				unit.pending_long_ticket = 0
				_apply_long_path_result(unit, long_result)
		if unit.pending_short_ticket > 0:
			var short_result := pathfinder.take_short_path_result(unit.pending_short_ticket)
			if short_result != null:
				unit.pending_short_ticket = 0
				_apply_short_path_result(unit, short_result)


func step_unit(
	unit: ZeroAdRtsLabUnit,
	delta: float,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit]
) -> void:
	if not unit.mobile or not unit.has_move_order:
		return
	unit.short_repath_cooldown = maxf(0.0, unit.short_repath_cooldown - delta)
	if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON and not unit.has_path():
		unit.finish_move_order()
		return

	_maybe_request_short_path_for_long_segment(unit, pathfinder, units)
	if not unit.has_path():
		if unit.pending_long_ticket == 0 and unit.pending_short_ticket == 0:
			_request_long_path(unit, unit.target, pathfinder)
		return

	var waypoint: Vector2 = unit.current_waypoint()
	var to_waypoint: Vector2 = waypoint - unit.position
	var max_step: float = unit.speed * delta
	var candidate: Vector2 = waypoint
	if to_waypoint.length() > max_step:
		candidate = unit.position + to_waypoint.normalized() * max_step
	var line_result := pathfinder.validate_movement_line(unit, unit.position, candidate, units, false)
	if line_result.is_success():
		unit.position = candidate
		unit.remember_position()
		unit.failed_movements = 0
		unit.was_obstructed = false
		if unit.position.distance_to(waypoint) <= ARRIVE_EPSILON:
			unit.consume_current_waypoint()
		if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON and not unit.has_path():
			unit.finish_move_order()
		return
	_handle_blocked_move(unit, pathfinder, units)


func apply_push_adjust(
	units: Array[ZeroAdRtsLabUnit],
	pathfinder: ZeroAdRtsLabPathfinder
) -> void:
	var pushes: Dictionary = {}
	for unit in units:
		pushes[unit.id] = Vector2.ZERO
	push_pair_checks = 0
	var buckets := _build_push_buckets(units)
	push_grid_cells = buckets.size()
	for unit in units:
		for other in _nearby_push_units(unit, buckets):
			if unit.id >= other.id:
				continue
			push_pair_checks += 1
			_accumulate_pair_push(unit, other, pushes)
	for unit in units:
		var push_vec: Vector2 = pushes.get(unit.id, Vector2.ZERO)
		if push_vec.length() <= MIN_PUSH:
			continue
		if push_vec.length() > PUSH_MAX_PER_FRAME:
			push_vec = push_vec.normalized() * PUSH_MAX_PER_FRAME
		var candidate: Vector2 = unit.position + push_vec
		var line_result := pathfinder.validate_movement_line(unit, unit.position, candidate, units, false)
		if line_result.is_success():
			unit.position = candidate
			unit.remember_position()
			applied_pushes += 1
		else:
			unit.was_obstructed = true
			rejected_pushes += 1


func _request_long_path(
	unit: ZeroAdRtsLabUnit,
	goal: Vector2,
	pathfinder: ZeroAdRtsLabPathfinder
) -> void:
	long_path_requests += 1
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
	unit.pending_long_ticket = pathfinder.enqueue_long_path(unit, goal)


func _apply_long_path_result(unit: ZeroAdRtsLabUnit, result: SimNavLongPathResult) -> void:
	path_results_applied += 1
	if result.is_success():
		unit.long_path = result.path
		unit.short_path = SimNavWaypointPath.new()
		unit.path_target = result.canonical_goal.center if result.canonical_goal != null else unit.target
	else:
		path_result_failures += 1
		unit.long_path = SimNavWaypointPath.new()
		unit.path_target = unit.target


func _request_short_path(
	unit: ZeroAdRtsLabUnit,
	goal: SimNavPathGoal,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	search_range: float = SHORT_PATH_RANGE
) -> void:
	if unit.pending_short_ticket > 0:
		return
	if unit.short_repath_cooldown > 0.0:
		return
	short_path_requests += 1
	unit.pending_short_ticket = pathfinder.enqueue_short_path(unit, goal, units, search_range)
	unit.short_repath_cooldown = SHORT_REPATH_COOLDOWN_SEC


func _apply_short_path_result(unit: ZeroAdRtsLabUnit, result: SimNavShortPathResult) -> void:
	path_results_applied += 1
	if result.is_success():
		unit.short_path = result.path
	else:
		path_result_failures += 1


func _maybe_request_short_path_for_long_segment(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit]
) -> void:
	if unit.short_path != null and not unit.short_path.is_empty():
		return
	if unit.pending_short_ticket > 0:
		return
	if unit.long_path == null or unit.long_path.is_empty():
		return
	var next_long: Vector2 = unit.long_path.back()
	var unit_line := pathfinder.validate_unit_line(unit, unit.position, next_long, units, false)
	if unit_line.is_success():
		return
	var goal := SimNavPathGoal.circle(next_long, LONG_SEGMENT_LOOKAHEAD_RADIUS)
	_request_short_path(unit, goal, pathfinder, units)


func _handle_blocked_move(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit]
) -> void:
	blocked_moves += 1
	unit.was_obstructed = true
	unit.failed_movements += 1
	if unit.failed_movements >= FAILED_BEFORE_LONG_REFRESH:
		unit.failed_movements = 0
		_request_long_path(unit, unit.target, pathfinder)
		return
	if unit.failed_movements >= FAILED_BEFORE_SHORT_PATH:
		var goal := SimNavPathGoal.circle(unit.current_waypoint(), LONG_SEGMENT_LOOKAHEAD_RADIUS)
		_request_short_path(unit, goal, pathfinder, units)


func _cancel_pending_path_requests(unit: ZeroAdRtsLabUnit, pathfinder: ZeroAdRtsLabPathfinder) -> void:
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
	if unit.pending_short_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_short_ticket)
		unit.pending_short_ticket = 0


func _accumulate_pair_push(
	a: ZeroAdRtsLabUnit,
	b: ZeroAdRtsLabUnit,
	pushes: Dictionary
) -> void:
	if not a.blocks_pathfinding or not b.blocks_pathfinding:
		return
	var delta: Vector2 = a.position - b.position
	var distance: float = delta.length()
	var min_distance: float = (a.radius + b.radius) * PUSH_RADIUS_MULTIPLIER
	if distance >= min_distance:
		return
	var direction := Vector2.RIGHT
	if distance > 0.001:
		direction = delta / distance
	var overlap: float = min_distance - distance
	var both_moving: bool = a.has_move_order and b.has_move_order
	var same_group: bool = a.group_id != "" and a.group_id == b.group_id
	if not both_moving and not same_group:
		return
	var amount: float = overlap * 0.5
	pushes[a.id] = (pushes.get(a.id, Vector2.ZERO) as Vector2) + direction * amount
	pushes[b.id] = (pushes.get(b.id, Vector2.ZERO) as Vector2) - direction * amount


func _build_push_buckets(units: Array[ZeroAdRtsLabUnit]) -> Dictionary:
	var buckets := {}
	for unit in units:
		if not unit.blocks_pathfinding:
			continue
		var coord := _push_bucket_coord(unit.position)
		if not buckets.has(coord):
			buckets[coord] = []
		var bucket_units: Array = buckets[coord]
		bucket_units.append(unit)
	return buckets


func _nearby_push_units(unit: ZeroAdRtsLabUnit, buckets: Dictionary) -> Array[ZeroAdRtsLabUnit]:
	var result: Array[ZeroAdRtsLabUnit] = []
	var origin := _push_bucket_coord(unit.position)
	for offset in _push_bucket_neighbor_offsets():
		var coord := origin + offset
		if not buckets.has(coord):
			continue
		var bucket_units: Array = buckets[coord]
		for other in bucket_units:
			result.append(other)
	return result


func _push_bucket_coord(point: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(point.x / PUSH_BUCKET_SIZE)),
		int(floor(point.y / PUSH_BUCKET_SIZE))
	)


func _push_bucket_neighbor_offsets() -> Array[Vector2i]:
	return [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
