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
const MAX_RECENT_FANOUT_ASSIGNMENTS := 160
const MAX_RECENT_COMMAND_RELEASES := 160
const DEFAULT_OBSTACLE_SIZE := Vector2(64.0, 64.0)
const DEFAULT_BLOCKER_RADIUS := 14.0
const TARGET_FANOUT_MAX_RINGS := 3
const TARGET_FANOUT_UNIT_RADIUS_FACTOR := 7.0
const COMMAND_RELEASE_BATCH_SIZE := 1
const COMMAND_RELEASE_INTERVAL_TICKS := 75


var map_size: Vector2 = Vector2(1320.0, 900.0)
var obstacles: Array[Dota2LabObstacle] = []
var units: Array[Dota2LabUnit] = []
var pathfinder: Dota2LabPathfinderWrapper = null
var motion: Dota2LabMotionController = null
var tick_count: int = 0
var recent_motion_updates: Array[Dictionary] = []
var recent_fanout_assignments: Array[Dictionary] = []
var last_fanout_assignments: Array[Dictionary] = []
var pending_command_releases: Array[Dictionary] = []
var recent_command_releases: Array[Dictionary] = []
var current_target: Vector2 = Vector2(1160.0, 450.0)
var _obstacle_seq: int = 0
var _blocker_seq: int = 0


func _init() -> void:
	pathfinder = Dota2LabPathfinderWrapper.new(map_size)
	motion = Dota2LabMotionController.new()
	setup_default()


# Default scene: 8 mobile blue units on the west, 1 static red blocker mid-map,
# and three static obstacles forming a more legible corridor. The composition
# mirrors the 0AD lab's readable manual-test layout while keeping Dota2 motion
# rules: hard block, no push, per-unit orders.
func setup_default() -> void:
	_obstacle_seq = 0
	_blocker_seq = 0
	current_target = Vector2(1160.0, 450.0)
	obstacles = [
		Dota2LabObstacle.new("center_block", Vector2(690.0, 450.0), Vector2(76.0, 280.0)),
		Dota2LabObstacle.new("north_block", Vector2(690.0, 190.0), Vector2(310.0, 100.0)),
		Dota2LabObstacle.new("south_block", Vector2(690.0, 710.0), Vector2(310.0, 100.0)),
	]
	units = [
		Dota2LabUnit.new("blue_0", "blue", Vector2(110.0, 420.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_1", "blue", Vector2(110.0, 480.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_2", "blue", Vector2(160.0, 365.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_3", "blue", Vector2(160.0, 535.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_4", "blue", Vector2(210.0, 420.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_5", "blue", Vector2(210.0, 480.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_6", "blue", Vector2(260.0, 395.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blue_7", "blue", Vector2(260.0, 505.0), 11.0, 110.0, true),
		Dota2LabUnit.new("red_blocker", "red", Vector2(470.0, 450.0), 13.0, 0.0, false),
	]
	_rebuild_navigation()
	tick_count = 0
	recent_motion_updates.clear()
	recent_fanout_assignments.clear()
	last_fanout_assignments.clear()
	pending_command_releases.clear()
	recent_command_releases.clear()
	clear_traces()


func step(delta: float) -> void:
	# Phase 0: release delayed command-layer orders. This only starts normal
	# per-unit move orders; it does not alter the motion FSM.
	_release_due_command_orders()

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
	var unit_ids: Array[String] = [unit_id]
	_remove_pending_command_releases_for_ids(unit_ids)
	last_fanout_assignments.clear()
	motion.begin_new_move_order(unit, goal, pathfinder, tick_count)


func issue_move_all_mobile(goal: Vector2) -> void:
	current_target = goal
	_issue_move_units(get_mobile_units(), goal, "move_all")


func issue_move_ids(unit_ids: Array[String], goal: Vector2) -> void:
	current_target = goal
	_issue_move_units(_mobile_units_for_ids(unit_ids), goal, "move_ids")


func cancel_move(unit_id: String) -> void:
	var unit := get_unit(unit_id)
	if unit == null:
		return
	var unit_ids: Array[String] = [unit_id]
	_remove_pending_command_releases_for_ids(unit_ids)
	motion.cancel_move_order(unit, pathfinder, tick_count, "cancelled")


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
	metrics["last_fanout_assignments"] = last_fanout_assignments.duplicate(true)
	metrics["recent_fanout_assignments"] = recent_fanout_assignments.duplicate(true)
	metrics["fanout_assignment_count"] = recent_fanout_assignments.size()
	metrics["pending_command_release_count"] = pending_command_releases.size()
	metrics["pending_command_releases"] = _pending_command_release_snapshots()
	metrics["recent_command_releases"] = recent_command_releases.duplicate(true)
	metrics["pathfinder"] = pathfinder.diagnostics()
	return metrics


# ───────────────── Internal helpers ─────────────────────────────────────────

func _issue_move_units(target_units: Array[Dota2LabUnit], goal: Vector2, command_kind: String) -> void:
	var target_unit_ids := _unit_ids_for_units(target_units)
	_remove_pending_command_releases_for_ids(target_unit_ids)
	if target_units.size() <= 1:
		last_fanout_assignments.clear()
		for unit in target_units:
			motion.begin_new_move_order(unit, goal, pathfinder, tick_count)
		return

	var assignments := _build_target_fanout_assignments(target_units, goal, command_kind)
	last_fanout_assignments.clear()
	for assignment in assignments:
		_record_fanout_assignment(assignment)
	_schedule_command_releases(assignments)
	_release_due_command_orders()


func _unit_ids_for_units(target_units: Array[Dota2LabUnit]) -> Array[String]:
	var result: Array[String] = []
	for unit in target_units:
		result.append(unit.id)
	return result


func _mobile_units_for_ids(unit_ids: Array[String]) -> Array[Dota2LabUnit]:
	var result: Array[Dota2LabUnit] = []
	var seen: Dictionary = {}
	for unit_id in unit_ids:
		if seen.has(unit_id):
			continue
		seen[unit_id] = true
		var unit := get_unit(unit_id)
		if unit != null and unit.mobile:
			result.append(unit)
	return result


func _build_target_fanout_assignments(
	target_units: Array[Dota2LabUnit],
	goal: Vector2,
	command_kind: String
) -> Array[Dictionary]:
	var sorted_units: Array[Dota2LabUnit] = target_units.duplicate()
	sorted_units.sort_custom(Callable(self, "_sort_units_by_id"))
	var command_direction := _command_direction(sorted_units, goal)
	var spacing := _target_fanout_spacing(sorted_units)
	var candidates := _target_fanout_candidates(goal, sorted_units.size(), spacing)
	var used_candidate_indices: Dictionary = {}
	var assignments: Array[Dictionary] = []
	for unit in sorted_units:
		var choice := _take_fanout_candidate(unit, goal, candidates, used_candidate_indices)
		var assigned_target: Vector2 = choice.get("assigned_target", goal) as Vector2
		assignments.append({
			"unit": unit,
			"unit_id": unit.id,
			"command": command_kind,
			"original_target": goal,
			"assigned_target": assigned_target,
			"status": str(choice.get("status", "no_slot")),
			"candidate_index": int(choice.get("candidate_index", -1)),
			"spacing": spacing,
			"release_projection": unit.position.dot(command_direction),
		})
	return assignments


func _schedule_command_releases(assignments: Array[Dictionary]) -> void:
	var sorted_assignments := assignments.duplicate(true)
	sorted_assignments.sort_custom(Callable(self, "_sort_assignments_front_first"))
	for i in range(sorted_assignments.size()):
		var assignment: Dictionary = sorted_assignments[i] as Dictionary
		var unit: Dota2LabUnit = assignment.get("unit", null) as Dota2LabUnit
		if unit == null:
			continue
		motion.cancel_move_order(unit, pathfinder, tick_count, "command_release_replaced")
		var batch_index: int = i / COMMAND_RELEASE_BATCH_SIZE
		pending_command_releases.append({
			"release_tick": tick_count + batch_index * COMMAND_RELEASE_INTERVAL_TICKS,
			"unit_id": unit.id,
			"command": str(assignment.get("command", "")),
			"original_target": assignment.get("original_target", Vector2.ZERO) as Vector2,
			"assigned_target": assignment.get("assigned_target", unit.position) as Vector2,
			"fanout_status": str(assignment.get("status", "")),
			"candidate_index": int(assignment.get("candidate_index", -1)),
			"release_projection": float(assignment.get("release_projection", 0.0)),
		})


func _release_due_command_orders() -> void:
	if pending_command_releases.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for release in pending_command_releases:
		var release_tick := int(release.get("release_tick", tick_count))
		if release_tick > tick_count:
			remaining.append(release)
			continue
		var unit_id := str(release.get("unit_id", ""))
		var unit := get_unit(unit_id)
		if unit == null or not unit.mobile:
			_record_command_release(release, "skipped")
			continue
		var assigned_target: Vector2 = release.get("assigned_target", unit.position) as Vector2
		motion.begin_new_move_order(unit, assigned_target, pathfinder, tick_count)
		_record_command_release(release, "released")
	pending_command_releases = remaining


func _remove_pending_command_releases_for_ids(unit_ids: Array[String]) -> void:
	if pending_command_releases.is_empty() or unit_ids.is_empty():
		return
	var ids: Dictionary = {}
	for unit_id in unit_ids:
		ids[unit_id] = true
	var remaining: Array[Dictionary] = []
	for release in pending_command_releases:
		if ids.has(str(release.get("unit_id", ""))):
			_record_command_release(release, "cancelled")
			continue
		remaining.append(release)
	pending_command_releases = remaining


func _take_fanout_candidate(
	unit: Dota2LabUnit,
	goal: Vector2,
	candidates: Array[Vector2],
	used_candidate_indices: Dictionary
) -> Dictionary:
	for i in range(candidates.size()):
		if used_candidate_indices.has(i):
			continue
		var candidate := candidates[i]
		if not _fanout_candidate_is_acceptable(unit, candidate):
			continue
		used_candidate_indices[i] = true
		return {
			"assigned_target": candidate,
			"status": "assigned_original" if i == 0 else "assigned_offset",
			"candidate_index": i,
		}
	return {
		"assigned_target": goal,
		"status": "no_slot",
		"candidate_index": -1,
	}


func _target_fanout_spacing(target_units: Array[Dota2LabUnit]) -> float:
	var max_radius := 0.0
	for unit in target_units:
		max_radius = maxf(max_radius, unit.radius)
	return maxf(
		max_radius * TARGET_FANOUT_UNIT_RADIUS_FACTOR,
		maxf(pathfinder.default_clearance * 2.0, pathfinder.cell_size * 2.0)
	)


func _target_fanout_candidates(goal: Vector2, count: int, spacing: float) -> Array[Vector2]:
	var candidates: Array[Vector2] = [goal]
	if count <= 1:
		return candidates
	var ring := 1
	while candidates.size() < count and ring <= TARGET_FANOUT_MAX_RINGS:
		var radius := spacing * float(ring)
		var slot_count := maxi(6, int(ceil(TAU * radius / spacing)))
		for slot_index in range(slot_count):
			if candidates.size() >= count:
				break
			var angle := -PI * 0.5 + TAU * float(slot_index) / float(slot_count)
			candidates.append(goal + Vector2(cos(angle), sin(angle)) * radius)
		ring += 1
	return candidates


func _fanout_candidate_is_acceptable(unit: Dota2LabUnit, candidate: Vector2) -> bool:
	var clamped := _clamp_unit_point(candidate, unit.radius)
	if clamped.distance_to(candidate) > 0.001:
		return false
	for obstacle in obstacles:
		if obstacle.contains_point_with_clearance(candidate, unit.radius):
			return false
	if pathfinder.nav_map != null:
		var coord := pathfinder.nav_map.world_to_navcell(candidate)
		if not pathfinder.nav_map.is_passable_navcell(coord, pathfinder.pass_mask):
			return false
	return true


func _command_direction(target_units: Array[Dota2LabUnit], goal: Vector2) -> Vector2:
	if target_units.is_empty():
		return Vector2.RIGHT
	var center := Vector2.ZERO
	for unit in target_units:
		center += unit.position
	center /= float(target_units.size())
	var direction := goal - center
	if direction.length() <= 0.001:
		return Vector2.RIGHT
	return direction.normalized()


func _record_command_release(release: Dictionary, status: String) -> void:
	recent_command_releases.append({
		"tick": tick_count,
		"release_tick": int(release.get("release_tick", tick_count)),
		"status": status,
		"unit_id": str(release.get("unit_id", "")),
		"command": str(release.get("command", "")),
		"original_target": _vector_snapshot(release.get("original_target", Vector2.ZERO) as Vector2),
		"assigned_target": _vector_snapshot(release.get("assigned_target", Vector2.ZERO) as Vector2),
		"fanout_status": str(release.get("fanout_status", "")),
	})
	while recent_command_releases.size() > MAX_RECENT_COMMAND_RELEASES:
		recent_command_releases.pop_front()


func _pending_command_release_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for release in pending_command_releases:
		result.append({
			"release_tick": int(release.get("release_tick", tick_count)),
			"unit_id": str(release.get("unit_id", "")),
			"command": str(release.get("command", "")),
			"original_target": _vector_snapshot(release.get("original_target", Vector2.ZERO) as Vector2),
			"assigned_target": _vector_snapshot(release.get("assigned_target", Vector2.ZERO) as Vector2),
			"fanout_status": str(release.get("fanout_status", "")),
			"candidate_index": int(release.get("candidate_index", -1)),
		})
	return result


func _record_fanout_assignment(assignment: Dictionary) -> void:
	var unit_id := str(assignment.get("unit_id", ""))
	var snapshot := {
		"tick": tick_count,
		"command": str(assignment.get("command", "")),
		"unit_id": unit_id,
		"original_target": _vector_snapshot(assignment.get("original_target", Vector2.ZERO) as Vector2),
		"assigned_target": _vector_snapshot(assignment.get("assigned_target", Vector2.ZERO) as Vector2),
		"status": str(assignment.get("status", "")),
		"candidate_index": int(assignment.get("candidate_index", -1)),
		"spacing": float(assignment.get("spacing", 0.0)),
	}
	last_fanout_assignments.append(snapshot)
	recent_fanout_assignments.append(snapshot)
	while recent_fanout_assignments.size() > MAX_RECENT_FANOUT_ASSIGNMENTS:
		recent_fanout_assignments.pop_front()


func _sort_units_by_id(a: Dota2LabUnit, b: Dota2LabUnit) -> bool:
	return a.id < b.id


func _sort_assignments_front_first(a: Dictionary, b: Dictionary) -> bool:
	var projection_a := float(a.get("release_projection", 0.0))
	var projection_b := float(b.get("release_projection", 0.0))
	if not is_equal_approx(projection_a, projection_b):
		return projection_a > projection_b
	return str(a.get("unit_id", "")) < str(b.get("unit_id", ""))

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


func _vector_snapshot(point: Vector2) -> Dictionary:
	return {
		"x": point.x,
		"y": point.y,
	}
