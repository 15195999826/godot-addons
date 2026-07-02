class_name SimNavNativeBridge


# Static converters between the SimNav GDScript DTO classes and the native
# backend's Dictionary boundary (SimNavNativeFacade). All native classes are
# reached via ClassDB indirection — this file must parse on platforms without
# a built native library. Conversion happens at plan granularity (a few times
# per tick at most); per-tick hot calls (movement_line_clear) cross as plain
# bools and never build DTOs.


static func available() -> bool:
	return (
		ClassDB.class_exists("SimNavNativeSupport")
		and ClassDB.class_exists("SimNavNativeMap")
		and ClassDB.class_exists("SimNavNativeFacade")
	)


static func goal_to_dict(goal: SimNavPathGoal) -> Dictionary:
	if goal == null:
		return {}
	return {
		"type": goal.type,
		"center": goal.center,
		"hw": goal.hw,
		"hh": goal.hh,
		"u": goal.u,
		"v": goal.v,
		"maxdist": goal.maxdist,
	}


static func dict_to_goal(data: Variant) -> SimNavPathGoal:
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		return null
	var dict := data as Dictionary
	var goal := SimNavPathGoal.new(int(dict.get("type", 0)), dict.get("center", Vector2.ZERO))
	goal.hw = float(dict.get("hw", 0.0))
	goal.hh = float(dict.get("hh", 0.0))
	goal.u = dict.get("u", Vector2(1.0, 0.0))
	goal.v = dict.get("v", Vector2(0.0, 1.0))
	goal.maxdist = float(dict.get("maxdist", 0.0))
	return goal


static func query_to_dict(query: SimNavLongPathQuery) -> Dictionary:
	var excluded: Array = []
	for region in query.excluded_regions:
		var region_dict := region as Dictionary
		excluded.append({
			"center": region_dict.get("center", Vector2.ZERO),
			"radius": maxf(0.0, float(region_dict.get("radius", 0.0))),
		})
	return {
		"start_world": query.start_world,
		"goal": goal_to_dict(query.goal),
		"pass_mask": query.pass_mask,
		"passability_class_name": query.passability_class_name,
		"excluded_regions": excluded,
		"post_process": query.post_process,
		"waypoint_spacing": query.waypoint_spacing,
	}


static func to_reachability_result(data: Variant) -> SimNavReachabilityResult:
	if not (data is Dictionary):
		return null
	var dict := data as Dictionary
	var result := SimNavReachabilityResult.new()
	result.is_reachable = bool(dict.get("is_reachable", false))
	result.canonicalized = bool(dict.get("canonicalized", false))
	result.failure_reason = str(dict.get("failure_reason", SimNavReachabilityResult.FAILURE_NONE))
	result.pass_mask = int(dict.get("pass_mask", 0))
	result.passability_class_name = str(dict.get("passability_class_name", ""))
	result.start_navcell = dict.get("start_navcell", Vector2i(-1, -1))
	result.effective_start_navcell = dict.get("effective_start_navcell", Vector2i(-1, -1))
	result.canonical_navcell = dict.get("canonical_navcell", Vector2i(-1, -1))
	result.start_global_region = int(dict.get("start_global_region", 0))
	result.canonical_global_region = int(dict.get("canonical_global_region", 0))
	result.query_goal = dict_to_goal(dict.get("query_goal"))
	result.canonical_goal = dict_to_goal(dict.get("canonical_goal"))
	return result


static func to_long_path_result(dict: Dictionary) -> SimNavLongPathResult:
	var result := SimNavLongPathResult.new()
	result.status = str(dict.get("status", SimNavLongPathResult.STATUS_INVALID_QUERY))
	result.failure_reason = str(dict.get("failure_reason", SimNavLongPathResult.FAILURE_NONE))
	result.canonicalization_reason = str(dict.get("canonicalization_reason", SimNavReachabilityResult.FAILURE_NONE))
	result.pass_mask = int(dict.get("pass_mask", 0))
	result.passability_class_name = str(dict.get("passability_class_name", ""))
	result.start_world = dict.get("start_world", Vector2.ZERO)
	result.effective_start_world = dict.get("effective_start_world", Vector2.ZERO)
	result.start_navcell = dict.get("start_navcell", Vector2i(-1, -1))
	result.effective_start_navcell = dict.get("effective_start_navcell", Vector2i(-1, -1))
	result.canonical_navcell = dict.get("canonical_navcell", Vector2i(-1, -1))
	result.query_goal = dict_to_goal(dict.get("query_goal"))
	result.canonical_goal = dict_to_goal(dict.get("canonical_goal"))
	result.canonicalized = bool(dict.get("canonicalized", false))
	result.start_recovered = bool(dict.get("start_recovered", false))
	result.reachability_result = to_reachability_result(dict.get("reachability_result"))
	var excluded: Array[Dictionary] = []
	for region in dict.get("excluded_regions", []):
		excluded.append(region as Dictionary)
	result.excluded_regions = excluded
	result.post_process = str(dict.get("post_process", SimNavLongPathQuery.POST_PROCESS_RAW))
	result.waypoint_spacing = float(dict.get("waypoint_spacing", 0.0))
	result.waypoint_order = str(dict.get("waypoint_order", SimNavLongPathResult.WAYPOINT_ORDER_REVERSE_CONSUMPTION))
	result.raw_navcell_order = str(dict.get("raw_navcell_order", SimNavLongPathResult.RAW_NAVCELL_ORDER_START_TO_GOAL))

	var raw_cells_packed: PackedInt32Array = dict.get("raw_navcell_path", PackedInt32Array())
	var raw_cells: Array[Vector2i] = []
	@warning_ignore("integer_division")
	var cell_count: int = raw_cells_packed.size() / 2
	for i in range(cell_count):
		raw_cells.append(Vector2i(raw_cells_packed[i * 2], raw_cells_packed[i * 2 + 1]))
	result.raw_navcell_path = raw_cells

	var raw_path := SimNavWaypointPath.new()
	raw_path.waypoints = dict.get("raw_waypoint_path", PackedVector2Array())
	result.raw_waypoint_path = raw_path
	var refined_path := SimNavWaypointPath.new()
	refined_path.waypoints = dict.get("refined_waypoint_path", PackedVector2Array())
	result.refined_waypoint_path = refined_path
	result.path = result.refined_waypoint_path

	result.path_cost = int(dict.get("path_cost", 0))
	result.path_length = float(dict.get("path_length", 0.0))
	result.raw_navcell_count = int(dict.get("raw_navcell_count", 0))
	result.raw_waypoint_count = int(dict.get("raw_waypoint_count", 0))
	result.refined_waypoint_count = int(dict.get("refined_waypoint_count", 0))
	result.search_algorithm = str(dict.get("search_algorithm", ""))
	result.search_expansion_count = int(dict.get("search_expansion_count", 0))
	result.search_push_count = int(dict.get("search_push_count", 0))
	result.search_jump_count = int(dict.get("search_jump_count", 0))
	result.search_closed_count = int(dict.get("search_closed_count", 0))
	result.search_max_open_count = int(dict.get("search_max_open_count", 0))
	result.search_path_cell_count = int(dict.get("search_path_cell_count", 0))
	return result
