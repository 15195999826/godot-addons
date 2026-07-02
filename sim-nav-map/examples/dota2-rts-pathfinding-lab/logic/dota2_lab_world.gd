class_name Dota2LabWorld
extends RefCounted

# Dota2 RTS Pathfinding Lab — world.
#
# Holds units + static obstacles + pathfinder + motion engine. The whole
# per-tick pipeline is one engine call (commit-then-resolve inside); planning
# is synchronous at command time, so there is no result-collection phase and
# no request queue to drain.

const MAX_RECENT_MOTION_UPDATES := 160
const MAX_RECENT_FANOUT_ASSIGNMENTS := 160
const DEFAULT_OBSTACLE_SIZE := Vector2(64.0, 64.0)
const DEFAULT_BLOCKER_RADIUS := 14.0
const TARGET_FANOUT_MAX_RINGS := 3
const TARGET_FANOUT_UNIT_RADIUS_FACTOR := 7.0


var map_size: Vector2 = Vector2(1320.0, 900.0)
var obstacles: Array[Dota2LabObstacle] = []
var units: Array[Dota2LabUnit] = []
var pathfinder: Dota2LabPathfinderWrapper = null
var motion: Dota2LabMotionEngine = null
var tick_count: int = 0
var orders_completed: int = 0
var orders_failed: int = 0
var recent_motion_updates: Array[Dictionary] = []
var recent_fanout_assignments: Array[Dictionary] = []
var last_fanout_assignments: Array[Dictionary] = []
var current_target: Vector2 = Vector2(1160.0, 450.0)
var _obstacle_seq: int = 0
var _blocker_seq: int = 0


func _init() -> void:
	pathfinder = Dota2LabPathfinderWrapper.new(map_size)
	motion = Dota2LabMotionEngine.new()
	setup_default()


# Speed tiers for the default scene (body-block probing: fast units catch up
# to and squeeze past slow ones). Frontend colors by tier.
const SPEED_SLOW := 70.0
const SPEED_MID := 110.0
const SPEED_FAST := 165.0


# Default scene: 8 mobile units on the west in three speed tiers
# (3 slow / 3 mid / 2 fast), 1 unpushable red blocker mid-map, and three
# static obstacles forming a legible corridor.
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
		Dota2LabUnit.new("slow_0", "slow", Vector2(110.0, 420.0), 11.0, SPEED_SLOW, true),
		Dota2LabUnit.new("slow_1", "slow", Vector2(110.0, 480.0), 11.0, SPEED_SLOW, true),
		Dota2LabUnit.new("slow_2", "slow", Vector2(160.0, 365.0), 11.0, SPEED_SLOW, true),
		Dota2LabUnit.new("mid_0", "mid", Vector2(160.0, 535.0), 11.0, SPEED_MID, true),
		Dota2LabUnit.new("mid_1", "mid", Vector2(210.0, 420.0), 11.0, SPEED_MID, true),
		Dota2LabUnit.new("mid_2", "mid", Vector2(210.0, 480.0), 11.0, SPEED_MID, true),
		Dota2LabUnit.new("fast_0", "fast", Vector2(260.0, 395.0), 11.0, SPEED_FAST, true),
		Dota2LabUnit.new("fast_1", "fast", Vector2(260.0, 505.0), 11.0, SPEED_FAST, true),
		Dota2LabUnit.new("red_blocker", "red", Vector2(470.0, 450.0), 13.0, 0.0, false),
	]
	rebuild_navigation()
	tick_count = 0
	orders_completed = 0
	orders_failed = 0
	recent_motion_updates.clear()
	recent_fanout_assignments.clear()
	last_fanout_assignments.clear()
	clear_traces()


func step(delta: float) -> void:
	var events := motion.step(units, pathfinder, delta, tick_count)
	for event in events:
		if str(event.get("kind", "")) == Dota2LabMotionEngine.EVENT_ORDER_FAILED:
			orders_failed += 1
		else:
			orders_completed += 1
		recent_motion_updates.append(event)
		while recent_motion_updates.size() > MAX_RECENT_MOTION_UPDATES:
			recent_motion_updates.pop_front()
	tick_count += 1


# ───────────────── Command API (used by frontend and smoke tests) ───────────

func issue_move(unit_id: String, goal: Vector2) -> void:
	var unit := get_unit(unit_id)
	if unit == null or not unit.mobile:
		return
	last_fanout_assignments.clear()
	motion.issue_move(unit, goal, pathfinder, tick_count)


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
	motion.cancel_move(unit, pathfinder, tick_count)


# ───────────────── Scene editing (used by frontend keys 2/3/4) ──────────────

func add_static_obstacle(center: Vector2, size: Vector2 = DEFAULT_OBSTACLE_SIZE) -> String:
	_obstacle_seq += 1
	var obstacle_id := "custom_obstacle_%d" % _obstacle_seq
	obstacles.append(Dota2LabObstacle.new(obstacle_id, _clamp_point_to_map(center), size))
	rebuild_navigation()
	replan_all_active()
	return obstacle_id


# Blockers never enter the nav map, so adding one does not invalidate paths —
# movers flow around it through the separation solve.
func add_blocker(center: Vector2, radius: float = DEFAULT_BLOCKER_RADIUS) -> String:
	_blocker_seq += 1
	var blocker_id := "custom_blocker_%d" % _blocker_seq
	units.append(Dota2LabUnit.new(blocker_id, "red", _clamp_unit_point(center, radius), radius, 0.0, false))
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
		rebuild_navigation()
		replan_all_active()
		return removed_obstacle.id
	var removed_unit := units[best_index]
	units.remove_at(best_index)
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
	var metrics := motion.diagnostics(units)
	metrics["tick_count"] = tick_count
	metrics["mobile_count"] = get_mobile_units().size()
	metrics["orders_completed"] = orders_completed
	metrics["orders_failed"] = orders_failed
	metrics["last_fanout_assignments"] = last_fanout_assignments.duplicate(true)
	metrics["recent_fanout_assignments"] = recent_fanout_assignments.duplicate(true)
	metrics["fanout_assignment_count"] = recent_fanout_assignments.size()
	metrics["pathfinder"] = pathfinder.diagnostics()
	return metrics


func rebuild_navigation() -> void:
	pathfinder.rebuild_context(obstacles)
	# The rebuilt queue starts fresh; old tickets would never resolve.
	motion.invalidate_pending_plans(units)


# ───────────────── Internal helpers ─────────────────────────────────────────

func _issue_move_units(target_units: Array[Dota2LabUnit], goal: Vector2, command_kind: String) -> void:
	if target_units.size() <= 1:
		last_fanout_assignments.clear()
		for unit in target_units:
			motion.issue_move(unit, goal, pathfinder, tick_count)
		return

	var assignments := _build_target_fanout_assignments(target_units, goal, command_kind)
	last_fanout_assignments.clear()
	for assignment in assignments:
		_record_fanout_assignment(assignment)
		var unit: Dota2LabUnit = assignment.get("unit", null) as Dota2LabUnit
		if unit == null:
			continue
		var assigned_target: Vector2 = assignment.get("assigned_target", goal) as Vector2
		motion.issue_move(unit, assigned_target, pathfinder, tick_count)


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
		})
	return assignments


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


func replan_all_active() -> void:
	for unit in get_mobile_units():
		motion.replan_active(unit, pathfinder, tick_count)


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
