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
