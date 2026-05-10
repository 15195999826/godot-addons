class_name SimNavLongPathResult
extends RefCounted


const STATUS_SUCCESS := "success"
const STATUS_CANONICALIZED := "canonicalized"
const STATUS_START_RECOVERED := "start_recovered"
const STATUS_DIRECT_GOAL := "direct_goal"
const STATUS_UNREACHABLE := "unreachable"
const STATUS_NO_PATH := "no_path"
const STATUS_INVALID_START := "invalid_start"
const STATUS_INVALID_QUERY := "invalid_query"

const FAILURE_NONE := "none"
const FAILURE_NAV_MAP_MISSING := "nav_map_missing"
const FAILURE_GOAL_MISSING := "goal_missing"
const FAILURE_PASS_MASK_MISSING := "pass_mask_missing"
const FAILURE_MAP_TOO_LARGE := "map_too_large"
const FAILURE_START_OUT_OF_BOUNDS := "start_out_of_bounds"
const FAILURE_START_BLOCKED := "start_blocked"
const FAILURE_GOAL_OUT_OF_BOUNDS := "goal_out_of_bounds"
const FAILURE_GOAL_BLOCKED := "goal_blocked"
const FAILURE_NO_ROUTE := "no_route"

const WAYPOINT_ORDER_REVERSE_CONSUMPTION := "reverse_consumption"
const RAW_NAVCELL_ORDER_START_TO_GOAL := "start_to_goal"

var status: String = STATUS_INVALID_QUERY
var failure_reason: String = FAILURE_NONE
var canonicalization_reason: String = SimNavReachabilityResult.FAILURE_NONE
var pass_mask: int = 0
var passability_class_name: String = ""
var start_world: Vector2 = Vector2.ZERO
var effective_start_world: Vector2 = Vector2.ZERO
var start_navcell: Vector2i = Vector2i(-1, -1)
var effective_start_navcell: Vector2i = Vector2i(-1, -1)
var canonical_navcell: Vector2i = Vector2i(-1, -1)
var query_goal: SimNavPathGoal = null
var canonical_goal: SimNavPathGoal = null
var canonicalized: bool = false
var start_recovered: bool = false
var reachability_result: SimNavReachabilityResult = null
var excluded_regions: Array[Dictionary] = []
var post_process: String = SimNavLongPathQuery.POST_PROCESS_RAW
var waypoint_spacing: float = 0.0
var waypoint_order: String = WAYPOINT_ORDER_REVERSE_CONSUMPTION
var raw_navcell_order: String = RAW_NAVCELL_ORDER_START_TO_GOAL
var raw_navcell_path: Array[Vector2i] = []
var raw_waypoint_path: SimNavWaypointPath = SimNavWaypointPath.new()
var refined_waypoint_path: SimNavWaypointPath = SimNavWaypointPath.new()
var path: SimNavWaypointPath = refined_waypoint_path
var path_cost: int = 0
var path_length: float = 0.0
var raw_navcell_count: int = 0
var raw_waypoint_count: int = 0
var refined_waypoint_count: int = 0
var search_algorithm: String = ""
var search_expansion_count: int = 0
var search_push_count: int = 0
var search_jump_count: int = 0
var search_closed_count: int = 0
var search_max_open_count: int = 0
var search_path_cell_count: int = 0


func configure_query(query: SimNavLongPathQuery, nav_map: SimNavMap = null) -> void:
	if query == null:
		return
	start_world = query.start_world
	effective_start_world = query.start_world
	pass_mask = query.pass_mask
	passability_class_name = query.passability_class_name
	query_goal = query.goal.clone() if query.goal != null else null
	canonical_goal = query.goal.clone() if query.goal != null else null
	excluded_regions = _clone_excluded_regions(query.excluded_regions)
	post_process = query.post_process
	waypoint_spacing = query.waypoint_spacing
	if nav_map != null:
		start_navcell = nav_map.world_to_navcell(query.start_world)
		effective_start_navcell = start_navcell
		if query.goal != null:
			canonical_navcell = nav_map.world_to_navcell(query.goal.center)


func set_failure(p_status: String, reason: String) -> void:
	status = p_status
	failure_reason = reason
	path = SimNavWaypointPath.new()
	refined_waypoint_path = path
	raw_waypoint_path = SimNavWaypointPath.new()
	raw_navcell_path = []
	raw_navcell_count = 0
	raw_waypoint_count = 0
	refined_waypoint_count = 0
	path_cost = 0
	path_length = 0.0


func set_paths(
	p_status: String,
	p_raw_navcell_path: Array[Vector2i],
	p_raw_waypoint_path: SimNavWaypointPath,
	p_refined_waypoint_path: SimNavWaypointPath,
	p_path_cost: int
) -> void:
	status = p_status
	failure_reason = FAILURE_NONE
	raw_navcell_path = p_raw_navcell_path.duplicate()
	raw_waypoint_path = p_raw_waypoint_path
	refined_waypoint_path = p_refined_waypoint_path
	path = refined_waypoint_path
	path_cost = p_path_cost
	path_length = _measure_path_length(effective_start_world, refined_waypoint_path)
	raw_navcell_count = raw_navcell_path.size()
	raw_waypoint_count = raw_waypoint_path.size()
	refined_waypoint_count = refined_waypoint_path.size()


func apply_search_diagnostics(diagnostics: Dictionary) -> void:
	search_algorithm = str(diagnostics.get("algorithm", search_algorithm))
	search_expansion_count = int(diagnostics.get("expansion_count", search_expansion_count))
	search_push_count = int(diagnostics.get("push_count", search_push_count))
	search_jump_count = int(diagnostics.get("jump_count", search_jump_count))
	search_closed_count = int(diagnostics.get("closed_count", search_closed_count))
	search_max_open_count = int(diagnostics.get("max_open_count", search_max_open_count))
	search_path_cell_count = int(diagnostics.get("path_cell_count", search_path_cell_count))


func search_diagnostics() -> Dictionary:
	return {
		"search_algorithm": search_algorithm,
		"search_expansion_count": search_expansion_count,
		"search_push_count": search_push_count,
		"search_jump_count": search_jump_count,
		"search_closed_count": search_closed_count,
		"search_max_open_count": search_max_open_count,
		"search_path_cell_count": search_path_cell_count,
	}


func is_success() -> bool:
	return status in [
		STATUS_SUCCESS,
		STATUS_CANONICALIZED,
		STATUS_START_RECOVERED,
		STATUS_DIRECT_GOAL,
	]


func has_path() -> bool:
	return path != null and not path.is_empty()


func _measure_path_length(origin: Vector2, waypoint_path: SimNavWaypointPath) -> float:
	if waypoint_path == null or waypoint_path.is_empty():
		return 0.0
	var total := 0.0
	var previous := origin
	for i in range(waypoint_path.waypoints.size() - 1, -1, -1):
		var point := waypoint_path.waypoints[i]
		total += previous.distance_to(point)
		previous = point
	return total


func _clone_excluded_regions(regions: Array[Dictionary]) -> Array[Dictionary]:
	var cloned_regions: Array[Dictionary] = []
	for region in regions:
		var region_dict := region as Dictionary
		cloned_regions.append({
			"center": region_dict.get("center", Vector2.ZERO),
			"radius": maxf(0.0, float(region_dict.get("radius", 0.0))),
		})
	return cloned_regions
