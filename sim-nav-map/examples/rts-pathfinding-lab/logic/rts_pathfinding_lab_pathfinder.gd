class_name RtsPathfindingLabPathfinder
extends RefCounted


const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

const LONG_VERTEX_DISTANCE_LIMIT: float = 224.0
const LONG_VERTEX_DYNAMIC_LIMIT: int = 3
const LONG_VERTEX_STATIC_LIMIT: int = 4
const LONG_VERTEX_EDGE_STATIC_LIMIT: int = 3
const LONG_VERTEX_EDGE_MARGIN: float = 64.0
const EDGE_VERTEX_DISTANCE_LIMIT: float = 64.0
const CROWDED_VERTEX_ACTIVE_LIMIT: int = 5
const DENSE_DYNAMIC_VERTEX_LIMIT: int = 6

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
	var query := SimNavLongPathQuery.from_values(start, SimNavPathGoal.point(goal), pass_mask, passability_class_name)
	var path_result := facade.compute_path_result(query)
	var path := _waypoint_path_to_forward_array(path_result.path)
	var reachable_goal := path_result.canonical_goal.center if path_result.canonical_goal != null else goal
	last_report = {
		"used_terrain_context": true,
		"passability_class_name": passability_class_name,
		"reachability_failure_reason": path_result.canonicalization_reason,
		"reachability_pass_mask": path_result.pass_mask,
		"reachability_canonicalized": path_result.canonicalized,
		"reachable_goal": reachable_goal,
		"path_size": path.size(),
		"long_path_result": _long_path_result_to_report(path_result),
	}
	return path


func plan_path(
	start: Vector2,
	goal: Vector2,
	static_obstacles: Array[RtsPathfindingLabObstacle],
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool,
	prefer_grid_for_canonical_target: bool = false
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
	var reachability_start_usec := Time.get_ticks_usec()
	var reachability := _query_reachability_with_nav(nav_map, hierarchical, start, SimNavPathGoal.point(goal), pass_mask, "ground")
	var reachability_usec := Time.get_ticks_usec() - reachability_start_usec
	if reachability.has_canonical_goal() and (reachability.canonicalized or not goal_passable):
		reachable_goal = reachability.canonical_goal.center
		used_make_goal_reachable = reachability.canonicalized or not goal_passable

	var short_request := _make_short_path_request(start, reachable_goal, pass_mask, moving_group_id, avoid_moving_units, group_filter_enabled)
	var distance_to_reachable_goal := start.distance_to(reachable_goal)
	var active_obstacle_count := active_obstacles.size()
	var dynamic_obstacle_count := maxi(active_obstacle_count - static_obstacles.size(), 0)
	var skipped_vertex_reason := ""
	var try_vertex := true
	if prefer_grid_for_canonical_target and distance_to_reachable_goal > LONG_VERTEX_DISTANCE_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "canonical_target_grid_preferred"
	elif (
		active_obstacle_count >= CROWDED_VERTEX_ACTIVE_LIMIT
		and distance_to_reachable_goal > LONG_VERTEX_DISTANCE_LIMIT
		and (_is_edge_goal(start) or _is_edge_goal(reachable_goal))
	):
		try_vertex = false
		skipped_vertex_reason = "crowded_edge_long_query"
	elif reachability.canonicalized and dynamic_obstacle_count >= LONG_VERTEX_DYNAMIC_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "canonical_goal_crowded_query"
	elif reachability.canonicalized and distance_to_reachable_goal > LONG_VERTEX_DISTANCE_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "canonical_goal_outside_vertex_range"
	elif _is_edge_goal(reachable_goal) and dynamic_obstacle_count >= LONG_VERTEX_DYNAMIC_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "crowded_dynamic_edge_query"
	elif dynamic_obstacle_count >= DENSE_DYNAMIC_VERTEX_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "dense_dynamic_query"
	elif _is_edge_goal(reachable_goal) and static_obstacles.size() >= LONG_VERTEX_EDGE_STATIC_LIMIT and distance_to_reachable_goal > EDGE_VERTEX_DISTANCE_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "edge_static_long_query"
	elif static_obstacles.size() >= LONG_VERTEX_STATIC_LIMIT and distance_to_reachable_goal > LONG_VERTEX_DISTANCE_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "edited_static_long_query"
	elif _is_edge_goal(reachable_goal) and dynamic_obstacle_count >= LONG_VERTEX_DYNAMIC_LIMIT and distance_to_reachable_goal > EDGE_VERTEX_DISTANCE_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "crowded_edge_query"
	elif dynamic_obstacle_count >= LONG_VERTEX_DYNAMIC_LIMIT and distance_to_reachable_goal > LONG_VERTEX_DISTANCE_LIMIT:
		try_vertex = false
		skipped_vertex_reason = "crowded_long_query"

	var vertex_usec := 0
	var vertex_path: Array[Vector2] = []
	if try_vertex:
		var vertex_start_usec := Time.get_ticks_usec()
		var vertex_pathfinder := SimNavVertexPathfinder.new(nav_map)
		var sim_vertex_path := vertex_pathfinder.compute_short_path_immediate(short_request)
		vertex_usec = Time.get_ticks_usec() - vertex_start_usec
		vertex_path = _waypoint_path_to_forward_array(sim_vertex_path)
	if try_vertex and not vertex_path.is_empty() and _path_respects_lab_bounds(start, vertex_path, active_obstacles, unit_radius):
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
			"reachability_usec": reachability_usec,
			"vertex_usec": vertex_usec,
			"grid_usec": 0,
			"skipped_vertex_reason": skipped_vertex_reason,
			"distance_to_reachable_goal": distance_to_reachable_goal,
			"active_obstacle_count": active_obstacle_count,
			"dynamic_obstacle_count": dynamic_obstacle_count,
		}
		return vertex_path

	var grid_start_usec := Time.get_ticks_usec()
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	var long_query := SimNavLongPathQuery.from_values(start, SimNavPathGoal.point(reachable_goal), pass_mask, "ground")
	long_query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	var long_result := facade.compute_path_result(long_query)
	var long_path := _waypoint_path_to_forward_array(long_result.path)
	var smoothed := _string_pull(start, long_path, static_obstacles, unit_radius)
	if not _path_respects_lab_bounds(start, smoothed, static_obstacles, unit_radius):
		# Smoothing produced a segment the lab bounds check refuses (e.g.
		# _string_pull keeps chosen=idx without re-verifying segment_clear, or
		# a smoothed shortcut grazes an inflated static under FP). Fall back
		# to the unsmoothed core long path: compute_path_result has already
		# validated it via navcell-center passability. The lab's continuous
		# segment_clear can still flag the long path because it is strictly
		# stricter than navcell-center passability, but returning the long
		# path is much better than handing the unit an empty path — empty
		# paths leave it frozen with has_move_order=true and no replan
		# trigger (LAB-006). The runtime push-out / collision pass corrects
		# any incidental clipping along the navcell-center route.
		if not long_path.is_empty():
			smoothed = long_path
		else:
			smoothed = []
	var grid_usec := Time.get_ticks_usec() - grid_start_usec
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
		"reachability_usec": reachability_usec,
		"vertex_usec": vertex_usec,
		"grid_usec": grid_usec,
		"skipped_vertex_reason": skipped_vertex_reason,
		"distance_to_reachable_goal": distance_to_reachable_goal,
		"active_obstacle_count": active_obstacle_count,
		"dynamic_obstacle_count": dynamic_obstacle_count,
		"long_path_result": _long_path_result_to_report(long_result),
		"core_refined_path_size": long_path.size(),
		"lab_smoothed_path_size": smoothed.size(),
	}
	return smoothed


func inspect_core_primitives(
	start: Vector2,
	goal: Vector2,
	static_obstacles: Array[RtsPathfindingLabObstacle],
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> Dictionary:
	plan_path(start, goal, static_obstacles, units, moving_group_id, avoid_moving_units, group_filter_enabled)
	var report := last_report.duplicate(true)
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
	var reachable_goal: Vector2 = report.get("reachable_goal", goal) as Vector2
	var short_request := _make_short_path_request(start, reachable_goal, pass_mask, moving_group_id, avoid_moving_units, group_filter_enabled)
	var short_filter := short_request.get_obstruction_filter()
	var short_result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(short_request)
	var primitive_facade := SimNavPathfinderFacade.new(nav_map, hierarchical, null)
	report["short_path_result"] = _short_path_result_to_report(short_result)
	report["movement_line_validation"] = _line_result_to_report(
		primitive_facade.validate_movement_line(start, reachable_goal, unit_radius, pass_mask, short_filter)
	)
	report["unit_line_validation"] = _line_result_to_report(
		primitive_facade.validate_unit_line(start, reachable_goal, unit_radius, short_filter)
	)
	return report


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


func _is_edge_goal(goal: Vector2) -> bool:
	return (
		goal.x <= LONG_VERTEX_EDGE_MARGIN
		or goal.y <= LONG_VERTEX_EDGE_MARGIN
		or goal.x >= map_size.x - LONG_VERTEX_EDGE_MARGIN
		or goal.y >= map_size.y - LONG_VERTEX_EDGE_MARGIN
	)


func build_obstacles_for_analysis(
	static_obstacles: Array[RtsPathfindingLabObstacle],
	units: Array[RtsPathfindingLabUnit],
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> Array[RtsPathfindingLabObstacle]:
	return _build_active_obstacles(static_obstacles, units, moving_group_id, avoid_moving_units, group_filter_enabled)


func _make_short_path_request(
	start: Vector2,
	reachable_goal: Vector2,
	pass_mask: int,
	moving_group_id: String,
	avoid_moving_units: bool,
	group_filter_enabled: bool
) -> SimNavShortPathRequest:
	var short_request := SimNavShortPathRequest.new()
	short_request.start = start
	short_request.goal = SimNavPathGoal.point(reachable_goal)
	short_request.clearance = unit_radius
	short_request.range_px = map_size.length()
	short_request.pass_mask = pass_mask
	short_request.avoid_moving_units = avoid_moving_units
	short_request.control_group = moving_group_id if group_filter_enabled else ""
	return short_request


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


func _long_path_result_to_report(result: SimNavLongPathResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"canonicalization_reason": result.canonicalization_reason,
		"canonicalized": result.canonicalized,
		"start_recovered": result.start_recovered,
		"pass_mask": result.pass_mask,
		"passability_class_name": result.passability_class_name,
		"start_navcell": result.start_navcell,
		"effective_start_navcell": result.effective_start_navcell,
		"canonical_navcell": result.canonical_navcell,
		"canonical_goal": result.canonical_goal.center if result.canonical_goal != null else Vector2.ZERO,
		"path_cost": result.path_cost,
		"path_length": result.path_length,
		"raw_navcell_count": result.raw_navcell_count,
		"raw_waypoint_count": result.raw_waypoint_count,
		"refined_waypoint_count": result.refined_waypoint_count,
		"waypoint_order": result.waypoint_order,
		"raw_navcell_order": result.raw_navcell_order,
		"post_process": result.post_process,
		"waypoint_spacing": result.waypoint_spacing,
		"excluded_region_count": result.excluded_regions.size(),
	}


func _short_path_result_to_report(result: SimNavShortPathResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"path_size": result.path.size(),
		"path_length": result.path_length,
		"candidate_count": result.candidate_count,
		"obstruction_count": result.obstruction_count,
		"range_px": result.range_px,
		"pass_mask": result.pass_mask,
	}


func _line_result_to_report(result: SimNavMovementLineResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"unit_only": result.unit_only,
		"checked_navcell_count": result.checked_navcell_count,
		"checked_obstruction_count": result.checked_obstruction_count,
		"blocked_navcell": result.blocked_navcell,
		"blocked_obstruction_tag": result.blocked_obstruction_tag,
		"blocked_obstruction_entity_id": result.blocked_obstruction_entity_id,
		"blocked_obstruction_type": result.blocked_obstruction_type,
	}


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
