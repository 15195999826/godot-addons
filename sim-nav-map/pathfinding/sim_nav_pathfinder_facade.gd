class_name SimNavPathfinderFacade
extends RefCounted


var _nav_map: SimNavMap = null
var _hierarchical: SimNavHierarchicalPathfinder = null
var _long: SimNavLongPathfinder = null


func _init(
	nav_map: SimNavMap = null,
	hierarchical: SimNavHierarchicalPathfinder = null,
	long_pathfinder: SimNavLongPathfinder = null
) -> void:
	_nav_map = nav_map
	_hierarchical = hierarchical
	_long = long_pathfinder


func recompute_dirty(passability_masks: Array[int], clear_dirty_navcells: bool = true) -> Dictionary:
	if _nav_map == null:
		return {
			"dirty_navcells": 0,
			"changed_obstruction_navcells": 0,
			"rebuilt_chunks": 0,
			"invalidated_long_path_cache": false,
		}

	var changed_obstruction_navcells := _nav_map.rasterize_dirty_obstructions()
	var dirty_navcells := _nav_map.collect_dirty_navcells().size()
	var rebuilt_chunks := 0
	if dirty_navcells > 0 and _hierarchical != null:
		rebuilt_chunks = _hierarchical.recompute_dirty(_nav_map, passability_masks)
	if dirty_navcells > 0 and _long != null:
		_long.invalidate_jump_point_cache()
	if clear_dirty_navcells and dirty_navcells > 0:
		_nav_map.clear_dirty_navcells()
	return {
		"dirty_navcells": dirty_navcells,
		"changed_obstruction_navcells": changed_obstruction_navcells,
		"rebuilt_chunks": rebuilt_chunks,
		"invalidated_long_path_cache": dirty_navcells > 0 and _long != null,
	}


func query_reachability(
	start_world: Vector2,
	goal: SimNavPathGoal,
	pass_mask: int,
	passability_class_name: String = ""
) -> SimNavReachabilityResult:
	if _nav_map == null or _hierarchical == null:
		var missing_result := SimNavReachabilityResult.new()
		missing_result.configure_query(Vector2i(-1, -1), goal, pass_mask, passability_class_name)
		missing_result.set_failure(SimNavReachabilityResult.FAILURE_NOT_RECOMPUTED)
		return missing_result
	var start_cell := _nav_map.world_to_navcell(start_world)
	return _hierarchical.query_goal_reachability(start_cell, goal, pass_mask, passability_class_name)


func compute_path_result(query: SimNavLongPathQuery) -> SimNavLongPathResult:
	var result := SimNavLongPathResult.new()
	if query == null:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_GOAL_MISSING)
		return result
	result.configure_query(query, _nav_map)
	if query.goal == null:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_GOAL_MISSING)
		return result
	if _nav_map == null or _long == null:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_NAV_MAP_MISSING)
		return result

	var working_query := query.clone()
	var reachability: SimNavReachabilityResult = null
	if _hierarchical != null and _hierarchical.is_recomputed():
		reachability = query_reachability(
			query.start_world,
			query.goal,
			query.pass_mask,
			query.passability_class_name
		)
		if reachability.is_failure():
			result.reachability_result = reachability
			result.canonicalization_reason = reachability.failure_reason
			result.effective_start_navcell = reachability.effective_start_navcell
			result.set_failure(_status_for_reachability_failure(reachability), _failure_for_reachability_failure(reachability))
			return result
		if reachability.has_canonical_goal():
			working_query.goal = reachability.canonical_goal.clone()
			if reachability.effective_start_navcell != reachability.start_navcell:
				working_query.start_world = _nav_map.navcell_center_world(reachability.effective_start_navcell)

	var path_result := _long.compute_path_result(working_query)
	if reachability != null:
		_apply_reachability_metadata(path_result, query, reachability)
	return path_result


func compute_path_immediate(start_world: Vector2, goal: SimNavPathGoal, pass_mask: int) -> SimNavWaypointPath:
	if _nav_map == null or _long == null or goal == null:
		return SimNavWaypointPath.new()
	var path_goal := goal
	if _hierarchical != null and _hierarchical.is_recomputed():
		var reachability := query_reachability(start_world, goal, pass_mask)
		if reachability.has_canonical_goal():
			path_goal = reachability.canonical_goal
			if reachability.canonicalized:
				goal.copy_from(path_goal)
	return _long.compute_path_immediate(start_world, path_goal, pass_mask)


func validate_movement_line(
	start_world: Vector2,
	target_world: Vector2,
	clearance: float,
	pass_mask: int,
	obstruction_filter: SimNavObstructionFilter = null
) -> SimNavMovementLineResult:
	return _validate_line(start_world, target_world, clearance, pass_mask, obstruction_filter, false)


func validate_unit_line(
	start_world: Vector2,
	target_world: Vector2,
	clearance: float,
	obstruction_filter: SimNavObstructionFilter = null
) -> SimNavMovementLineResult:
	return _validate_line(start_world, target_world, clearance, 0, obstruction_filter, true)


func get_navigation_diagnostics(passability_masks: Array[int] = []) -> Dictionary:
	return {
		"map": _nav_map.get_diagnostics() if _nav_map != null else {},
		"hierarchical": _hierarchical.get_diagnostics(passability_masks) if _hierarchical != null else {},
		"has_long_pathfinder": _long != null,
	}


func _apply_reachability_metadata(
	result: SimNavLongPathResult,
	query: SimNavLongPathQuery,
	reachability: SimNavReachabilityResult
) -> void:
	if result == null or reachability == null:
		return
	result.reachability_result = reachability
	result.start_world = query.start_world
	result.start_navcell = reachability.start_navcell
	result.effective_start_navcell = reachability.effective_start_navcell
	result.effective_start_world = _nav_map.navcell_center_world(reachability.effective_start_navcell)
	result.pass_mask = reachability.pass_mask
	result.passability_class_name = reachability.passability_class_name
	result.query_goal = query.goal.clone() if query.goal != null else null
	result.canonical_goal = reachability.canonical_goal.clone() if reachability.has_canonical_goal() else null
	result.canonical_navcell = reachability.canonical_navcell
	result.canonicalized = reachability.canonicalized
	result.canonicalization_reason = reachability.failure_reason if reachability.canonicalized else SimNavReachabilityResult.FAILURE_NONE
	result.start_recovered = reachability.effective_start_navcell != reachability.start_navcell
	if not result.is_success():
		return
	if result.start_recovered:
		result.status = SimNavLongPathResult.STATUS_START_RECOVERED
	elif result.canonicalized:
		result.status = SimNavLongPathResult.STATUS_CANONICALIZED


func _status_for_reachability_failure(reachability: SimNavReachabilityResult) -> String:
	match reachability.failure_reason:
		SimNavReachabilityResult.FAILURE_NO_START_REGION:
			return SimNavLongPathResult.STATUS_INVALID_START
		SimNavReachabilityResult.FAILURE_NO_REACHABLE_GOAL, SimNavReachabilityResult.FAILURE_ORIGINAL_GOAL_UNREACHABLE:
			return SimNavLongPathResult.STATUS_UNREACHABLE
	return SimNavLongPathResult.STATUS_INVALID_QUERY


func _failure_for_reachability_failure(reachability: SimNavReachabilityResult) -> String:
	match reachability.failure_reason:
		SimNavReachabilityResult.FAILURE_NO_START_REGION:
			return SimNavLongPathResult.FAILURE_START_BLOCKED
		SimNavReachabilityResult.FAILURE_NO_REACHABLE_GOAL, SimNavReachabilityResult.FAILURE_ORIGINAL_GOAL_UNREACHABLE:
			return SimNavLongPathResult.FAILURE_NO_ROUTE
		SimNavReachabilityResult.FAILURE_INVALID_QUERY:
			return SimNavLongPathResult.FAILURE_GOAL_MISSING
	return SimNavLongPathResult.FAILURE_NAV_MAP_MISSING


func _validate_line(
	start_world: Vector2,
	target_world: Vector2,
	clearance: float,
	pass_mask: int,
	obstruction_filter: SimNavObstructionFilter,
	unit_only: bool
) -> SimNavMovementLineResult:
	var filter := obstruction_filter.clone() if obstruction_filter != null else SimNavObstructionFilter.new()
	if unit_only:
		filter.include_static = false
		filter.include_units = true
	var result := SimNavMovementLineResult.new()
	result.configure_query(start_world, target_world, clearance, pass_mask, filter, unit_only)
	if _nav_map == null:
		result.set_invalid(SimNavMovementLineResult.FAILURE_NAV_MAP_MISSING)
		return result
	if not unit_only and pass_mask != 0:
		var blocked_navcell := _first_blocked_line_navcell(start_world, target_world, clearance, pass_mask, result)
		if not blocked_navcell.is_empty():
			result.set_passability_blocked(
				str(blocked_navcell.get("reason", SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED)),
				blocked_navcell.get("coord", Vector2i(-1, -1)) as Vector2i
			)
			return result
	var shapes := _collect_line_obstructions(start_world, target_world, clearance, filter, unit_only)
	result.checked_obstruction_count = shapes.size()
	var blocking_shape := SimNavLineOfSight.first_blocking_shape(start_world, target_world, shapes, maxf(clearance, 0.000001))
	if blocking_shape != null:
		result.set_obstruction_blocked(blocking_shape)
		return result
	result.set_clear()
	return result


func _first_blocked_line_navcell(
	start_world: Vector2,
	target_world: Vector2,
	_clearance: float,
	pass_mask: int,
	result: SimNavMovementLineResult
) -> Dictionary:
	var origin := _nav_map.origin
	var cell_size := _nav_map.navcell_size
	var i0 := int(floor((start_world.x - origin.x) / cell_size))
	var j0 := int(floor((start_world.y - origin.y) / cell_size))
	var i1 := int(floor((target_world.x - origin.x) / cell_size))
	var j1 := int(floor((target_world.y - origin.y) / cell_size))
	var current := Vector2i(i0, j0)
	var target := Vector2i(i1, j1)
	var initial := _line_navcell_failure(current, target, pass_mask, true, result)
	if not initial.is_empty():
		return initial
	if current == target:
		return {}

	var dx := target_world.x - start_world.x
	var dy := target_world.y - start_world.y
	var step_i := 0
	var step_j := 0
	var t_max_x := INF
	var t_max_y := INF
	var delta_t_x := INF
	var delta_t_y := INF
	if dx > 0.0:
		step_i = 1
		t_max_x = (origin.x + float(i0 + 1) * cell_size - start_world.x) / dx
		delta_t_x = cell_size / dx
	elif dx < 0.0:
		step_i = -1
		t_max_x = (origin.x + float(i0) * cell_size - start_world.x) / dx
		delta_t_x = -cell_size / dx
	if dy > 0.0:
		step_j = 1
		t_max_y = (origin.y + float(j0 + 1) * cell_size - start_world.y) / dy
		delta_t_y = cell_size / dy
	elif dy < 0.0:
		step_j = -1
		t_max_y = (origin.y + float(j0) * cell_size - start_world.y) / dy
		delta_t_y = -cell_size / dy

	var max_steps := absi(i1 - i0) + absi(j1 - j0) + 4
	while current != target and max_steps > 0:
		max_steps -= 1
		if t_max_x < t_max_y:
			current.x += step_i
			t_max_x += delta_t_x
		else:
			current.y += step_j
			t_max_y += delta_t_y
		var failure := _line_navcell_failure(current, target, pass_mask, false, result)
		if not failure.is_empty():
			return failure
	return {}


func _line_navcell_failure(
	coord: Vector2i,
	target_coord: Vector2i,
	pass_mask: int,
	is_start: bool,
	result: SimNavMovementLineResult
) -> Dictionary:
	result.checked_navcell_count += 1
	if not _nav_map.is_valid_navcell(coord):
		var reason := SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED
		if is_start:
			reason = SimNavMovementLineResult.FAILURE_START_OUT_OF_BOUNDS
		elif coord == target_coord:
			reason = SimNavMovementLineResult.FAILURE_END_OUT_OF_BOUNDS
		return {
			"coord": coord,
			"reason": reason,
		}
	if not _nav_map.is_passable_navcell(coord, pass_mask):
		return {
			"coord": coord,
			"reason": SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED,
		}
	return {}


func _collect_line_obstructions(
	start_world: Vector2,
	target_world: Vector2,
	clearance: float,
	filter: SimNavObstructionFilter,
	unit_only: bool
) -> Array[SimNavObstructionShape]:
	var center := (start_world + target_world) * 0.5
	var query_range := start_world.distance_to(target_world) * 0.5 + clearance + _nav_map.navcell_size
	var shapes := _nav_map.get_obstruction_shapes_in_range_filtered(center, query_range, filter)
	var result: Array[SimNavObstructionShape] = []
	for shape in shapes:
		if unit_only and not (shape is SimNavObstructionShapeUnit):
			continue
		if shape is SimNavObstructionShapeStatic and (shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		if shape is SimNavObstructionShapeUnit and (shape.flags & SimNavObstructionFlags.BLOCK_MOVEMENT) == 0:
			continue
		result.append(shape)
	return result
