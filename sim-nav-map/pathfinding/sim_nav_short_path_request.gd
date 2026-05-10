class_name SimNavShortPathRequest
extends RefCounted


var start: Vector2 = Vector2.ZERO
var goal: SimNavPathGoal = null
var clearance: float = 0.0
var range_px: float = 256.0
var pass_mask: int = 0
var avoid_moving_units: bool = true
var control_group: String = ""
var obstruction_filter: SimNavObstructionFilter = null
var static_vertex_extra_outset: float = 0.0


func get_obstruction_filter() -> SimNavObstructionFilter:
	if obstruction_filter != null:
		return obstruction_filter
	return SimNavObstructionFilter.for_short_path(avoid_moving_units, control_group)


func clone() -> SimNavShortPathRequest:
	var cloned_request := SimNavShortPathRequest.new()
	cloned_request.start = start
	cloned_request.goal = goal.clone() if goal != null else null
	cloned_request.clearance = clearance
	cloned_request.range_px = range_px
	cloned_request.pass_mask = pass_mask
	cloned_request.avoid_moving_units = avoid_moving_units
	cloned_request.control_group = control_group
	cloned_request.obstruction_filter = obstruction_filter.clone() if obstruction_filter != null else null
	cloned_request.static_vertex_extra_outset = static_vertex_extra_outset
	return cloned_request
