class_name RtsPathfindingLabPathfinder
extends RefCounted


const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

var map_size: Vector2 = Vector2(720.0, 420.0)
var cell_size: float = 16.0
var unit_radius: float = 11.0
var last_report: Dictionary = {}
var _cached_static_signature: String = ""
var _cached_nav_map: SimNavMap = null
var _cached_pass_mask: int = 0
var _cached_hierarchical: SimNavHierarchicalPathfinder = null
var _last_context_cache_hit: bool = false
var static_context_cache_hits: int = 0
var static_context_cache_misses: int = 0


func _init(p_map_size: Vector2 = Vector2(720.0, 420.0), p_cell_size: float = 16.0, p_unit_radius: float = 11.0) -> void:
	map_size = p_map_size
	cell_size = p_cell_size
	unit_radius = p_unit_radius


func prewarm_static_context(static_obstacles: Array[RtsPathfindingLabObstacle]) -> void:
	_get_static_nav_context(static_obstacles)


func build_terrain_nav_context(
	terrain_tiles: Dictionary,
	passability_configs: Array[SimNavPassabilityClassConfig],
	p_navcells_per_tile: int = 2
) -> Dictionary:
	var width := int(ceil(map_size.x / cell_size))
	var height := int(ceil(map_size.y / cell_size))
	var nav_map := SimNavMap.new(width, height, cell_size, Vector2.ZERO, p_navcells_per_tile)
	var pass_masks: Dictionary = {}
	var recompute_masks: Array[int] = []
	for config in passability_configs:
		var mask := nav_map.register_passability_class(config)
		pass_masks[config.class_name_id] = mask
		if mask != 0:
			recompute_masks.append(mask)
	for tile_key in terrain_tiles.keys():
		var tile: Vector2i = tile_key
		nav_map.set_terrain_tile_data(tile, int(terrain_tiles[tile_key]))
	for config in passability_configs:
		var boundary_mask := int(pass_masks.get(config.class_name_id, 0))
		if boundary_mask != 0:
			_mark_out_of_playable_navcells(nav_map, boundary_mask, config.clearance)
	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, recompute_masks)
	return {
		"nav_map": nav_map,
		"pass_masks": pass_masks,
		"hierarchical": hierarchical,
	}


func plan_path_with_terrain_context(
	start: Vector2,
	goal: Vector2,
	terrain_context: Dictionary,
	passability_class_name: String
) -> Array[Vector2]:
	var nav_map := terrain_context.get("nav_map", null) as SimNavMap
	var hierarchical := terrain_context.get("hierarchical", null) as SimNavHierarchicalPathfinder
	var pass_masks: Dictionary = terrain_context.get("pass_masks", {})
	var pass_mask := int(pass_masks.get(passability_class_name, 0))
	if nav_map == null or pass_mask == 0:
		return []
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	var reachability := facade.query_reachability(start, SimNavPathGoal.point(goal), pass_mask, passability_class_name)
	var path_goal := reachability.canonical_goal if reachability.has_canonical_goal() else SimNavPathGoal.point(goal)
	var path := _waypoint_path_to_forward_array(facade.compute_path_immediate(start, path_goal, pass_mask))
	last_report = {
		"used_terrain_context": true,
		"passability_class_name": passability_class_name,
		"reachability_failure_reason": reachability.failure_reason,
		"reachability_pass_mask": reachability.pass_mask,
		"reachability_canonicalized": reachability.canonicalized,
		"reachable_goal": path_goal.center,
		"path_size": path.size(),
	}
	return path


func plan_path(
	start: Vector2,
	goal: Vector2,
	static_obstacles: Array[RtsPathfindingLabObstacle],
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> Array[Vector2]:
	var active_obstacles := _build_active_obstacles(static_obstacles, units, moving_group_id, avoid_moving_units, group_filter_enabled)
	var nav_context := _get_static_nav_context(static_obstacles)
	var nav_map: SimNavMap = nav_context["nav_map"]
	var pass_mask := int(nav_context["pass_mask"])
	var hierarchical: SimNavHierarchicalPathfinder = nav_context["hierarchical"]
	nav_map.replace_dynamic_obstructions(_build_dynamic_obstruction_shapes(
		units,
		moving_group_id,
		avoid_moving_units,
		group_filter_enabled
	))

	var reachable_goal := goal
	var used_make_goal_reachable := false
	var goal_passable := is_point_passable(goal, active_obstacles, unit_radius)
	var reachability := _query_reachability_with_nav(nav_map, hierarchical, start, SimNavPathGoal.point(goal), pass_mask, "ground")
	if reachability.has_canonical_goal() and (reachability.canonicalized or not goal_passable):
		reachable_goal = reachability.canonical_goal.center
		used_make_goal_reachable = reachability.canonicalized or not goal_passable

	var short_request := SimNavShortPathRequest.new()
	short_request.start = start
	short_request.goal = SimNavPathGoal.point(reachable_goal)
	short_request.clearance = unit_radius
	short_request.range_px = map_size.length()
	short_request.pass_mask = pass_mask
	short_request.avoid_moving_units = avoid_moving_units
	short_request.control_group = moving_group_id if group_filter_enabled else ""
	var vertex_pathfinder := SimNavVertexPathfinder.new(nav_map)
	var sim_vertex_path := vertex_pathfinder.compute_short_path_immediate(short_request)
	var vertex_path := _waypoint_path_to_forward_array(sim_vertex_path)
	if not vertex_path.is_empty() and _path_respects_lab_bounds(start, vertex_path, active_obstacles, unit_radius):
		last_report = {
			"used_vertex": true,
			"used_grid_fallback": false,
			"used_make_goal_reachable": used_make_goal_reachable,
			"reachable_goal": reachable_goal,
			"path_size": vertex_path.size(),
			"static_context_cache_hit": _last_context_cache_hit,
			"reachability_failure_reason": reachability.failure_reason,
			"reachability_pass_mask": reachability.pass_mask,
			"reachability_canonicalized": reachability.canonicalized,
		}
		return vertex_path

	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	var long_path := _waypoint_path_to_forward_array(facade.compute_path_immediate(start, SimNavPathGoal.point(reachable_goal), pass_mask))
	var smoothed := _string_pull(start, long_path, active_obstacles, unit_radius)
	if not _path_respects_lab_bounds(start, smoothed, active_obstacles, unit_radius):
		smoothed = []
	last_report = {
		"used_vertex": false,
		"used_grid_fallback": true,
		"used_make_goal_reachable": used_make_goal_reachable,
		"reachable_goal": reachable_goal,
		"path_size": smoothed.size(),
		"static_context_cache_hit": _last_context_cache_hit,
		"reachability_failure_reason": reachability.failure_reason,
		"reachability_pass_mask": reachability.pass_mask,
		"reachability_canonicalized": reachability.canonicalized,
	}
	return smoothed


func is_point_passable(point: Vector2, obstacles: Array[RtsPathfindingLabObstacle], clearance: float) -> bool:
	if point.x < 0.0 or point.y < 0.0 or point.x > map_size.x or point.y > map_size.y:
		return false
	for shape in _obstacles_to_static_shapes(obstacles):
		if shape.contains_point_with_clearance(point, clearance):
			return false
	return true


func segment_clear(a: Vector2, b: Vector2, obstacles: Array[RtsPathfindingLabObstacle], clearance: float) -> bool:
	if not _point_inside_playable_bounds(a, clearance):
		return false
	if not _point_inside_playable_bounds(b, clearance):
		return false
	return SimNavLineOfSight.segment_clear(a, b, _obstacles_to_static_shapes(obstacles), clearance)


func build_obstacles_for_analysis(
	static_obstacles: Array[RtsPathfindingLabObstacle],
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> Array[RtsPathfindingLabObstacle]:
	return _build_active_obstacles(static_obstacles, units, moving_group_id, avoid_moving_units, group_filter_enabled)


func _build_active_obstacles(
	static_obstacles: Array[RtsPathfindingLabObstacle],
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> Array[RtsPathfindingLabObstacle]:
	var result: Array[RtsPathfindingLabObstacle] = []
	for obstacle in static_obstacles:
		result.append(obstacle)
	if not avoid_moving_units:
		return result

	var sorted_units := units.duplicate()
	sorted_units.sort_custom(func(a: RtsPathfindingLabUnit, b: RtsPathfindingLabUnit) -> bool:
		return a.id < b.id
	)
	for unit in sorted_units:
		if not unit.blocks_pathfinding:
			continue
		if group_filter_enabled and unit.group_id == moving_group_id:
			continue
		var size := Vector2(unit.radius * 2.0, unit.radius * 2.0)
		result.append(LabObstacle.new("unit:%s" % unit.id, unit.position, size))
	return result


func _build_dynamic_obstruction_shapes(
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> Array[SimNavObstructionShapeUnit]:
	var result: Array[SimNavObstructionShapeUnit] = []
	if not avoid_moving_units:
		return result

	var sorted_units := units.duplicate()
	sorted_units.sort_custom(func(a: RtsPathfindingLabUnit, b: RtsPathfindingLabUnit) -> bool:
		return a.id < b.id
	)
	for unit in sorted_units:
		if not unit.blocks_pathfinding:
			continue
		if group_filter_enabled and unit.group_id == moving_group_id:
			continue
		var shape := SimNavObstructionShapeUnit.new()
		shape.entity_id = unit.id
		shape.center = unit.position
		shape.clearance = unit.radius
		shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
		if unit.mobile:
			shape.flags |= SimNavObstructionFlags.MOVING
			shape.moving = true
		shape.control_group = unit.group_id
		result.append(shape)
	return result


func _get_static_nav_context(static_obstacles: Array[RtsPathfindingLabObstacle]) -> Dictionary:
	var signature := _static_obstacles_signature(static_obstacles)
	_last_context_cache_hit = (
		_cached_nav_map != null
		and _cached_hierarchical != null
		and _cached_static_signature == signature
	)
	if not _last_context_cache_hit:
		static_context_cache_misses += 1
		var nav_context := _build_nav_context(static_obstacles)
		_cached_static_signature = signature
		_cached_nav_map = nav_context["nav_map"] as SimNavMap
		_cached_pass_mask = int(nav_context["pass_mask"])
		_cached_hierarchical = SimNavHierarchicalPathfinder.new()
		_cached_hierarchical.recompute(_cached_nav_map, [_cached_pass_mask])
	else:
		static_context_cache_hits += 1
	return {
		"nav_map": _cached_nav_map,
		"pass_mask": _cached_pass_mask,
		"hierarchical": _cached_hierarchical,
	}


func _static_obstacles_signature(static_obstacles: Array[RtsPathfindingLabObstacle]) -> String:
	var parts: Array[String] = []
	var sorted_obstacles := static_obstacles.duplicate()
	sorted_obstacles.sort_custom(func(a: RtsPathfindingLabObstacle, b: RtsPathfindingLabObstacle) -> bool:
		return a.id < b.id
	)
	for obstacle in sorted_obstacles:
		parts.append("%s:%d:%d:%d:%d" % [
			obstacle.id,
			int(roundf(obstacle.center.x * 10.0)),
			int(roundf(obstacle.center.y * 10.0)),
			int(roundf(obstacle.size.x * 10.0)),
			int(roundf(obstacle.size.y * 10.0)),
		])
	return "|".join(parts)


func _build_nav_context(obstacles: Array[RtsPathfindingLabObstacle]) -> Dictionary:
	var width := int(ceil(map_size.x / cell_size))
	var height := int(ceil(map_size.y / cell_size))
	var nav_map := SimNavMap.new(width, height, cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = unit_radius
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)
	_mark_out_of_playable_navcells(nav_map, pass_mask, unit_radius)
	for shape in _obstacles_to_static_shapes(obstacles):
		nav_map.add_static_obstruction(shape)
	nav_map.rebuild_dirty()
	return {
		"nav_map": nav_map,
		"pass_mask": pass_mask,
	}


func _obstacles_to_static_shapes(obstacles: Array[RtsPathfindingLabObstacle]) -> Array[SimNavObstructionShapeStatic]:
	var shapes: Array[SimNavObstructionShapeStatic] = []
	for obstacle in obstacles:
		shapes.append(_lab_obstacle_to_static_shape(obstacle))
	return shapes


func _lab_obstacle_to_static_shape(obstacle: RtsPathfindingLabObstacle) -> SimNavObstructionShapeStatic:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = obstacle.id
	shape.center = obstacle.center
	shape.width = obstacle.size.x
	shape.height = obstacle.size.y
	shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	return shape


func _mark_out_of_playable_navcells(nav_map: SimNavMap, pass_mask: int, clearance: float) -> void:
	var safe_clearance := maxf(clearance, 0.0)
	for y in range(nav_map.height):
		for x in range(nav_map.width):
			var coord := Vector2i(x, y)
			var center := nav_map.navcell_center_world(coord)
			if _point_inside_playable_bounds(center, safe_clearance):
				continue
			nav_map.or_navcell_data(coord, pass_mask)


func _query_reachability_with_nav(
	nav_map: SimNavMap,
	hierarchical: SimNavHierarchicalPathfinder,
	start: Vector2,
	goal: SimNavPathGoal,
	pass_mask: int,
	passability_class_name: String
) -> SimNavReachabilityResult:
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, null)
	return facade.query_reachability(start, goal, pass_mask, passability_class_name)


func _waypoint_path_to_forward_array(path: SimNavWaypointPath) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if path == null:
		return result
	for i in range(path.waypoints.size() - 1, -1, -1):
		result.append(path.waypoints[i])
	return result


func _string_pull(
	start: Vector2,
	raw_path: Array[Vector2],
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> Array[Vector2]:
	if raw_path.is_empty():
		return []
	var result: Array[Vector2] = []
	var anchor := start
	var idx := 0
	while idx < raw_path.size():
		var chosen := idx
		for j in range(raw_path.size() - 1, idx - 1, -1):
			if segment_clear(anchor, raw_path[j], obstacles, clearance):
				chosen = j
				break
		result.append(raw_path[chosen])
		anchor = raw_path[chosen]
		idx = chosen + 1
	return result


func _path_respects_lab_bounds(
	start: Vector2,
	path: Array[Vector2],
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> bool:
	if path.is_empty():
		return true
	var prev := start
	for point in path:
		if not segment_clear(prev, point, obstacles, clearance):
			return false
		prev = point
	return true


func _point_inside_playable_bounds(point: Vector2, clearance: float) -> bool:
	var safe_clearance := maxf(clearance, 0.0)
	return (
		point.x >= safe_clearance
		and point.y >= safe_clearance
		and point.x <= map_size.x - safe_clearance
		and point.y <= map_size.y - safe_clearance
	)
