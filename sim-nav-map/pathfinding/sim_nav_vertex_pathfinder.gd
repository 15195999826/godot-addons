class_name SimNavVertexPathfinder
extends RefCounted


const COORD_INT_SCALE: int = 10
const CORNER_OUTSET_FACTOR: float = 2.0
const _MAX_PATH_LENGTH: float = 1.0e20

var _nav_map: SimNavMap = null


func _init(nav_map: SimNavMap = null) -> void:
	_nav_map = nav_map


func compute_short_path_immediate(req: SimNavShortPathRequest) -> SimNavWaypointPath:
	if _nav_map == null or req == null or req.goal == null:
		return SimNavWaypointPath.new()
	if req.goal.contains_point(req.start):
		var same := SimNavWaypointPath.new()
		same.push_back(req.start)
		return same

	var obstacles := _collect_obstacles(req)
	var virtual_goals := _goal_candidates(req)
	var best_path := SimNavWaypointPath.new()
	var best_length := _MAX_PATH_LENGTH
	for virtual_goal in virtual_goals:
		var candidate_path := _compute_to_virtual_goal(req.start, virtual_goal, obstacles, req.clearance)
		if candidate_path.is_empty():
			continue
		var candidate_length := _path_length(req.start, candidate_path)
		if candidate_length < best_length:
			best_length = candidate_length
			best_path = candidate_path
	return best_path


func compute_short_path_result(req: SimNavShortPathRequest) -> SimNavShortPathResult:
	var result := SimNavShortPathResult.new()
	result.configure_query(req)
	if _nav_map == null or req == null or req.goal == null:
		var reason := SimNavShortPathResult.FAILURE_NAV_MAP_MISSING if _nav_map == null else SimNavShortPathResult.FAILURE_GOAL_MISSING
		result.set_failure(SimNavShortPathResult.STATUS_INVALID_QUERY, reason)
		return result
	if req.goal.contains_point(req.start):
		var same := SimNavWaypointPath.new()
		same.push_back(req.start)
		result.set_path(SimNavShortPathResult.STATUS_SAME_GOAL, same)
		return result

	var obstacles := _collect_obstacles(req)
	result.obstruction_count = obstacles.size()
	var virtual_goals := _goal_candidates(req)
	result.candidate_count = virtual_goals.size()
	var best_path := SimNavWaypointPath.new()
	var best_length := _MAX_PATH_LENGTH
	var had_candidate_in_range := false
	for virtual_goal in virtual_goals:
		if not _goal_candidate_in_range(req, virtual_goal):
			continue
		had_candidate_in_range = true
		var candidate_path := _compute_to_virtual_goal(req.start, virtual_goal, obstacles, req.clearance)
		if candidate_path.is_empty():
			continue
		var candidate_length := _path_length(req.start, candidate_path)
		if candidate_length < best_length:
			best_length = candidate_length
			best_path = candidate_path
	if best_path.is_empty():
		if not had_candidate_in_range:
			result.set_failure(SimNavShortPathResult.STATUS_OUT_OF_RANGE, SimNavShortPathResult.FAILURE_RANGE_EXCEEDED)
		else:
			result.set_failure(SimNavShortPathResult.STATUS_NO_PATH, SimNavShortPathResult.FAILURE_NO_ROUTE)
		return result
	var status := SimNavShortPathResult.STATUS_SUCCESS
	if best_path.size() == 1:
		status = SimNavShortPathResult.STATUS_DIRECT_GOAL
	result.set_path(status, best_path)
	return result


func _compute_to_virtual_goal(
	start: Vector2,
	virtual_goal: Vector2,
	obstacles: Array,
	clearance: float
) -> SimNavWaypointPath:
	if start.distance_squared_to(virtual_goal) < 1.0:
		var same := SimNavWaypointPath.new()
		same.push_back(virtual_goal)
		return same
	if SimNavLineOfSight.segment_clear(start, virtual_goal, obstacles, clearance):
		var direct := SimNavWaypointPath.new()
		direct.push_back(virtual_goal)
		return direct

	var vertices: Array[Vector2] = [start, virtual_goal]
	var statics: Array[SimNavObstructionShapeStatic] = []
	var units: Array[SimNavObstructionShapeUnit] = []
	for shape in obstacles:
		if shape is SimNavObstructionShapeStatic:
			statics.append(shape as SimNavObstructionShapeStatic)
		elif shape is SimNavObstructionShapeUnit:
			units.append(shape as SimNavObstructionShapeUnit)

	for static_shape in statics:
		var outset := clearance * CORNER_OUTSET_FACTOR
		for corner in static_shape.get_corners():
			var direction := (corner - static_shape.center).normalized()
			vertices.append(corner + direction * outset)

	for unit_shape in units:
		var radius := unit_shape.clearance + clearance
		vertices.append(unit_shape.center + Vector2(radius, radius))
		vertices.append(unit_shape.center + Vector2(radius, -radius))
		vertices.append(unit_shape.center + Vector2(-radius, -radius))
		vertices.append(unit_shape.center + Vector2(-radius, radius))

	return _astar_visibility(vertices, obstacles, clearance)


func _goal_candidates(req: SimNavShortPathRequest) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	_append_unique_candidate(candidates, req.goal.nearest_point_on_goal(req.start))
	match req.goal.type:
		SimNavPathGoal.Type.CIRCLE, SimNavPathGoal.Type.INVERTED_CIRCLE:
			var radius := req.goal.hw
			_append_unique_candidate(candidates, req.goal.center + Vector2(radius, 0.0))
			_append_unique_candidate(candidates, req.goal.center + Vector2(0.0, radius))
			_append_unique_candidate(candidates, req.goal.center + Vector2(-radius, 0.0))
			_append_unique_candidate(candidates, req.goal.center + Vector2(0.0, -radius))
		SimNavPathGoal.Type.SQUARE, SimNavPathGoal.Type.INVERTED_SQUARE:
			_append_unique_candidate(candidates, req.goal.center + req.goal.u * req.goal.hw)
			_append_unique_candidate(candidates, req.goal.center - req.goal.u * req.goal.hw)
			_append_unique_candidate(candidates, req.goal.center + req.goal.v * req.goal.hh)
			_append_unique_candidate(candidates, req.goal.center - req.goal.v * req.goal.hh)
			_append_unique_candidate(candidates, req.goal.center + req.goal.u * req.goal.hw + req.goal.v * req.goal.hh)
			_append_unique_candidate(candidates, req.goal.center + req.goal.u * req.goal.hw - req.goal.v * req.goal.hh)
			_append_unique_candidate(candidates, req.goal.center - req.goal.u * req.goal.hw + req.goal.v * req.goal.hh)
			_append_unique_candidate(candidates, req.goal.center - req.goal.u * req.goal.hw - req.goal.v * req.goal.hh)
	return candidates


func _append_unique_candidate(candidates: Array[Vector2], point: Vector2) -> void:
	for existing in candidates:
		if existing.distance_squared_to(point) < 0.01:
			return
	candidates.append(point)


func _goal_candidate_in_range(req: SimNavShortPathRequest, point: Vector2) -> bool:
	if req.range_px <= 0.0:
		return true
	return req.start.distance_to(point) <= req.range_px + req.clearance + 0.001


func _collect_obstacles(req: SimNavShortPathRequest) -> Array:
	var result: Array = []
	var filter := req.obstruction_filter
	for static_shape in _nav_map.get_static_obstruction_shapes():
		if (static_shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		if filter != null and not filter.matches(static_shape):
			continue
		if filter == null and _is_same_control_group(static_shape, req.control_group):
			continue
		result.append(static_shape)
	_append_blocked_navcell_obstacles(result, req, filter)
	for unit_shape in _nav_map.get_dynamic_obstruction_shapes():
		if (unit_shape.flags & SimNavObstructionFlags.BLOCK_MOVEMENT) == 0:
			continue
		if filter != null and not filter.matches(unit_shape):
			continue
		if filter == null and _is_same_control_group(unit_shape, req.control_group):
			continue
		if filter == null and not req.avoid_moving_units and ((unit_shape.flags & SimNavObstructionFlags.MOVING) != 0 or unit_shape.moving):
			continue
		result.append(unit_shape)
	return result


func _append_blocked_navcell_obstacles(
	result: Array,
	req: SimNavShortPathRequest,
	filter: SimNavObstructionFilter
) -> void:
	if req.pass_mask == 0:
		return
	var virtual_goal := req.goal.nearest_point_on_goal(req.start)
	var scan_padding := maxf(req.clearance + _nav_map.navcell_size * 2.0, _nav_map.navcell_size)
	var min_world := Vector2(
		minf(req.start.x, virtual_goal.x) - scan_padding,
		minf(req.start.y, virtual_goal.y) - scan_padding
	)
	var max_world := Vector2(
		maxf(req.start.x, virtual_goal.x) + scan_padding,
		maxf(req.start.y, virtual_goal.y) + scan_padding
	)
	var min_cell := _nav_map.world_to_navcell(min_world)
	var max_cell := _nav_map.world_to_navcell(max_world)
	var start_x := maxi(0, mini(min_cell.x, max_cell.x))
	var end_x := mini(_nav_map.width - 1, maxi(min_cell.x, max_cell.x))
	var start_y := maxi(0, mini(min_cell.y, max_cell.y))
	var end_y := mini(_nav_map.height - 1, maxi(min_cell.y, max_cell.y))
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var coord := Vector2i(x, y)
			if _nav_map.is_passable_navcell(coord, req.pass_mask):
				continue
			if _static_shape_covers_navcell(coord, req.clearance, filter):
				continue
			result.append(_blocked_navcell_shape(coord))


func _blocked_navcell_shape(coord: Vector2i) -> SimNavObstructionShapeStatic:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = "terrain_%d_%d" % [coord.x, coord.y]
	shape.center = _nav_map.navcell_center_world(coord)
	shape.width = _nav_map.navcell_size
	shape.height = _nav_map.navcell_size
	shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	return shape


func _static_shape_covers_navcell(coord: Vector2i, clearance: float, filter: SimNavObstructionFilter) -> bool:
	var center_world := _nav_map.navcell_center_world(coord)
	for shape in _nav_map.get_static_obstruction_shapes():
		if (shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		if filter != null and not filter.matches(shape):
			continue
		if shape.contains_point_with_clearance(center_world, clearance):
			return true
	return false


func _is_same_control_group(shape: SimNavObstructionShape, control_group: String) -> bool:
	if control_group == "":
		return false
	if shape.control_group == control_group:
		return true
	return shape.control_group_2 == control_group


func _astar_visibility(vertices: Array[Vector2], obstacles: Array, clearance: float) -> SimNavWaypointPath:
	var open_keys: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var insertion_seq := 0

	var goal_idx := 1
	g_score[0] = 0.0
	var h0 := vertices[0].distance_to(vertices[goal_idx])
	open_keys.append([h0, h0, _coord_int(vertices[0].x), _coord_int(vertices[0].y), insertion_seq, 0])
	insertion_seq += 1

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var current_idx := int(key[5])
		if closed.has(current_idx):
			continue
		closed[current_idx] = true
		if current_idx == goal_idx:
			return _reconstruct(vertices, came_from, current_idx)

		var current_pos := vertices[current_idx]
		var current_g: float = float(g_score[current_idx])
		for next_idx in range(vertices.size()):
			if next_idx == current_idx or closed.has(next_idx):
				continue
			var next_pos := vertices[next_idx]
			if not SimNavLineOfSight.segment_clear(current_pos, next_pos, obstacles, clearance):
				continue
			var next_g := current_g + current_pos.distance_to(next_pos)
			if g_score.has(next_idx) and next_g >= float(g_score[next_idx]):
				continue
			g_score[next_idx] = next_g
			came_from[next_idx] = current_idx
			var next_h := next_pos.distance_to(vertices[goal_idx])
			var f := next_g + next_h
			SimNavPathfinderHeap.insert(open_keys, [f, next_h, _coord_int(next_pos.x), _coord_int(next_pos.y), insertion_seq, next_idx])
			insertion_seq += 1
	return SimNavWaypointPath.new()


func _reconstruct(vertices: Array[Vector2], came_from: Dictionary, goal_idx: int) -> SimNavWaypointPath:
	var path := SimNavWaypointPath.new()
	var trail: Array[int] = [goal_idx]
	var current := goal_idx
	while current != 0:
		if not came_from.has(current):
			return SimNavWaypointPath.new()
		current = int(came_from[current])
		trail.append(current)
	for i in range(trail.size() - 1):
		path.push_back(vertices[trail[i]])
	return path


func _coord_int(value: float) -> int:
	return int(round(value * COORD_INT_SCALE))


func _path_length(start: Vector2, path: SimNavWaypointPath) -> float:
	var length := 0.0
	var prev := start
	for i in range(path.waypoints.size() - 1, -1, -1):
		var point := path.waypoints[i]
		length += prev.distance_to(point)
		prev = point
	return length
