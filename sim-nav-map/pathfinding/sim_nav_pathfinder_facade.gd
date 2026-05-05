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


func compute_path_immediate(start_world: Vector2, goal: SimNavPathGoal, pass_mask: int) -> SimNavWaypointPath:
	if _nav_map == null or _long == null or goal == null:
		return SimNavWaypointPath.new()
	if goal.type == SimNavPathGoal.Type.POINT and _hierarchical != null and _hierarchical.is_recomputed():
		var start_cell := _nav_map.world_to_navcell(start_world)
		var goal_cell := _nav_map.world_to_navcell(goal.center)
		var reachable_goal_cell := _hierarchical.make_goal_reachable_navcell(start_cell, goal_cell, pass_mask)
		goal.type = SimNavPathGoal.Type.POINT
		goal.center = _nav_map.navcell_center_world(reachable_goal_cell)
	return _long.compute_path_immediate(start_world, goal, pass_mask)
