class_name Dota2LabWorld
extends RefCounted

# Dota2 RTS Pathfinding Lab — world.
#
# Holds units + static obstacles + pathfinder + motion controller. Owns the
# per-tick phase order required by the motion design doc
# (docs/design-notes/motion-controller-design.md §4):
#
#   1. apply_path_results(unit)   for every unit
#   2. step_unit(unit, delta)     for every FOLLOWING unit
#   3. emit_motion_updates()      drain controller event buffer
#   4. queue.process_budget(N)    advance core's pending requests
#
# Order is fixed. Do not interleave.

const PATH_BUDGET_PER_TICK := 4
const MAX_RECENT_MOTION_UPDATES := 160
const DEFAULT_OBSTACLE_SIZE := Vector2(64.0, 64.0)
const DEFAULT_BLOCKER_RADIUS := 14.0


var map_size: Vector2 = Vector2(720.0, 420.0)
var obstacles: Array[Dota2LabObstacle] = []
var units: Array[Dota2LabUnit] = []
var pathfinder: Dota2LabPathfinderWrapper = null
var motion: Dota2LabMotionController = null
var tick_count: int = 0
var recent_motion_updates: Array[Dictionary] = []
var current_target: Vector2 = Vector2(610.0, 210.0)
var _obstacle_seq: int = 0
var _blocker_seq: int = 0


func _init() -> void:
	pathfinder = Dota2LabPathfinderWrapper.new(map_size)
	motion = Dota2LabMotionController.new()
	setup_default()


# Default scene: 4 mobile blue units on the west, 1 static red blocker mid-map,
# 2 static obstacles forming a corridor. Mirrors 0AD lab's default density
# (kept low — dota2 lab targets 10–40 units, not 100+).
func setup_default() -> void:
	_obstacle_seq = 0
	_blocker_seq = 0
	current_target = Vector2(610.0, 210.0)
	obstacles = [
		Dota2LabObstacle.new("obstacle_north", Vector2(360.0, 100.0), Vector2(120.0, 64.0)),
		Dota2LabObstacle.new("obstacle_south", Vector2(360.0, 320.0), Vector2(120.0, 64.0)),
	]
	units = [
		Dota2LabUnit.new("blue_0", "blue", Vector2(80.0, 170.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_1", "blue", Vector2(80.0, 210.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_2", "blue", Vector2(80.0, 250.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_3", "blue", Vector2(120.0, 210.0), 11.0, 110.0, true),
		Dota2LabUnit.new("red_blocker", "red", Vector2(280.0, 210.0), 13.0, 0.0, false),
	]
	_rebuild_navigation()
	tick_count = 0
	recent_motion_updates.clear()
	clear_traces()


func step(delta: float) -> void:
	# Phase 1: collect path results for every unit (drives WAITING_* → FOLLOWING/FAILED).
	for unit in units:
		motion.apply_path_results(unit, pathfinder, tick_count)

	# Phase 2: walk FOLLOWING units (step_unit returns early for others).
	# Refresh dynamic obstructions once before stepping so validate_movement_line
	# sees current unit positions.
	pathfinder.refresh_dynamic_units(units)
	for unit in units:
		if unit.mobile:
			motion.step_unit(unit, delta, pathfinder, units, tick_count)

	# Phase 3: drain motion update event buffer for frontend/smoke consumption.
	_dispatch_motion_updates()

	# Phase 4: advance the path request queue. Results land in next tick's
	# apply_path_results. This enforces the NO_SAME_TICK_TAKEOVER invariant
	# at the world level (in addition to step_unit's internal discipline).
	pathfinder.process_budget(units, PATH_BUDGET_PER_TICK)

	tick_count += 1


# ───────────────── Command API (used by frontend and smoke tests) ───────────

func issue_move(unit_id: String, goal: Vector2) -> void:
	var unit := get_unit(unit_id)
	if unit == null or not unit.mobile:
		return
	unit.begin_move_order(goal, tick_count)
	motion.start_move_order(unit, pathfinder, tick_count)


func issue_move_all_mobile(goal: Vector2) -> void:
	current_target = goal
	for unit in get_mobile_units():
		unit.begin_move_order(goal, tick_count)
		motion.start_move_order(unit, pathfinder, tick_count)


func issue_move_ids(unit_ids: Array[String], goal: Vector2) -> void:
	current_target = goal
	for unit_id in unit_ids:
		issue_move(unit_id, goal)


func cancel_move(unit_id: String) -> void:
	var unit := get_unit(unit_id)
	if unit == null:
		return
	unit.fail_order(tick_count, "cancelled")
	unit.state = Dota2LabUnit.STATE_IDLE


# ───────────────── Scene editing (used by frontend keys 2/3/4) ──────────────

func add_static_obstacle(center: Vector2, size: Vector2 = DEFAULT_OBSTACLE_SIZE) -> String:
	_obstacle_seq += 1
	var obstacle_id := "custom_obstacle_%d" % _obstacle_seq
	obstacles.append(Dota2LabObstacle.new(obstacle_id, _clamp_point_to_map(center), size))
	_rebuild_navigation()
	_replan_all_active()
	return obstacle_id


func add_blocker(center: Vector2, radius: float = DEFAULT_BLOCKER_RADIUS) -> String:
	_blocker_seq += 1
	var blocker_id := "custom_blocker_%d" % _blocker_seq
	units.append(Dota2LabUnit.new(blocker_id, "red", _clamp_unit_point(center, radius), radius, 0.0, false))
	_replan_all_active()
	return blocker_id


func remove_nearest_editable(point: Vector2, max_distance: float = 44.0) -> String:
	var best_kind := ""
	var best_index := -1
	var best_dist_sq := max_distance * max_distance
	for i in range(obstacles.size()):
		var obstacle := obstacles[i]
		var d2: float = obstacle.center.distance_squared_to(point)
		if d2 <= best_dist_sq:
			best_dist_sq = d2
			best_kind = "obstacle"
			best_index = i
	for i in range(units.size()):
		var unit := units[i]
		if unit.mobile:
			continue
		var d2: float = unit.position.distance_squared_to(point)
		if d2 <= best_dist_sq:
			best_dist_sq = d2
			best_kind = "blocker"
			best_index = i
	if best_index < 0:
		return ""
	if best_kind == "obstacle":
		var removed_obstacle := obstacles[best_index]
		obstacles.remove_at(best_index)
		_rebuild_navigation()
		_replan_all_active()
		return removed_obstacle.id
	var removed_unit := units[best_index]
	units.remove_at(best_index)
	_replan_all_active()
	return removed_unit.id


# ───────────────── Lookups ──────────────────────────────────────────────────

func get_unit(unit_id: String) -> Dota2LabUnit:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func get_mobile_units() -> Array[Dota2LabUnit]:
	var result: Array[Dota2LabUnit] = []
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
		var d2: float = unit.position.distance_squared_to(point)
		if d2 <= best_dist_sq:
			best_dist_sq = d2
			best_id = unit.id
	return best_id


func get_mobile_units_in_rect(rect: Rect2) -> Array[String]:
	var result: Array[String] = []
	for unit in get_mobile_units():
		if rect.has_point(unit.position):
			result.append(unit.id)
	return result


func clear_traces() -> void:
	for unit in units:
		unit.clear_trace()


# ───────────────── Diagnostics (smoke + frontend HUD) ───────────────────────

func get_metrics() -> Dictionary:
	var metrics := motion.diagnostics(units).duplicate(true)
	metrics["tick_count"] = tick_count
	metrics["mobile_count"] = get_mobile_units().size()
	metrics["pathfinder"] = pathfinder.diagnostics()
	return metrics


# ───────────────── Internal helpers ─────────────────────────────────────────

func _rebuild_navigation() -> void:
	pathfinder.rebuild_context(obstacles)


func _replan_all_active() -> void:
	for unit in get_mobile_units():
		if unit.state != Dota2LabUnit.STATE_IDLE and unit.state != Dota2LabUnit.STATE_FAILED:
			motion.replan_active(unit, pathfinder, tick_count)


func _dispatch_motion_updates() -> void:
	var updates := motion.drain_motion_updates()
	for update in updates:
		recent_motion_updates.append(update.to_snapshot())
		while recent_motion_updates.size() > MAX_RECENT_MOTION_UPDATES:
			recent_motion_updates.pop_front()


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
