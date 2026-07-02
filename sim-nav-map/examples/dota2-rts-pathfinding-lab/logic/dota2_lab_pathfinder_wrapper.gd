class_name Dota2LabPathfinderWrapper
extends RefCounted

# Fable-version navigation wrapper: STATIC WORLD ONLY.
#
# Units never enter the nav map. Long paths plan around terrain bounds and
# static obstacles; unit-vs-unit interaction is entirely the motion engine's
# separation solve. That removes the whole class of same-tick-staleness bugs
# the old dynamic-obstruction refresh had.
#
# Planning is synchronous — unit counts in this lab (and in dota2-auto-battle)
# are far below anything that needs the budgeted request queue.

const PASSABILITY_CLASS_NAME := "ground"


# 8 px raster cells: after core gained CLEARANCE_EXTENSION_RADIUS (+1 raster
# cell), 16 px cells inflated static bands to clearance+16 = 28 px per side and
# sealed 56 px narrow-gap fixtures outright. 8 px keeps the band at
# clearance+8 = 20 px per side and halves center quantization.
var map_size: Vector2 = Vector2(1320.0, 900.0)
var cell_size: float = 8.0
var default_clearance: float = 12.0
var nav_map: SimNavMap = null
var pass_mask: int = 0
var hierarchical: SimNavHierarchicalPathfinder = null
var long_pathfinder: SimNavLongPathfinder = null
var facade: SimNavPathfinderFacade = null
var plan_count: int = 0
var line_check_count: int = 0

var _line_filter: SimNavObstructionFilter = null


func _init(
	p_map_size: Vector2 = Vector2(1320.0, 900.0),
	p_cell_size: float = 8.0,
	p_default_clearance: float = 12.0
) -> void:
	map_size = p_map_size
	cell_size = p_cell_size
	default_clearance = p_default_clearance
	_line_filter = SimNavObstructionFilter.all()
	_line_filter.include_units = false


func rebuild_context(static_obstacles: Array[Dota2LabObstacle]) -> void:
	var width := int(ceil(map_size.x / cell_size))
	var height := int(ceil(map_size.y / cell_size))
	nav_map = SimNavMap.new(width, height, cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = PASSABILITY_CLASS_NAME
	ground.clearance = default_clearance
	ground.affects_pathfinding = true
	pass_mask = nav_map.register_passability_class(ground)
	_mark_out_of_playable_navcells(default_clearance)
	for obstacle in static_obstacles:
		nav_map.add_static_obstruction(_static_shape_for_obstacle(obstacle))
	nav_map.rebuild_dirty()
	hierarchical = SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [pass_mask])
	nav_map.clear_dirty_navcells()
	long_pathfinder = SimNavLongPathfinder.new(nav_map)
	facade = SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)


# Synchronous long-path plan with reachable-goal canonicalization. An
# unreachable goal comes back as a path to the nearest reachable point
# (result.canonicalized == true) — callers never need a retry loop for
# statically bad goals.
func plan_path(start: Vector2, goal: Vector2) -> SimNavLongPathResult:
	plan_count += 1
	var query := SimNavLongPathQuery.from_values(
		start,
		SimNavPathGoal.point(goal),
		pass_mask,
		PASSABILITY_CLASS_NAME
	)
	query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	query.waypoint_spacing = cell_size * 12.0 - 1.0
	return facade.compute_path_result(query)


# Raster LOS against statics only, at class clearance. Used for waypoint
# shortcutting: conservative (band-inflated) on purpose so a shortcut can
# never commit the unit to a line the planner would have refused.
func is_line_walkable(start: Vector2, target: Vector2) -> bool:
	line_check_count += 1
	return facade.validate_movement_line(
		start, target, default_clearance, pass_mask, _line_filter
	).is_success()


# Exact static geometry for the separation solve's project-out step.
func static_shapes() -> Array[SimNavObstructionShapeStatic]:
	if nav_map == null:
		return []
	return nav_map.get_static_obstruction_shapes()


func clamp_to_playable(point: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(point.x, radius, map_size.x - radius),
		clampf(point.y, radius, map_size.y - radius)
	)


func diagnostics() -> Dictionary:
	return {
		"plan_count": plan_count,
		"line_check_count": line_check_count,
	}


func _static_shape_for_obstacle(obstacle: Dota2LabObstacle) -> SimNavObstructionShapeStatic:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = obstacle.id
	shape.center = obstacle.center
	shape.width = obstacle.size.x
	shape.height = obstacle.size.y
	shape.rotation_rad = obstacle.rotation_rad
	shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	return shape


func _mark_out_of_playable_navcells(clearance: float) -> void:
	for y in range(nav_map.height):
		for x in range(nav_map.width):
			var coord := Vector2i(x, y)
			var point := nav_map.navcell_center_world(coord)
			if _point_inside_playable_bounds(point, clearance):
				continue
			nav_map.or_navcell_data(coord, pass_mask)


func _point_inside_playable_bounds(point: Vector2, clearance: float) -> bool:
	return (
		point.x >= clearance
		and point.y >= clearance
		and point.x <= map_size.x - clearance
		and point.y <= map_size.y - clearance
	)
