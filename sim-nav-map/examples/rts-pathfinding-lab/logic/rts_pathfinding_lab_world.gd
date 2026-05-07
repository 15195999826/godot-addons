class_name RtsPathfindingLabWorld
extends RefCounted


const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

const MOBILE_GROUP_ID: String = "blue"
const REPLAN_INTERVAL: float = 0.45
const REPLAN_BUDGET_PER_TICK: int = 1
const ARRIVE_EPSILON: float = 8.0
const OVERLAP_RESOLVE_ITERATIONS: int = 4
const SEPARATION_STABILIZE_ITERATIONS: int = 6
# 单次 _push_unit_out_of_static_component 位移上限(cell_size 倍数);限制单帧"瞬移"。
const STATIC_PUSH_MAX_PER_CALL_CELLS: float = 1.5
# 沿 inflated rect 边采样 candidate 的步长(cell_size 倍数);决定 push out 候选点密度。
const STATIC_EXIT_SAMPLE_STEP_CELLS: float = 0.5
# _resolve_overlaps 单帧每个 unit 总位移上限(cell_size 倍数);限制 overlap 推动累积造成的视觉跳变。
const OVERLAP_PUSH_MAX_PER_FRAME_CELLS: float = 1.0
const SEPARATION_TOTAL_BUDGET_USEC: int = 16000
const RECENT_PLAN_REPORT_LIMIT: int = 80
const STUCK_SETTLE_TICKS: int = 30
const STUCK_ACTIVE_ORDER_TICKS: int = 180
const STUCK_SETTLE_RADIUS: float = 56.0
const STUCK_STATIC_DIRECT_SETTLE_RADIUS: float = 96.0
const STUCK_BLOCKED_PATH_SETTLE_RADIUS: float = 160.0
const STUCK_PROGRESS_EPSILON: float = 0.25
const STUCK_STATIC_MARGIN: float = 16.0
const ARRIVE_MAX_OVERLAP: float = 1.0
const STATIC_PUSH_LOCAL_EXIT_DISTANCE: float = 24.0
const STATIC_PUSH_REASONABLE_EXIT_DISTANCE: float = 64.0

var map_size: Vector2 = Vector2(720.0, 420.0)
var obstacles: Array[RtsPathfindingLabObstacle] = []
var units: Array[RtsPathfindingLabUnit] = []
var pathfinder: RtsPathfindingLabPathfinder = null
var group_filter_enabled: bool = true
var avoid_moving_units_enabled: bool = true
var current_target: Vector2 = Vector2(610.0, 210.0)
var tick_count: int = 0
var last_replans_this_tick: int = 0
var max_replans_per_tick: int = 0
var total_replans: int = 0
var last_step_profile: Dictionary = {}
var recent_plan_reports: Array[Dictionary] = []
var _obstacle_seq: int = 0
var _blocker_seq: int = 0
var _replan_queue: Array[String] = []
var _last_step_plans: Array[Dictionary] = []
var _last_step_stuck_settles: Array[Dictionary] = []
var _last_target_error_by_unit: Dictionary = {}
var _stalled_ticks_by_unit: Dictionary = {}
var _active_order_ticks_by_unit: Dictionary = {}
var _canonical_target_by_unit: Dictionary = {}


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
	last_replans_this_tick = 0
	max_replans_per_tick = 0
	total_replans = 0
	last_step_profile = {}
	recent_plan_reports.clear()
	_last_step_plans.clear()
	_last_step_stuck_settles.clear()
	_last_target_error_by_unit.clear()
	_stalled_ticks_by_unit.clear()
	_active_order_ticks_by_unit.clear()
	_canonical_target_by_unit.clear()
	_replan_queue.clear()
	pathfinder.prewarm_static_context(obstacles)
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
		unit.target = _clamp_unit_point(target + offsets[i], unit.radius)
		unit.arrived = false
		unit.has_move_order = true
		unit.replan_timer = REPLAN_INTERVAL
		unit.path.clear()
		unit.path_index = 0
		_canonical_target_by_unit[unit.id] = false
		_reset_stuck_progress(unit)
		_enqueue_replan(unit.id)


func step(delta: float) -> void:
	var step_start_usec := Time.get_ticks_usec()
	tick_count += 1
	last_replans_this_tick = 0
	_last_step_plans.clear()
	_last_step_stuck_settles.clear()
	var replan_start_usec := Time.get_ticks_usec()
	_process_replan_budget()
	var replan_usec := Time.get_ticks_usec() - replan_start_usec
	var mobile_units := get_mobile_units()
	mobile_units.sort_custom(func(a: RtsPathfindingLabUnit, b: RtsPathfindingLabUnit) -> bool:
		return a.id < b.id
	)
	var move_start_usec := Time.get_ticks_usec()
	for unit in mobile_units:
		if unit.arrived:
			continue
		unit.replan_timer += delta
		_move_unit(unit, delta)
		if not unit.arrived and (unit.replan_timer >= REPLAN_INTERVAL or unit.path_index >= unit.path.size()):
			_enqueue_replan(unit.id)
	var move_usec := Time.get_ticks_usec() - move_start_usec
	var pre_settle_start_usec := Time.get_ticks_usec()
	_pre_settle_expired_active_orders(mobile_units)
	var pre_settle_usec := Time.get_ticks_usec() - pre_settle_start_usec
	var separation_start_usec := Time.get_ticks_usec()
	_resolve_separation(mobile_units)
	var separation_usec := Time.get_ticks_usec() - separation_start_usec
	var settle_start_usec := Time.get_ticks_usec()
	for unit in mobile_units:
		if not unit.has_move_order:
			_settle_idle_unit(unit)
		else:
			_update_active_move_settle(unit)
		unit.append_trace_point()
	var settle_trace_usec := Time.get_ticks_usec() - settle_start_usec
	last_step_profile = {
		"tick": tick_count,
		"delta": delta,
		"total_usec": Time.get_ticks_usec() - step_start_usec,
		"replan_usec": replan_usec,
		"move_usec": move_usec,
		"pre_settle_usec": pre_settle_usec,
		"separation_usec": separation_usec,
		"settle_trace_usec": settle_trace_usec,
		"planned_count": last_replans_this_tick,
		"pending_replans": _replan_queue.size(),
		"plans": _last_step_plans.duplicate(true),
		"stuck_settles": _last_step_stuck_settles.duplicate(true),
	}


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
	pathfinder.prewarm_static_context(obstacles)
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
		pathfinder.prewarm_static_context(obstacles)
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
		"last_replans_this_tick": last_replans_this_tick,
		"max_replans_per_tick": max_replans_per_tick,
		"pending_replans": _replan_queue.size(),
		"total_replans": total_replans,
		"active_move_orders": _active_move_order_count(),
		"static_context_cache_hits": pathfinder.static_context_cache_hits,
		"static_context_cache_misses": pathfinder.static_context_cache_misses,
	}


func _plan_unit(unit: RtsPathfindingLabUnit) -> void:
	var others: Array[RtsPathfindingLabUnit] = []
	for candidate in units:
		if candidate.id != unit.id:
			others.append(candidate)
	var start_position := unit.position
	var target_before := unit.target
	var plan_start_usec := Time.get_ticks_usec()
	var planned_path := pathfinder.plan_path(
		unit.position,
		unit.target,
		obstacles,
		others,
		unit.group_id,
		avoid_moving_units_enabled,
		group_filter_enabled,
		bool(_canonical_target_by_unit.get(unit.id, false))
	)
	var plan_usec := Time.get_ticks_usec() - plan_start_usec
	if bool(pathfinder.last_report.get("used_make_goal_reachable", false)):
		var reachable_goal: Vector2 = pathfinder.last_report.get("reachable_goal", unit.target) as Vector2
		if reachable_goal.distance_to(unit.target) > 0.01:
			unit.target = reachable_goal
			_canonical_target_by_unit[unit.id] = true
			_reset_stuck_progress(unit)
	unit.set_path(planned_path)
	unit.replan_timer = 0.0
	_record_plan_report({
		"tick": tick_count,
		"unit_id": unit.id,
		"start": start_position,
		"target_before": target_before,
		"target_after": unit.target,
		"plan_usec": plan_usec,
		"path_size": planned_path.size(),
		"other_units": others.size(),
		"static_obstacles": obstacles.size(),
		"pathfinder_report": pathfinder.last_report.duplicate(true),
	})


func _record_plan_report(report: Dictionary) -> void:
	recent_plan_reports.append(report)
	_last_step_plans.append(report)
	while recent_plan_reports.size() > RECENT_PLAN_REPORT_LIMIT:
		recent_plan_reports.pop_front()


func movement_debug_snapshot() -> Dictionary:
	var unit_debug: Array[Dictionary] = []
	for unit in get_mobile_units():
		unit_debug.append({
			"id": unit.id,
			"target_error": unit.position.distance_to(unit.target),
			"stalled_ticks": int(_stalled_ticks_by_unit.get(unit.id, 0)),
			"last_target_error": float(_last_target_error_by_unit.get(unit.id, -1.0)),
			"active_order_ticks": int(_active_order_ticks_by_unit.get(unit.id, 0)),
			"canonical_target": bool(_canonical_target_by_unit.get(unit.id, false)),
			"path_is_direct_to_target": _path_is_direct_to_target(unit),
			"static_constrained": _move_order_is_static_constrained(unit),
			"has_move_order": unit.has_move_order,
			"arrived": unit.arrived,
		})
	return {
		"units": unit_debug,
		"stuck_settles_this_step": _last_step_stuck_settles.duplicate(true),
	}


func _replan_all_mobile() -> void:
	for unit in get_mobile_units():
		if not unit.has_move_order:
			continue
		unit.replan_timer = REPLAN_INTERVAL
		_enqueue_replan(unit.id)


func _enqueue_replan(unit_id: String) -> void:
	if not _replan_queue.has(unit_id):
		_replan_queue.append(unit_id)


func _process_replan_budget() -> void:
	var planned_count := 0
	while planned_count < REPLAN_BUDGET_PER_TICK and not _replan_queue.is_empty():
		var unit_id := String(_replan_queue.pop_front())
		var unit := get_unit_by_id(unit_id)
		if unit == null or not unit.mobile or unit.arrived:
			continue
		_plan_unit(unit)
		planned_count += 1
	last_replans_this_tick = planned_count
	max_replans_per_tick = maxi(max_replans_per_tick, planned_count)
	total_replans += planned_count


func _move_unit(unit: RtsPathfindingLabUnit, delta: float) -> void:
	if unit.path.is_empty():
		unit.arrived = unit.position.distance_to(unit.target) <= ARRIVE_EPSILON
		if unit.arrived:
			unit.has_move_order = false
		return
	var waypoint := unit.current_waypoint()
	var to_waypoint := waypoint - unit.position
	var max_step := unit.speed * delta
	if to_waypoint.length() <= max_step:
		unit.position = waypoint
		unit.path_index += 1
	else:
		unit.position += to_waypoint.normalized() * max_step
	unit.position = _clamp_unit_point(unit.position, unit.radius)

	if unit.path_index >= unit.path.size() and unit.position.distance_to(unit.target) <= ARRIVE_EPSILON:
		_finish_move_order(unit)


func _pre_settle_expired_active_orders(mobile_units: Array[RtsPathfindingLabUnit]) -> void:
	for unit in mobile_units:
		if not unit.has_move_order:
			continue
		var next_active_ticks := int(_active_order_ticks_by_unit.get(unit.id, 0)) + 1
		if next_active_ticks < STUCK_ACTIVE_ORDER_TICKS:
			continue
		var target_error := unit.position.distance_to(unit.target)
		if target_error <= ARRIVE_EPSILON:
			continue
		var path_is_direct := _path_is_direct_to_target(unit)
		var static_constrained := _move_order_is_static_constrained(unit)
		var near_static_boundary := _unit_near_static_boundary(unit)
		var max_stuck_error := STUCK_SETTLE_RADIUS
		if path_is_direct and static_constrained:
			max_stuck_error = STUCK_STATIC_DIRECT_SETTLE_RADIUS
		elif not path_is_direct:
			max_stuck_error = STUCK_BLOCKED_PATH_SETTLE_RADIUS
		if (
			target_error > max_stuck_error
			or not static_constrained
			or (not path_is_direct and not near_static_boundary)
		):
			continue
		_last_step_stuck_settles.append({
			"unit_id": unit.id,
			"position_before": unit.position,
			"target_before": unit.target,
			"target_error": target_error,
			"progress_error": target_error if path_is_direct else unit.position.distance_to(unit.current_waypoint()),
			"active_order_ticks": next_active_ticks,
			"path_size": unit.path.size(),
			"path_index": unit.path_index,
			"reason": "active_order_age",
			"phase": "pre_separation",
		})
		_settle_idle_unit(unit)


func _update_active_move_settle(unit: RtsPathfindingLabUnit) -> void:
	_active_order_ticks_by_unit[unit.id] = int(_active_order_ticks_by_unit.get(unit.id, 0)) + 1
	var target_error := unit.position.distance_to(unit.target)
	if target_error <= ARRIVE_EPSILON:
		if _unit_max_overlap(unit) <= ARRIVE_MAX_OVERLAP:
			_settle_idle_unit(unit)
		else:
			unit.arrived = false
			_last_target_error_by_unit[unit.id] = target_error
			_stalled_ticks_by_unit[unit.id] = 0
		return
	unit.arrived = false
	var path_is_direct := _path_is_direct_to_target(unit)
	var static_constrained := _move_order_is_static_constrained(unit)
	var near_static_boundary := _unit_near_static_boundary(unit)
	var max_stuck_error := STUCK_SETTLE_RADIUS
	if path_is_direct and static_constrained:
		max_stuck_error = STUCK_STATIC_DIRECT_SETTLE_RADIUS
	elif not path_is_direct:
		max_stuck_error = STUCK_BLOCKED_PATH_SETTLE_RADIUS
	var active_age_eligible := (
		static_constrained
		and target_error <= STUCK_BLOCKED_PATH_SETTLE_RADIUS
		and (path_is_direct or near_static_boundary)
	)
	if (
		target_error > max_stuck_error
		or not static_constrained
		or (not path_is_direct and not near_static_boundary)
	):
		_last_target_error_by_unit[unit.id] = target_error
		_stalled_ticks_by_unit[unit.id] = 0
		if not active_age_eligible:
			_active_order_ticks_by_unit[unit.id] = 0
		return

	var progress_error := target_error if path_is_direct else unit.position.distance_to(unit.current_waypoint())
	var last_error := float(_last_target_error_by_unit.get(unit.id, INF))
	if progress_error >= last_error - STUCK_PROGRESS_EPSILON:
		_stalled_ticks_by_unit[unit.id] = int(_stalled_ticks_by_unit.get(unit.id, 0)) + 1
	else:
		_stalled_ticks_by_unit[unit.id] = 0
	_last_target_error_by_unit[unit.id] = progress_error

	if int(_stalled_ticks_by_unit.get(unit.id, 0)) >= STUCK_SETTLE_TICKS:
		_last_step_stuck_settles.append({
			"unit_id": unit.id,
			"position_before": unit.position,
			"target_before": unit.target,
			"target_error": target_error,
			"progress_error": progress_error,
			"stalled_ticks": int(_stalled_ticks_by_unit.get(unit.id, 0)),
			"path_size": unit.path.size(),
			"path_index": unit.path_index,
		})
		_settle_idle_unit(unit)
		return
	if int(_active_order_ticks_by_unit.get(unit.id, 0)) >= STUCK_ACTIVE_ORDER_TICKS:
		_last_step_stuck_settles.append({
			"unit_id": unit.id,
			"position_before": unit.position,
			"target_before": unit.target,
			"target_error": target_error,
			"progress_error": progress_error,
			"active_order_ticks": int(_active_order_ticks_by_unit.get(unit.id, 0)),
			"path_size": unit.path.size(),
			"path_index": unit.path_index,
			"reason": "active_order_age",
		})
		_settle_idle_unit(unit)


func _path_is_direct_to_target(unit: RtsPathfindingLabUnit) -> bool:
	if unit.path.is_empty():
		return true
	if unit.path_index >= unit.path.size():
		return true
	if unit.path.size() - unit.path_index > 1:
		return false
	return unit.path.back().distance_to(unit.target) <= ARRIVE_EPSILON


func _move_order_is_static_constrained(unit: RtsPathfindingLabUnit) -> bool:
	for obstacle in obstacles:
		var rect := obstacle.get_inflated_rect(unit.radius).grow(STUCK_STATIC_MARGIN)
		if rect.has_point(unit.target):
			return true
	return false


func _unit_max_overlap(unit: RtsPathfindingLabUnit) -> float:
	var result := 0.0
	for other in units:
		if other.id == unit.id:
			continue
		var dist := unit.position.distance_to(other.position)
		result = maxf(result, unit.radius + other.radius - dist)
	return maxf(result, 0.0)


func _unit_near_static_boundary(unit: RtsPathfindingLabUnit) -> bool:
	for obstacle in obstacles:
		var rect := obstacle.get_inflated_rect(unit.radius).grow(STUCK_STATIC_MARGIN)
		if rect.has_point(unit.position):
			return true
	return false


func _finish_move_order(unit: RtsPathfindingLabUnit) -> void:
	unit.position = unit.target
	unit.path.clear()
	unit.path_index = 0
	unit.arrived = true
	unit.has_move_order = false
	unit.replan_timer = 0.0
	_clear_stuck_progress(unit)
	_canonical_target_by_unit.erase(unit.id)
	_remove_queued_replan(unit.id)


func _resolve_overlaps(overlap_push_budgets: Dictionary) -> bool:
	var any_changed := false
	for _iteration in range(OVERLAP_RESOLVE_ITERATIONS):
		var changed := false
		for i in range(units.size()):
			for j in range(i + 1, units.size()):
				var a := units[i]
				var b := units[j]
				if (
					a.mobile
					and b.mobile
					and not a.has_move_order
					and not b.has_move_order
					and (_unit_near_static_boundary(a) or _unit_near_static_boundary(b))
				):
					continue
				var min_dist := a.radius + b.radius
				var delta := b.position - a.position
				var dist := delta.length()
				if dist >= min_dist or dist <= 0.0001:
					continue
				var dir := delta / dist
				var push := (min_dist - dist) + 0.1
				var displacement_a := Vector2.ZERO
				var displacement_b := Vector2.ZERO
				if a.mobile and b.mobile:
					displacement_a = -dir * push * 0.5
					displacement_b = dir * push * 0.5
				elif a.mobile:
					displacement_a = -dir * push
				elif b.mobile:
					displacement_b = dir * push
				var moved_a := false
				var moved_b := false
				if a.mobile and displacement_a.length() > 0.0001:
					moved_a = _apply_overlap_push(a, displacement_a, overlap_push_budgets)
				if b.mobile and displacement_b.length() > 0.0001:
					moved_b = _apply_overlap_push(b, displacement_b, overlap_push_budgets)
				if not a.mobile:
					a.position = _clamp_to_map(a.position)
				if not b.mobile:
					b.position = _clamp_to_map(b.position)
				if moved_a or moved_b:
					changed = true
					any_changed = true
		if not changed:
			return any_changed
	return any_changed


func _apply_overlap_push(
	unit: RtsPathfindingLabUnit,
	displacement: Vector2,
	overlap_push_budgets: Dictionary
) -> bool:
	var distance := displacement.length()
	if distance <= 0.0001:
		return false
	var max_per_frame := _overlap_push_max_per_frame(unit)
	var used := float(overlap_push_budgets.get(unit.id, 0.0))
	var remaining := max_per_frame - used
	if remaining <= 0.0001:
		return false
	if distance > remaining:
		displacement = displacement.normalized() * remaining
		distance = remaining
	unit.position += displacement
	unit.position = _clamp_unit_point(unit.position, unit.radius)
	overlap_push_budgets[unit.id] = used + distance
	return true


func _overlap_push_max_per_frame(unit: RtsPathfindingLabUnit) -> float:
	# 与 cell_size / unit diameter 较大者关联,缩放 cell_size / radius 时自动适应。
	var cell_step := pathfinder.cell_size * OVERLAP_PUSH_MAX_PER_FRAME_CELLS
	var unit_step := unit.radius * 1.5
	return maxf(cell_step, unit_step)


func _resolve_separation(mobile_units: Array[RtsPathfindingLabUnit]) -> void:
	var inflated_rect_cache: Dictionary = {}
	var component_cache_by_radius: Dictionary = {}
	var static_exit_cache: Dictionary = {}
	var overlap_push_budgets: Dictionary = {}
	for unit in mobile_units:
		overlap_push_budgets[unit.id] = 0.0
	var separation_start_usec := Time.get_ticks_usec()
	for _iteration in range(SEPARATION_STABILIZE_ITERATIONS):
		var changed := _push_out_static_obstacles_for_units(
			mobile_units,
			inflated_rect_cache,
			component_cache_by_radius,
			static_exit_cache
		)
		changed = _resolve_overlaps(overlap_push_budgets) or changed
		changed = _push_out_static_obstacles_for_units(
			mobile_units,
			inflated_rect_cache,
			component_cache_by_radius,
			static_exit_cache
		) or changed
		if not changed:
			return
		if Time.get_ticks_usec() - separation_start_usec > SEPARATION_TOTAL_BUDGET_USEC:
			return


func _push_out_static_obstacles_for_units(
	mobile_units: Array[RtsPathfindingLabUnit],
	inflated_rect_cache: Dictionary,
	component_cache_by_radius: Dictionary,
	static_exit_cache: Dictionary
) -> bool:
	var changed := false
	for unit in mobile_units:
		var radius_key := _radius_cache_key(unit.radius)
		if not inflated_rect_cache.has(radius_key):
			inflated_rect_cache[radius_key] = _build_static_inflated_rects(unit.radius)
			component_cache_by_radius[radius_key] = {}
		var inflated_rects: Array[Rect2] = inflated_rect_cache[radius_key]
		var component_cache: Dictionary = component_cache_by_radius[radius_key]
		changed = _push_out_static_obstacles(
			unit,
			inflated_rects,
			component_cache,
			static_exit_cache,
			mobile_units
		) or changed
	return changed


func _push_out_static_obstacles(
	unit: RtsPathfindingLabUnit,
	inflated_rects: Array[Rect2],
	component_cache: Dictionary,
	static_exit_cache: Dictionary,
	mobile_units: Array[RtsPathfindingLabUnit]
) -> bool:
	var moved := false
	for _iteration in range(OVERLAP_RESOLVE_ITERATIONS):
		var push_rects := _static_push_component_for_point(unit.position, inflated_rects, component_cache)
		if push_rects.is_empty():
			return moved
		var before := unit.position
		_push_unit_out_of_static_component(unit, push_rects, inflated_rects, static_exit_cache, mobile_units)
		if unit.position.distance_squared_to(before) <= 0.0001:
			return moved
		moved = true
	return moved


func _radius_cache_key(radius: float) -> String:
	return "%.3f" % radius


func _build_static_inflated_rects(radius: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for obstacle in obstacles:
		result.append(obstacle.get_inflated_rect(radius))
	return result


func _static_push_component_for_point(point: Vector2, inflated_rects: Array[Rect2], component_cache: Dictionary) -> Array[Rect2]:
	var component_indices: Array[int] = []
	for i in range(inflated_rects.size()):
		var rect := inflated_rects[i]
		if rect.has_point(point):
			component_indices.append(i)
			break
	if component_indices.is_empty():
		return []
	var start_index := component_indices[0]
	if component_cache.has(start_index):
		return component_cache[start_index]

	var changed := true
	while changed:
		changed = false
		for i in range(inflated_rects.size()):
			if component_indices.has(i):
				continue
			var obstacle_rect := inflated_rects[i]
			if _component_intersects_rect(component_indices, obstacle_rect, inflated_rects):
				component_indices.append(i)
				changed = true

	var result: Array[Rect2] = []
	for index in component_indices:
		result.append(inflated_rects[index])
	for index in component_indices:
		component_cache[index] = result
	return result


func _component_intersects_rect(component_indices: Array[int], rect: Rect2, inflated_rects: Array[Rect2]) -> bool:
	for index in component_indices:
		if inflated_rects[index].intersects(rect, true):
			return true
	return false


func _push_unit_out_of_static_component(
	unit: RtsPathfindingLabUnit,
	rects: Array[Rect2],
	inflated_rects: Array[Rect2],
	static_exit_cache: Dictionary,
	mobile_units: Array[RtsPathfindingLabUnit]
) -> void:
	var best_point := unit.position
	var best_dist_sq := INF
	var best_overlap := INF
	var best_side_point := unit.position
	var best_side_dist_sq := INF
	var best_side_overlap := INF
	var reference_point := _static_push_reference_point(unit, inflated_rects)
	var containing_rects := _rects_containing_point(unit.position, rects)
	var prefer_local_exit := not unit.has_move_order
	var reference_candidate := _clamp_unit_point(reference_point, unit.radius)
	if prefer_local_exit and not _point_inside_static_obstacles(reference_candidate, inflated_rects):
		var reference_dist_sq := unit.position.distance_squared_to(reference_candidate)
		var reference_overlap := _point_max_overlap_with_units(reference_candidate, unit, mobile_units)
		if _is_better_static_exit(reference_overlap, reference_dist_sq, best_overlap, best_dist_sq, prefer_local_exit):
			best_overlap = reference_overlap
			best_dist_sq = reference_dist_sq
			best_point = reference_candidate
		if _candidate_preserves_reference_side(reference_candidate, reference_point, containing_rects):
			if _is_better_static_exit(
				reference_overlap,
				reference_dist_sq,
				best_side_overlap,
				best_side_dist_sq,
				prefer_local_exit
			):
				best_side_overlap = reference_overlap
				best_side_dist_sq = reference_dist_sq
				best_side_point = reference_candidate
	for rect in rects:
		var candidates := _static_exit_candidates(unit.position, rect, static_exit_cache)
		for candidate in candidates:
			var clamped_candidate := _clamp_unit_point(candidate, unit.radius)
			if _point_inside_static_obstacles(clamped_candidate, inflated_rects):
				continue
			var current_dist_sq := unit.position.distance_squared_to(clamped_candidate)
			var candidate_overlap := _point_max_overlap_with_units(clamped_candidate, unit, mobile_units)
			if _is_better_static_exit(candidate_overlap, current_dist_sq, best_overlap, best_dist_sq, prefer_local_exit):
				best_overlap = candidate_overlap
				best_dist_sq = current_dist_sq
				best_point = clamped_candidate
			if _candidate_preserves_reference_side(clamped_candidate, reference_point, containing_rects):
				if _is_better_static_exit(
					candidate_overlap,
					current_dist_sq,
					best_side_overlap,
					best_side_dist_sq,
					prefer_local_exit
				):
					best_side_overlap = candidate_overlap
					best_side_dist_sq = current_dist_sq
					best_side_point = clamped_candidate
	var chosen_point := unit.position
	if best_side_dist_sq < INF:
		chosen_point = best_side_point
	elif best_dist_sq < INF:
		chosen_point = best_point
	else:
		_push_unit_out_of_rect(unit, _component_bounds(rects))
		return
	_apply_static_push_displacement(unit, chosen_point - unit.position)


func _apply_static_push_displacement(unit: RtsPathfindingLabUnit, displacement: Vector2) -> void:
	var distance := displacement.length()
	if distance <= 0.0001:
		return
	var max_per_call := _static_push_max_per_call(unit)
	if distance > max_per_call:
		displacement = displacement.normalized() * max_per_call
	unit.position += displacement
	unit.position = _clamp_unit_point(unit.position, unit.radius)


func _static_push_max_per_call(unit: RtsPathfindingLabUnit) -> float:
	# 取 cell_size 倍数与 unit diameter 中较大者:
	# - cell_size 倍数保证 push 至少能跨过一个 navcell,与 grid 对齐;
	# - unit diameter 兜底确保大单位也有合理位移,不会被卡住"micro-step"。
	var cell_step := pathfinder.cell_size * STATIC_PUSH_MAX_PER_CALL_CELLS
	var unit_step := unit.radius * 2.0
	return maxf(cell_step, unit_step)


func _is_better_static_exit(
	candidate_overlap: float,
	candidate_dist_sq: float,
	best_overlap: float,
	best_dist_sq: float,
	prefer_local_exit: bool
) -> bool:
	var candidate_is_reasonable := candidate_dist_sq <= STATIC_PUSH_REASONABLE_EXIT_DISTANCE * STATIC_PUSH_REASONABLE_EXIT_DISTANCE
	var best_is_reasonable := best_dist_sq <= STATIC_PUSH_REASONABLE_EXIT_DISTANCE * STATIC_PUSH_REASONABLE_EXIT_DISTANCE
	if candidate_is_reasonable and not best_is_reasonable:
		return true
	if not candidate_is_reasonable and best_is_reasonable:
		return false
	if prefer_local_exit:
		var candidate_is_local := candidate_dist_sq <= STATIC_PUSH_LOCAL_EXIT_DISTANCE * STATIC_PUSH_LOCAL_EXIT_DISTANCE
		var best_is_local := best_dist_sq <= STATIC_PUSH_LOCAL_EXIT_DISTANCE * STATIC_PUSH_LOCAL_EXIT_DISTANCE
		if candidate_is_local and not best_is_local:
			return true
		if not candidate_is_local and best_is_local:
			return false
	var candidate_is_clear := candidate_overlap <= ARRIVE_MAX_OVERLAP
	var best_is_clear := best_overlap <= ARRIVE_MAX_OVERLAP
	if candidate_is_clear and not best_is_clear:
		return true
	if not candidate_is_clear and not best_is_clear:
		if candidate_overlap < best_overlap - 0.01:
			return true
		if absf(candidate_overlap - best_overlap) <= 0.01:
			return candidate_dist_sq < best_dist_sq
		return false
	return candidate_dist_sq < best_dist_sq


func _point_max_overlap_with_units(
	point: Vector2,
	unit: RtsPathfindingLabUnit,
	mobile_units: Array[RtsPathfindingLabUnit]
) -> float:
	var result := 0.0
	for other in mobile_units:
		if other.id == unit.id:
			continue
		var overlap := unit.radius + other.radius - point.distance_to(other.position)
		result = maxf(result, overlap)
	return maxf(result, 0.0)


func _rects_containing_point(point: Vector2, rects: Array[Rect2]) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in rects:
		if rect.has_point(point):
			result.append(rect)
	return result


func _candidate_preserves_reference_side(candidate: Vector2, reference_point: Vector2, containing_rects: Array[Rect2]) -> bool:
	if containing_rects.is_empty():
		return false
	for rect in containing_rects:
		var left := rect.position.x
		var right := rect.position.x + rect.size.x
		var top := rect.position.y
		var bottom := rect.position.y + rect.size.y
		if reference_point.x < left and candidate.x <= left:
			return true
		if reference_point.x > right and candidate.x >= right:
			return true
		if reference_point.y < top and candidate.y <= top:
			return true
		if reference_point.y > bottom and candidate.y >= bottom:
			return true
	return false


func _static_push_reference_point(unit: RtsPathfindingLabUnit, inflated_rects: Array[Rect2]) -> Vector2:
	for i in range(unit.trace.size() - 1, -1, -1):
		var point := unit.trace[i]
		if point.distance_to(unit.position) > 160.0:
			break
		if not _point_inside_static_obstacles(point, inflated_rects):
			return point
	return unit.position


func _static_exit_candidates(point: Vector2, rect: Rect2, static_exit_cache: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = [
		Vector2(rect.position.x - 0.5, point.y),
		Vector2(rect.position.x + rect.size.x + 0.5, point.y),
		Vector2(point.x, rect.position.y - 0.5),
		Vector2(point.x, rect.position.y + rect.size.y + 0.5),
	]
	var cached := _static_exit_static_candidates(rect, static_exit_cache)
	for candidate in cached:
		result.append(candidate)
	return result


func _static_exit_static_candidates(rect: Rect2, static_exit_cache: Dictionary) -> Array[Vector2]:
	var key := "%.3f:%.3f:%.3f:%.3f" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if static_exit_cache.has(key):
		return static_exit_cache[key]
	var left := rect.position.x - 0.5
	var right := rect.position.x + rect.size.x + 0.5
	var top := rect.position.y - 0.5
	var bottom := rect.position.y + rect.size.y + 0.5
	var result: Array[Vector2] = [
		Vector2(left, top),
		Vector2(right, top),
		Vector2(left, bottom),
		Vector2(right, bottom),
	]
	var sample_step := pathfinder.cell_size * STATIC_EXIT_SAMPLE_STEP_CELLS
	var y := top + sample_step
	while y < bottom:
		result.append(Vector2(left, y))
		result.append(Vector2(right, y))
		y += sample_step
	var x := left + sample_step
	while x < right:
		result.append(Vector2(x, top))
		result.append(Vector2(x, bottom))
		x += sample_step
	static_exit_cache[key] = result
	return result


func _point_inside_static_obstacles(point: Vector2, inflated_rects: Array[Rect2]) -> bool:
	for rect in inflated_rects:
		if rect.has_point(point):
			return true
	return false


func _component_bounds(rects: Array[Rect2]) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var result := rects[0]
	for i in range(1, rects.size()):
		result = result.merge(rects[i])
	return result


func _push_unit_out_of_rect(unit: RtsPathfindingLabUnit, rect: Rect2) -> void:
	var left := absf(unit.position.x - rect.position.x)
	var right := absf(rect.position.x + rect.size.x - unit.position.x)
	var top := absf(unit.position.y - rect.position.y)
	var bottom := absf(rect.position.y + rect.size.y - unit.position.y)
	var min_side := minf(minf(left, right), minf(top, bottom))
	var target := unit.position
	if is_equal_approx(min_side, left):
		target.x = rect.position.x - 0.5
	elif is_equal_approx(min_side, right):
		target.x = rect.position.x + rect.size.x + 0.5
	elif is_equal_approx(min_side, top):
		target.y = rect.position.y - 0.5
	else:
		target.y = rect.position.y + rect.size.y + 0.5
	target = _clamp_unit_point(target, unit.radius)
	_apply_static_push_displacement(unit, target - unit.position)


func _settle_idle_unit(unit: RtsPathfindingLabUnit) -> void:
	unit.target = unit.position
	unit.path.clear()
	unit.path_index = 0
	unit.arrived = true
	unit.has_move_order = false
	unit.replan_timer = 0.0
	_clear_stuck_progress(unit)
	_canonical_target_by_unit.erase(unit.id)
	_remove_queued_replan(unit.id)


func _reset_stuck_progress(unit: RtsPathfindingLabUnit) -> void:
	_last_target_error_by_unit[unit.id] = INF
	_stalled_ticks_by_unit[unit.id] = 0
	_active_order_ticks_by_unit[unit.id] = 0


func _clear_stuck_progress(unit: RtsPathfindingLabUnit) -> void:
	_last_target_error_by_unit.erase(unit.id)
	_stalled_ticks_by_unit.erase(unit.id)
	_active_order_ticks_by_unit.erase(unit.id)


func _remove_queued_replan(unit_id: String) -> void:
	var index := _replan_queue.find(unit_id)
	if index >= 0:
		_replan_queue.remove_at(index)


func _active_move_order_count() -> int:
	var result := 0
	for unit in get_mobile_units():
		if unit.has_move_order:
			result += 1
	return result


func _formation_offsets(count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count == 1:
		result.append(Vector2.ZERO)
		return result
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


func _clamp_unit_point(point: Vector2, radius: float) -> Vector2:
	var safe_radius := maxf(radius, 0.0)
	return Vector2(
		clampf(point.x, safe_radius, maxf(safe_radius, map_size.x - safe_radius)),
		clampf(point.y, safe_radius, maxf(safe_radius, map_size.y - safe_radius))
	)
