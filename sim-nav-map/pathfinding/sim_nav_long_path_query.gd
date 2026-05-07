class_name SimNavLongPathQuery
extends RefCounted


const POST_PROCESS_RAW := "raw"
const POST_PROCESS_LINE_OF_SIGHT := "line_of_sight"
const POST_PROCESS_MAX_SPACING := "max_spacing"

var start_world: Vector2 = Vector2.ZERO
var goal: SimNavPathGoal = null
var pass_mask: int = 0
var passability_class_name: String = ""
var excluded_regions: Array[Dictionary] = []
var waypoint_spacing: float = 0.0
var post_process: String = POST_PROCESS_RAW


static func from_values(
	p_start_world: Vector2,
	p_goal: SimNavPathGoal,
	p_pass_mask: int,
	p_passability_class_name: String = ""
) -> SimNavLongPathQuery:
	var query := SimNavLongPathQuery.new()
	query.start_world = p_start_world
	query.goal = p_goal.clone() if p_goal != null else null
	query.pass_mask = p_pass_mask
	query.passability_class_name = p_passability_class_name
	return query


func add_excluded_circle(center: Vector2, radius: float) -> void:
	excluded_regions.append({
		"center": center,
		"radius": maxf(0.0, radius),
	})


func clone() -> SimNavLongPathQuery:
	var cloned_query := SimNavLongPathQuery.new()
	cloned_query.start_world = start_world
	cloned_query.goal = goal.clone() if goal != null else null
	cloned_query.pass_mask = pass_mask
	cloned_query.passability_class_name = passability_class_name
	cloned_query.excluded_regions = _clone_excluded_regions()
	cloned_query.waypoint_spacing = waypoint_spacing
	cloned_query.post_process = post_process
	return cloned_query


func _clone_excluded_regions() -> Array[Dictionary]:
	var cloned_regions: Array[Dictionary] = []
	for region in excluded_regions:
		var region_dict := region as Dictionary
		cloned_regions.append({
			"center": region_dict.get("center", Vector2.ZERO),
			"radius": maxf(0.0, float(region_dict.get("radius", 0.0))),
		})
	return cloned_regions
