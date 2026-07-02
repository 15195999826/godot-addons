class_name Dota2LabPathfinderWrapper
extends RefCounted

# Fable-version navigation wrapper: STATIC WORLD ONLY.
#
# Units never enter the nav map. Long paths plan around terrain bounds and
# static obstacles; unit-vs-unit interaction is entirely the motion engine's
# separation solve. That removes the whole class of same-tick-staleness bugs
# the old dynamic-obstruction refresh had.
#
# Planning is deferred and time-sliced: a GDScript JPS query costs 4-40 ms
# (measured), so an 8-unit cross-map group command computed synchronously
# used to freeze the input frame for ~250 ms. Commands enqueue instead; the
# engine drains ONE request per tick through the core queue while units walk
# a straight-line placeholder for those few ticks. Peak per-frame planning
# cost is one query (~4-10 ms warm) instead of the whole batch.
# (A worker-thread variant was tried and reverted: GDScript execution on
# spawned threads crashed unpredictably on Godot 4.6 rc1 — see the
# fable-motion design note.)

const PASSABILITY_CLASS_NAME := "ground"
const PLAN_BUDGET_PER_TICK := 1


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
var vertex_pathfinder: SimNavVertexPathfinder = null
var path_queue: SimNavPathRequestQueue = null
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
	if path_queue != null:
		path_queue.clear()
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
	vertex_pathfinder = SimNavVertexPathfinder.new(nav_map)
	path_queue = SimNavPathRequestQueue.new(facade, vertex_pathfinder)


# ── Async plan API (normal engine path) ──────────────────────────────────────

# Enqueue a long-path request for the worker thread. Reachable-goal
# canonicalization applies as in plan_path.
func request_plan(start: Vector2, goal: Vector2) -> int:
	if path_queue == null:
		return 0
	plan_count += 1
	return path_queue.enqueue_long_path_query(_build_long_path_query(start, goal))


func cancel_plan(ticket: int) -> void:
	if path_queue == null or ticket <= 0:
		return
	path_queue.cancel(ticket)


# Once per tick: compute at most PLAN_BUDGET_PER_TICK pending requests on
# the main thread (time-slicing, not threading).
func pump_async() -> void:
	if path_queue == null:
		return
	if path_queue.pending_count() > 0:
		path_queue.process_budget(PLAN_BUDGET_PER_TICK)


func take_plan_result(ticket: int) -> SimNavLongPathResult:
	if path_queue == null or ticket <= 0:
		return null
	return path_queue.take_long_path_result(ticket)


func pending_plan_count() -> int:
	if path_queue == null:
		return 0
	return path_queue.pending_count()


# ── Synchronous plan (tools/probes only) ─────────────────────────────────────

# Same query as request_plan, computed immediately.
func plan_path(start: Vector2, goal: Vector2) -> SimNavLongPathResult:
	plan_count += 1
	return facade.compute_path_result(_build_long_path_query(start, goal))


func _build_long_path_query(start: Vector2, goal: Vector2) -> SimNavLongPathQuery:
	var query := SimNavLongPathQuery.from_values(
		start,
		SimNavPathGoal.point(goal),
		pass_mask,
		PASSABILITY_CLASS_NAME
	)
	query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	query.waypoint_spacing = cell_size * 12.0 - 1.0
	return query


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
		"plans_pending": pending_plan_count(),
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
