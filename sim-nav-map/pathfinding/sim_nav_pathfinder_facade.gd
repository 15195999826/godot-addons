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
