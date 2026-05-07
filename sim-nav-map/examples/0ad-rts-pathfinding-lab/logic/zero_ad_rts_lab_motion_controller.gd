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

var short_path_requests: int = 0
var long_path_requests: int = 0
var blocked_moves: int = 0
var rejected_pushes: int = 0
var applied_pushes: int = 0


func issue_move_order(
	unit: Variant,
	goal: Vector2,
	pathfinder: Variant
) -> void:
	unit.begin_move_order(goal)
	_request_long_path(unit, goal, pathfinder)


func step_unit(
	unit: Variant,
	delta: float,
	pathfinder: Variant,
	units: Array
) -> void:
	if not unit.mobile or not unit.has_move_order:
		return
	if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON and not unit.has_path():
		unit.finish_move_order()
		return

	_maybe_request_short_path_for_long_segment(unit, pathfinder, units)
	if not unit.has_path():
		_request_long_path(unit, unit.target, pathfinder)
		if not unit.has_path():
			_handle_blocked_move(unit, pathfinder, units)
			return

	var waypoint: Vector2 = unit.current_waypoint()
	var to_waypoint: Vector2 = waypoint - unit.position
	var max_step: float = unit.speed * delta
	var candidate: Vector2 = waypoint
	if to_waypoint.length() > max_step:
		candidate = unit.position + to_waypoint.normalized() * max_step
	var line_result: SimNavMovementLineResult = pathfinder.validate_movement_line(unit, unit.position, candidate, units)
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
	units: Array,
	pathfinder: Variant
) -> void:
	var pushes: Dictionary = {}
	for unit in units:
		pushes[unit.id] = Vector2.ZERO
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			_accumulate_pair_push(units[i], units[j], pushes)
	for unit in units:
		var push_vec: Vector2 = pushes.get(unit.id, Vector2.ZERO)
		if push_vec.length() <= MIN_PUSH:
			continue
		if push_vec.length() > PUSH_MAX_PER_FRAME:
			push_vec = push_vec.normalized() * PUSH_MAX_PER_FRAME
		var candidate: Vector2 = unit.position + push_vec
		var line_result: SimNavMovementLineResult = pathfinder.validate_movement_line(unit, unit.position, candidate, units)
		if line_result.is_success():
			unit.position = candidate
			unit.remember_position()
			applied_pushes += 1
		else:
			unit.was_obstructed = true
			rejected_pushes += 1


func _request_long_path(
	unit: Variant,
	goal: Vector2,
	pathfinder: Variant
) -> void:
	long_path_requests += 1
	var result: SimNavLongPathResult = pathfinder.compute_long_path(unit, goal)
	if result.is_success():
		unit.long_path = result.path
		unit.short_path = SimNavWaypointPath.new()
		unit.path_target = result.canonical_goal.center if result.canonical_goal != null else goal
	else:
		unit.long_path = SimNavWaypointPath.new()
		unit.path_target = goal


func _request_short_path(
	unit: Variant,
	goal: SimNavPathGoal,
	pathfinder: Variant,
	units: Array,
	search_range: float = SHORT_PATH_RANGE
) -> void:
	short_path_requests += 1
	var result: SimNavShortPathResult = pathfinder.compute_short_path(unit, goal, units, search_range)
	if result.is_success():
		unit.short_path = result.path


func _maybe_request_short_path_for_long_segment(
	unit: Variant,
	pathfinder: Variant,
	units: Array
) -> void:
	if unit.short_path != null and not unit.short_path.is_empty():
		return
	if unit.long_path == null or unit.long_path.is_empty():
		return
	var next_long: Vector2 = unit.long_path.back()
	var unit_line: SimNavMovementLineResult = pathfinder.validate_unit_line(unit, unit.position, next_long, units)
	if unit_line.is_success():
		return
	var goal := SimNavPathGoal.circle(next_long, LONG_SEGMENT_LOOKAHEAD_RADIUS)
	_request_short_path(unit, goal, pathfinder, units)


func _handle_blocked_move(
	unit: Variant,
	pathfinder: Variant,
	units: Array
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


func _accumulate_pair_push(
	a: Variant,
	b: Variant,
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
