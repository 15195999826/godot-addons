class_name Dota2LabPathfinderWrapper
extends RefCounted


const PASSABILITY_CLASS_NAME := "ground"


# 8 px raster cells: after core gained CLEARANCE_EXTENSION_RADIUS (+1 raster
# cell, CORE-005), 16 px cells inflated static bands to clearance+16 = 28 px
# per side and sealed the 56 px narrow-gap fixtures outright. 8 px keeps the
# band at clearance+8 = 20 px per side and halves center quantization.
var map_size: Vector2 = Vector2(720.0, 420.0)
var cell_size: float = 8.0
var default_clearance: float = 12.0
var nav_map: SimNavMap = null
var pass_mask: int = 0
var hierarchical: SimNavHierarchicalPathfinder = null
var long_pathfinder: SimNavLongPathfinder = null
var facade: SimNavPathfinderFacade = null
var vertex_pathfinder: SimNavVertexPathfinder = null
var path_queue: SimNavPathRequestQueue = null


func _init(
	p_map_size: Vector2 = Vector2(720.0, 420.0),
	p_cell_size: float = 8.0,
	p_default_clearance: float = 12.0
) -> void:
	map_size = p_map_size
	cell_size = p_cell_size
	default_clearance = p_default_clearance


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


func refresh_dynamic_units(units: Array[Dota2LabUnit]) -> void:
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
		shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
		if unit.state == Dota2LabUnit.STATE_FOLLOWING:
			shape.flags |= SimNavObstructionFlags.MOVING
			shape.moving = true
		shapes.append(shape)
	nav_map.replace_dynamic_obstructions(shapes)


func enqueue_long_path(unit: Dota2LabUnit, goal: Vector2) -> int:
	if path_queue == null:
		return 0
	return path_queue.enqueue_long_path_query(_build_long_path_query(unit, goal))


func enqueue_short_path(
	unit: Dota2LabUnit,
	goal: SimNavPathGoal,
	search_range: float
) -> int:
	if path_queue == null:
		return 0
	return path_queue.enqueue_short_path(_build_short_path_request(unit, goal, search_range))


func take_long_path_result(ticket: int) -> SimNavLongPathResult:
	if path_queue == null or ticket <= 0:
		return null
	return path_queue.take_long_path_result(ticket)


func take_short_path_result(ticket: int) -> SimNavShortPathResult:
	if path_queue == null or ticket <= 0:
		return null
	return path_queue.take_short_path_result(ticket)


func cancel(ticket: int) -> void:
	if path_queue == null or ticket <= 0:
		return
	path_queue.cancel(ticket)


# Process queue. Refreshes dynamic obstructions first so short-path requests
# see the current unit positions.
func process_budget(units: Array[Dota2LabUnit], max_requests: int) -> int:
	if path_queue == null:
		return 0
	if path_queue.pending_count() <= 0:
		return 0
	refresh_dynamic_units(units)
	return path_queue.process_budget(max_requests)


func validate_movement_line(
	unit: Dota2LabUnit,
	start: Vector2,
	target: Vector2,
	units: Array[Dota2LabUnit],
	refresh_dynamic: bool = true,
	clearance_override: float = -1.0
) -> SimNavMovementLineResult:
	# clearance_override < 0 uses the unit's full radius. The motion layer
	# passes radius minus the ½-cell unit-relax (movement-feel-policy M2) when
	# re-validating a unit-blocked step; the raster DDA inside stays governed
	# by pass_mask, so statics keep their full conservative band.
	if refresh_dynamic:
		refresh_dynamic_units(units)
	var clearance := unit.radius if clearance_override < 0.0 else clearance_override
	return facade.validate_movement_line(start, target, clearance, pass_mask, _movement_filter_for_unit(unit))


# Slide-step static validation (movement-feel-policy M1): playable bounds
# plus EXACT static geometry, deliberately skipping the static raster DDA.
# The raster band is a long-path conservativeness tool; inside a narrow gap
# it steals geometrically legal side-step room (band leaves 16 px where
# geometry allows 34 px), which would make opposing units unable to brush
# past. This mirrors 0 A.D., where movement checks statics geometrically and
# only terrain via the grid. A slide may therefore end inside the raster
# band; the core impassable-escape rule (CORE-020 fix) walks it back out.
# Unit-vs-unit slide checks live in the motion controller against LIVE unit
# positions — the nav map's dynamic shapes are refreshed once per tick and
# would let two units slide into the same spot.
func validate_slide_statics(
	unit: Dota2LabUnit,
	start: Vector2,
	target: Vector2
) -> bool:
	if not _point_inside_playable_bounds(target, unit.radius):
		return false
	return SimNavLineOfSight.segment_clear(
		start, target, nav_map.get_static_obstruction_shapes(), unit.radius
	)


func diagnostics() -> Dictionary:
	if path_queue == null:
		return {}
	return path_queue.get_diagnostics().duplicate(true)


func _build_long_path_query(unit: Dota2LabUnit, goal: Vector2) -> SimNavLongPathQuery:
	var query := SimNavLongPathQuery.from_values(
		unit.position,
		SimNavPathGoal.point(goal),
		pass_mask,
		PASSABILITY_CLASS_NAME
	)
	query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	query.waypoint_spacing = cell_size * 12.0 - 1.0
	return query


func _build_short_path_request(
	unit: Dota2LabUnit,
	goal: SimNavPathGoal,
	search_range: float
) -> SimNavShortPathRequest:
	var request := SimNavShortPathRequest.new()
	request.start = unit.position
	request.goal = goal
	request.clearance = unit.radius
	request.range_px = search_range
	request.pass_mask = pass_mask
	request.avoid_moving_units = true
	request.obstruction_filter = _movement_filter_for_unit(unit)
	# Keep static outset vertices outside the raster band: unit radius (11) +
	# outset must exceed class clearance (12) + raster extension (+1 cell) +
	# half-cell center quantization, or A* edges INTO those vertices are
	# rejected by the passable->impassable DDA rule.
	request.static_vertex_extra_outset = cell_size * 2.0
	return request


# Dota2 paradigm: hard block all units including allies. No control_group
# carveouts. Only ignore the requesting unit itself so it doesn't block its
# own queries.
func _movement_filter_for_unit(unit: Dota2LabUnit) -> SimNavObstructionFilter:
	var filter := SimNavObstructionFilter.all()
	filter.ignored_entity_id = unit.id
	return filter


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
