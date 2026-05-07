class_name SimNavShortPathResult
extends RefCounted


const STATUS_SUCCESS := "success"
const STATUS_DIRECT_GOAL := "direct_goal"
const STATUS_SAME_GOAL := "same_goal"
const STATUS_OUT_OF_RANGE := "out_of_range"
const STATUS_NO_PATH := "no_path"
const STATUS_INVALID_QUERY := "invalid_query"

const FAILURE_NONE := "none"
const FAILURE_NAV_MAP_MISSING := "nav_map_missing"
const FAILURE_GOAL_MISSING := "goal_missing"
const FAILURE_RANGE_EXCEEDED := "range_exceeded"
const FAILURE_NO_ROUTE := "no_route"

var status: String = STATUS_INVALID_QUERY
var failure_reason: String = FAILURE_NONE
var start: Vector2 = Vector2.ZERO
var goal: SimNavPathGoal = null
var clearance: float = 0.0
var range_px: float = 0.0
var pass_mask: int = 0
var obstruction_filter: SimNavObstructionFilter = null
var path: SimNavWaypointPath = SimNavWaypointPath.new()
var path_length: float = 0.0
var candidate_count: int = 0
var obstruction_count: int = 0


func configure_query(request: SimNavShortPathRequest) -> void:
	if request == null:
		return
	start = request.start
	goal = request.goal.clone() if request.goal != null else null
	clearance = request.clearance
	range_px = request.range_px
	pass_mask = request.pass_mask
	obstruction_filter = request.get_obstruction_filter().clone()


func set_failure(p_status: String, reason: String) -> void:
	status = p_status
	failure_reason = reason
	path = SimNavWaypointPath.new()
	path_length = 0.0


func set_path(p_status: String, p_path: SimNavWaypointPath) -> void:
	status = p_status
	failure_reason = FAILURE_NONE
	path = p_path if p_path != null else SimNavWaypointPath.new()
	path_length = _measure_path_length(start, path)


func is_success() -> bool:
	return status in [STATUS_SUCCESS, STATUS_DIRECT_GOAL, STATUS_SAME_GOAL]


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
