class_name ZeroAdRtsLabPathfinder
extends RefCounted


const PASSABILITY_CLASS_NAME: String = "ground"
# Wall-clock per-tick budget for sync path request processing.
#
# 0 (default) = no time cap. Only the per-tick request count
# (PATH_REQUEST_BUDGET_PER_TICK in ZeroAdRtsLabWorld) gates how many requests
# get processed each tick.
#
# Set > 0 to also stop processing once that many microseconds have elapsed in
# the current tick. WARNING: a wall-clock cap makes simulation outcome depend
# on OS scheduling — different CPU load, different background processes, or
# different machines can produce divergent unit trajectories from the same
# seed and same setup. See docs/issues/core-019-path-queue-wall-clock-nondeterminism.md.
#
# 0 A.D.'s `m_MaxSameTurnMoves` (CCmpPathfinder_Common.h) is a pure request
# count cap with no wall-clock component, which keeps simulation deterministic.
const DEFAULT_SYNC_PATH_BUDGET_USEC: int = 0

# Raster resolution note: core's CLEARANCE_EXTENSION_RADIUS (+1 raster cell,
# CORE-005) makes static raster bands clearance + cell_size per side (= 26 px
# here). An 8 px cell experiment halved the band but invalidated every
# logged-* replay anchor in the motion smoke (they are all 16 px-era exports);
# re-anchoring belongs to the movement-contract rework, so the resolution
# stays 16 and map fixtures must budget corridors for the wider band instead.
var map_size: Vector2 = Vector2(720.0, 420.0)
var cell_size: float = 16.0
var default_clearance: float = 10.0
var nav_map: SimNavMap = null
var pass_mask: int = 0
var hierarchical: SimNavHierarchicalPathfinder = null
var long_pathfinder: SimNavLongPathfinder = null
var facade: SimNavPathfinderFacade = null
var vertex_pathfinder: SimNavVertexPathfinder = null
var path_queue: SimNavPathRequestQueue = null
var last_report: Dictionary = {}
var dynamic_refreshes: int = 0


func _init(
	p_map_size: Vector2 = Vector2(720.0, 420.0),
	p_cell_size: float = 16.0,
	p_default_clearance: float = 10.0
) -> void:
	map_size = p_map_size
	cell_size = p_cell_size
	default_clearance = p_default_clearance


func rebuild_context(static_obstacles: Array[ZeroAdRtsLabObstacle]) -> void:
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
	dynamic_refreshes = 0


func compute_long_path(unit: ZeroAdRtsLabUnit, goal: Vector2) -> SimNavLongPathResult:
	if facade == null:
		return SimNavLongPathResult.new()
	var query := build_long_path_query(unit, goal)
	var result := facade.compute_path_result(query)
	last_report["long_path"] = _long_result_to_report(result)
	return result


func build_long_path_query(unit: ZeroAdRtsLabUnit, goal: Vector2) -> SimNavLongPathQuery:
	var query := SimNavLongPathQuery.from_values(unit.position, SimNavPathGoal.point(goal), pass_mask, PASSABILITY_CLASS_NAME)
	query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	query.waypoint_spacing = cell_size * 12.0 - 1.0
	return query


func enqueue_long_path(unit: ZeroAdRtsLabUnit, goal: Vector2) -> int:
	if path_queue == null:
		return 0
	var ticket := path_queue.enqueue_long_path_query(build_long_path_query(unit, goal))
	last_report["long_path_queued"] = {
		"ticket": ticket,
		"unit_id": unit.id,
		"goal": goal,
	}
	return ticket


func compute_short_path(
	unit: ZeroAdRtsLabUnit,
	goal: SimNavPathGoal,
	units: Array[ZeroAdRtsLabUnit],
	search_range: float
) -> SimNavShortPathResult:
	_refresh_dynamic_units(units)
	var request := build_short_path_request(unit, goal, search_range)
	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(request)
	last_report["short_path"] = _short_result_to_report(result)
	return result


func build_short_path_request(
	unit: ZeroAdRtsLabUnit,
	goal: SimNavPathGoal,
	search_range: float
) -> SimNavShortPathRequest:
	var request := SimNavShortPathRequest.new()
	request.start = unit.position
	request.goal = goal
	request.clearance = unit.radius
	request.range_px = search_range
	request.pass_mask = pass_mask
	request.avoid_moving_units = false
	request.control_group = unit.control_group_id
	request.obstruction_filter = movement_filter_for_unit(unit)
	# NOTE: with the +1-cell raster extension this outset no longer clears the
	# static raster band (11 + 8 < 10 + 16 + 8); vertices inside the band stay
	# reachable outbound via the impassable-escape rule but edges INTO them can
	# be DDA-rejected. Raising it re-anchors every logged-* motion replay, so
	# the rebalance is deferred to the movement-contract rework.
	request.static_vertex_extra_outset = cell_size * 0.5
	return request


func enqueue_short_path(
	unit: ZeroAdRtsLabUnit,
	goal: SimNavPathGoal,
	units: Array[ZeroAdRtsLabUnit],
	search_range: float
) -> int:
	if path_queue == null:
		return 0
	var ticket := path_queue.enqueue_short_path(build_short_path_request(unit, goal, search_range))
	last_report["short_path_queued"] = {
		"ticket": ticket,
		"unit_id": unit.id,
		"goal": goal.center if goal != null else Vector2.ZERO,
	}
	return ticket


func process_path_budget(
	units: Array[ZeroAdRtsLabUnit],
	max_requests: int,
	max_usec: int = DEFAULT_SYNC_PATH_BUDGET_USEC
) -> int:
	if path_queue == null:
		return 0
	if path_queue.pending_count() <= 0:
		return 0
	_refresh_dynamic_units(units)
	var processed := path_queue.process_budget(max_requests, max_usec)
	if processed > 0:
		last_report["path_queue_processed"] = {
			"processed": processed,
			"diagnostics": path_queue.get_diagnostics(),
		}
	return processed


func cancel_path_request(ticket: int) -> void:
	if path_queue == null or ticket <= 0:
		return
	path_queue.cancel(ticket)


func take_long_path_result(ticket: int) -> SimNavLongPathResult:
	if path_queue == null or ticket <= 0:
		return null
	return path_queue.take_long_path_result(ticket)


func take_short_path_result(ticket: int) -> SimNavShortPathResult:
	if path_queue == null or ticket <= 0:
		return null
	return path_queue.take_short_path_result(ticket)


func path_queue_diagnostics() -> Dictionary:
	if path_queue == null:
		return {}
	return path_queue.get_diagnostics()


func validate_movement_line(
	unit: ZeroAdRtsLabUnit,
	start: Vector2,
	target: Vector2,
	units: Array[ZeroAdRtsLabUnit],
	refresh_dynamic: bool = true
) -> SimNavMovementLineResult:
	if refresh_dynamic:
		_refresh_dynamic_units(units)
	var result := facade.validate_movement_line(start, target, unit.radius, pass_mask, movement_filter_for_unit(unit))
	last_report["movement_line"] = _line_result_to_report(result)
	return result


func validate_unit_line(
	unit: ZeroAdRtsLabUnit,
	start: Vector2,
	target: Vector2,
	units: Array[ZeroAdRtsLabUnit],
	refresh_dynamic: bool = true
) -> SimNavMovementLineResult:
	if refresh_dynamic:
		_refresh_dynamic_units(units)
	var result := facade.validate_unit_line(start, target, unit.radius, movement_filter_for_unit(unit))
	last_report["unit_line"] = _line_result_to_report(result)
	return result


func movement_filter_for_unit(unit: ZeroAdRtsLabUnit) -> SimNavObstructionFilter:
	var filter := SimNavObstructionFilter.for_short_path(false, unit.control_group_id)
	filter.ignored_entity_id = unit.id
	return filter


func point_inside_static(point: Vector2, clearance: float) -> bool:
	if nav_map == null:
		return false
	for shape in nav_map.get_static_obstruction_shapes():
		if shape.contains_point_with_clearance(point, clearance):
			return true
	return false


func refresh_dynamic_units(units: Array[ZeroAdRtsLabUnit]) -> void:
	if nav_map == null:
		return
	var shapes: Array[SimNavObstructionShapeUnit] = []
	for unit in units:
		if not unit.blocks_pathfinding:
			continue
		var shape := SimNavObstructionShapeUnit.new()
		shape.entity_id = unit.id
		shape.center = unit.position
		shape.clearance = unit.radius
		shape.control_group = unit.control_group_id
		shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
		if unit.has_move_order:
			shape.flags |= SimNavObstructionFlags.MOVING
			shape.moving = true
		shapes.append(shape)
	nav_map.replace_dynamic_obstructions(shapes)
	dynamic_refreshes += 1


func _refresh_dynamic_units(units: Array[ZeroAdRtsLabUnit]) -> void:
	refresh_dynamic_units(units)


func _static_shape_for_obstacle(obstacle: ZeroAdRtsLabObstacle) -> SimNavObstructionShapeStatic:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = obstacle.id
	shape.center = obstacle.center
	shape.width = obstacle.size.x
	shape.height = obstacle.size.y
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


func _long_result_to_report(result: SimNavLongPathResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"path_size": result.path.size(),
		"canonicalized": result.canonicalized,
		"canonical_goal": result.canonical_goal.center if result.canonical_goal != null else Vector2.ZERO,
	}


func _short_result_to_report(result: SimNavShortPathResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"path_size": result.path.size(),
		"path_length": result.path_length,
		"graph": result.graph_diagnostics(),
	}


func _line_result_to_report(result: SimNavMovementLineResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"blocked_obstruction_entity_id": result.blocked_obstruction_entity_id,
		"blocked_navcell": result.blocked_navcell,
	}
