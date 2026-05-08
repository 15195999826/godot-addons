class_name ZeroAdRtsLabMotionController
extends RefCounted


const ARRIVE_EPSILON: float = 8.0
const NAVCELL_SIZE: float = 16.0
const SHORT_PATH_MIN_SEARCH_RANGE: float = 12.0 * NAVCELL_SIZE
const SHORT_PATH_MAX_SEARCH_RANGE: float = 56.0 * NAVCELL_SIZE
const SHORT_PATH_SEARCH_RANGE_INCREMENT: float = 4.0 * NAVCELL_SIZE
const SHORT_PATH_SEARCH_RANGE_INCREASE_DELAY: int = 1
const SHORT_PATH_LONG_WAYPOINT_RANGE: float = 4.0 * NAVCELL_SIZE
const LONG_PATH_MIN_DIST: float = 16.0 * NAVCELL_SIZE
const DIRECT_PATH_RANGE: float = 24.0 * NAVCELL_SIZE
const KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN: int = 12
const MAX_FAILED_MOVEMENTS: int = 35
const ALTERNATE_PATH_TYPE_DELAY: int = 3
const ALTERNATE_PATH_TYPE_EVERY: int = 6
const BACKUP_HACK_DELAY: int = 10
const BACKUP_HACK_DISTANCE: float = 1.0
const VERY_OBSTRUCTED_THRESHOLD: int = 10
const PUSH_RADIUS_MULTIPLIER: float = 1.05
const PUSH_MAX_PER_FRAME: float = 6.0
const MIN_PUSH: float = 0.05
const PUSH_BUCKET_SIZE: float = 48.0
const SHORT_REPATH_COOLDOWN_SEC: float = 0.22

var short_path_requests: int = 0
var long_path_requests: int = 0
var blocked_moves: int = 0
var move_failures: int = 0
var obstructed_notifications: int = 0
var very_obstructed_notifications: int = 0
var repath_suppressed: int = 0
var obsolete_path_requests: int = 0
var known_imperfect_paths: int = 0
var known_imperfect_suppressed: int = 0
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
	unit.follow_known_imperfect_path_countdown = maxi(0, unit.follow_known_imperfect_path_countdown - 1)
	if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON and not unit.has_path():
		unit.finish_move_order()
		return

	var went_straight := _try_going_straight_to_target(unit, pathfinder, units, true)
	if not went_straight:
		_maybe_request_short_path_for_long_segment(unit, pathfinder, units)
	if not unit.has_path():
		if unit.pending_long_ticket == 0 and unit.pending_short_ticket == 0:
			_handle_blocked_move(unit, pathfinder, units, false)
		return

	var move_result := _perform_move(unit, delta, pathfinder, units)
	if bool(move_result.get("obstructed", false)):
		_handle_blocked_move(unit, pathfinder, units, bool(move_result.get("moved", false)))
		return
	if bool(move_result.get("moved", false)):
		unit.failed_movements = 0
		unit.was_obstructed = false
		unit.obstruction_state = ""
		if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON and not unit.has_path():
			unit.finish_move_order()
		elif went_straight:
			unit.short_path = SimNavWaypointPath.new()
		return
	_handle_blocked_move(unit, pathfinder, units, false)


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


func _perform_move(
	unit: ZeroAdRtsLabUnit,
	delta: float,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit]
) -> Dictionary:
	var remaining_distance := unit.speed * delta
	var moved := false
	while remaining_distance > 0.0001 and unit.has_path():
		var waypoint := unit.current_waypoint()
		var to_waypoint := waypoint - unit.position
		var waypoint_distance := to_waypoint.length()
		if waypoint_distance <= ARRIVE_EPSILON:
			unit.consume_current_waypoint()
			continue
		var move_distance := minf(remaining_distance, waypoint_distance)
		var candidate := unit.position + to_waypoint / waypoint_distance * move_distance
		var line_result := pathfinder.validate_movement_line(unit, unit.position, candidate, units, false)
		if not line_result.is_success():
			return {
				"obstructed": true,
				"moved": moved,
			}
		unit.position = candidate
		unit.remember_position()
		moved = true
		remaining_distance -= move_distance
		if unit.position.distance_to(waypoint) <= ARRIVE_EPSILON:
			unit.consume_current_waypoint()
	return {
		"obstructed": false,
		"moved": moved,
	}


func _request_long_path(
	unit: ZeroAdRtsLabUnit,
	goal: Vector2,
	pathfinder: ZeroAdRtsLabPathfinder
) -> void:
	if unit.pending_short_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_short_ticket)
		unit.pending_short_ticket = 0
		obsolete_path_requests += 1
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
		obsolete_path_requests += 1
	long_path_requests += 1
	unit.pending_long_ticket = pathfinder.enqueue_long_path(unit, goal)


func _apply_long_path_result(unit: ZeroAdRtsLabUnit, result: SimNavLongPathResult) -> void:
	path_results_applied += 1
	if result.is_success():
		unit.long_path = result.path
		unit.short_path = SimNavWaypointPath.new()
		unit.path_target = result.canonical_goal.center if result.canonical_goal != null else unit.target
		_note_known_imperfect_path_if_needed(unit, true)
	else:
		path_result_failures += 1
		unit.long_path = SimNavWaypointPath.new()
		unit.path_target = unit.target


func _request_short_path(
	unit: ZeroAdRtsLabUnit,
	goal: SimNavPathGoal,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	search_range: float = SHORT_PATH_MIN_SEARCH_RANGE
) -> bool:
	if unit.pending_short_ticket > 0:
		repath_suppressed += 1
		return false
	if unit.short_repath_cooldown > 0.0:
		repath_suppressed += 1
		return false
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
		obsolete_path_requests += 1
	short_path_requests += 1
	unit.pending_short_ticket = pathfinder.enqueue_short_path(unit, goal, units, search_range)
	unit.short_repath_cooldown = SHORT_REPATH_COOLDOWN_SEC
	return true


func _apply_short_path_result(unit: ZeroAdRtsLabUnit, result: SimNavShortPathResult) -> void:
	path_results_applied += 1
	if result.is_success():
		unit.short_path = result.path
		_note_known_imperfect_path_if_needed(unit, unit.long_path == null or unit.long_path.is_empty())
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
	if unit.follow_known_imperfect_path_countdown > 0:
		known_imperfect_suppressed += 1
		return
	var next_long: Vector2 = unit.long_path.back()
	var unit_line := pathfinder.validate_unit_line(unit, unit.position, next_long, units, false)
	if unit_line.is_success():
		return
	if unit.long_path.size() > 1:
		unit.long_path.pop_back()
		next_long = unit.long_path.back()
	var goal := SimNavPathGoal.circle(next_long, SHORT_PATH_LONG_WAYPOINT_RANGE)
	_request_short_path(unit, goal, pathfinder, units, _short_path_search_range(unit, false))


func _handle_blocked_move(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	moved: bool
) -> void:
	blocked_moves += 1
	unit.was_obstructed = true
	if not moved or unit.failed_movements < 2:
		if _increment_failed_movements_and_maybe_fail(unit, pathfinder):
			return
		_note_obstructed(unit)

	var goal := SimNavPathGoal.point(unit.path_target)
	if _in_short_path_range(goal, unit.position):
		_compute_path_to_goal(unit, pathfinder, units, goal)
		return
	if unit.short_path != null and not unit.short_path.is_empty() and unit.failed_movements == BACKUP_HACK_DELAY:
		var next := unit.short_path.back()
		var back_up := unit.position - next
		if back_up.length_squared() > 0.0001:
			unit.short_path.push_back(unit.position + back_up.normalized() * BACKUP_HACK_DISTANCE)
			return

	var skip_beyond := maxf(_short_path_search_range(unit, false) / 3.0, NAVCELL_SIZE * 8.0)
	if unit.long_path != null and unit.long_path.size() > 1 and unit.position.distance_to(unit.long_path.back()) < skip_beyond:
		unit.long_path.pop_back()
	elif _should_alternate_pathfinder(unit):
		_request_long_path(unit, unit.path_target, pathfinder)
		return

	if unit.long_path == null or unit.long_path.is_empty():
		_compute_path_to_goal(unit, pathfinder, units, goal)
		return

	var radius := clampf(skip_beyond / 3.0, NAVCELL_SIZE * 4.0, NAVCELL_SIZE * 12.0)
	var subgoal := SimNavPathGoal.circle(unit.long_path.back(), radius)
	_request_short_path(unit, subgoal, pathfinder, units, _short_path_search_range(unit, false))


func _compute_path_to_goal(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	goal: SimNavPathGoal
) -> void:
	if goal == null:
		return
	if unit.follow_known_imperfect_path_countdown > 0 and unit.has_path():
		known_imperfect_suppressed += 1
		return
	if not _should_alternate_pathfinder(unit) and _try_going_straight_to_target(unit, pathfinder, units, false):
		unit.short_path = SimNavWaypointPath.new()
		_request_long_path(unit, goal.center, pathfinder)
		return
	var use_short_path := _in_short_path_range(goal, unit.position)
	if _should_alternate_pathfinder(unit):
		use_short_path = not use_short_path
	if use_short_path:
		unit.long_path = SimNavWaypointPath.new()
		_request_short_path(unit, goal, pathfinder, units, _short_path_search_range(unit, true, goal))
	else:
		unit.short_path = SimNavWaypointPath.new()
		_request_long_path(unit, goal.center, pathfinder)


func _increment_failed_movements_and_maybe_fail(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder
) -> bool:
	unit.failed_movements += 1
	if unit.failed_movements < MAX_FAILED_MOVEMENTS:
		return false
	_cancel_pending_path_requests(unit, pathfinder)
	unit.fail_move_order()
	move_failures += 1
	return true


func _try_going_straight_to_target(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	update_paths: bool
) -> bool:
	if unit.short_path != null and not unit.short_path.is_empty():
		return false
	if unit.position.distance_to(unit.path_target) > DIRECT_PATH_RANGE:
		return false
	var line_result := pathfinder.validate_movement_line(unit, unit.position, unit.path_target, units, false)
	if not line_result.is_success():
		return false
	if not update_paths:
		return true
	unit.long_path = SimNavWaypointPath.new()
	unit.short_path = SimNavWaypointPath.new()
	unit.short_path.push_back(unit.path_target)
	return true


func _note_obstructed(unit: ZeroAdRtsLabUnit) -> void:
	if unit.failed_movements < 2:
		unit.obstruction_state = ""
		return
	if unit.failed_movements >= VERY_OBSTRUCTED_THRESHOLD:
		unit.obstruction_state = "very_obstructed"
		very_obstructed_notifications += 1
	else:
		unit.obstruction_state = "obstructed"
		obstructed_notifications += 1


func _note_known_imperfect_path_if_needed(unit: ZeroAdRtsLabUnit, pathed_towards_goal: bool) -> void:
	if not pathed_towards_goal:
		return
	if not _pathing_update_needed(unit):
		return
	unit.follow_known_imperfect_path_countdown = KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN
	unit.obstruction_state = "known_imperfect_path"
	known_imperfect_paths += 1


func _pathing_update_needed(unit: ZeroAdRtsLabUnit) -> bool:
	if not unit.has_move_order:
		return false
	if unit.follow_known_imperfect_path_countdown > 0 and unit.has_path():
		return false
	var goal := SimNavPathGoal.point(unit.path_target)
	if not unit.has_path():
		return true
	if _in_short_path_range(goal, unit.position) and unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON:
		return false
	var final_waypoint := _final_waypoint(unit.active_path())
	return goal.distance_to_point(final_waypoint) > ARRIVE_EPSILON


func _final_waypoint(path: SimNavWaypointPath) -> Vector2:
	if path == null or path.is_empty():
		return Vector2.ZERO
	return path.waypoints[0]


func _in_short_path_range(goal: SimNavPathGoal, position: Vector2) -> bool:
	if goal == null:
		return false
	return goal.distance_to_point(position) < LONG_PATH_MIN_DIST


func _short_path_search_range(
	unit: ZeroAdRtsLabUnit,
	extend_range: bool,
	goal: SimNavPathGoal = null
) -> float:
	var multiple := maxi(0, unit.failed_movements - SHORT_PATH_SEARCH_RANGE_INCREASE_DELAY)
	var search_range := SHORT_PATH_MIN_SEARCH_RANGE + SHORT_PATH_SEARCH_RANGE_INCREMENT * float(multiple)
	search_range = minf(search_range, SHORT_PATH_MAX_SEARCH_RANGE)
	if extend_range and goal != null:
		var goal_distance := unit.position.distance_to(goal.center)
		if goal_distance >= search_range - 1.0:
			search_range = minf(goal_distance + 1.0, SHORT_PATH_MAX_SEARCH_RANGE)
	return search_range


func _should_alternate_pathfinder(unit: ZeroAdRtsLabUnit) -> bool:
	if unit.failed_movements == ALTERNATE_PATH_TYPE_DELAY:
		return true
	return (
		unit.failed_movements > ALTERNATE_PATH_TYPE_DELAY
		and (unit.failed_movements - ALTERNATE_PATH_TYPE_DELAY) % ALTERNATE_PATH_TYPE_EVERY == 0
	)


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
