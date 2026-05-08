class_name SimNavVertexPathfinder
extends RefCounted


const COORD_INT_SCALE: int = 10
# Small outward delta on visibility-graph corners so segments tangent to the
# inflated obstacle aren't classified as crossing it under FP rounding. Mirrors
# 0 A.D. VertexPathfinder.cpp EDGE_EXPAND_DELTA (1/16 in fixed-point); 0.5 px
# is its float-math equivalent at the lab's clearance scale.
const EDGE_EXPAND_DELTA: float = 0.5
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
		var candidate_path := _compute_to_virtual_goal(req, virtual_goal, obstacles)
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
		var candidate_path := _compute_to_virtual_goal(req, virtual_goal, obstacles)
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
	req: SimNavShortPathRequest,
	virtual_goal: Vector2,
	obstacles: Array
) -> SimNavWaypointPath:
	var start := req.start
	if start.distance_squared_to(virtual_goal) < 1.0:
		var same := SimNavWaypointPath.new()
		same.push_back(virtual_goal)
		return same
	if _segment_clear_for_request(req, start, virtual_goal, obstacles):
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
		# Expand OBB corners along the obstacle's own axes (u, v), not corner-to-center
		# radials, so clearance is uniform regardless of aspect ratio.
		var axes := static_shape.get_axes()
		var su := axes[0]
		var sv := axes[1]
		var ehw := static_shape.width * 0.5 + req.clearance + EDGE_EXPAND_DELTA
		var ehh := static_shape.height * 0.5 + req.clearance + EDGE_EXPAND_DELTA
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				vertices.append(static_shape.center + sx * ehw * su + sy * ehh * sv)

	for unit_shape in units:
		var radius := unit_shape.clearance + req.clearance + EDGE_EXPAND_DELTA
		vertices.append(unit_shape.center + Vector2(radius, radius))
		vertices.append(unit_shape.center + Vector2(radius, -radius))
		vertices.append(unit_shape.center + Vector2(-radius, -radius))
		vertices.append(unit_shape.center + Vector2(-radius, radius))

	return _astar_visibility(vertices, obstacles, req)


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


func _astar_visibility(
	vertices: Array[Vector2],
	obstacles: Array,
	req: SimNavShortPathRequest
) -> SimNavWaypointPath:
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
			if not _segment_clear_for_request(req, current_pos, next_pos, obstacles):
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


func _segment_clear_for_request(
	req: SimNavShortPathRequest,
	a: Vector2,
	b: Vector2,
	obstacles: Array
) -> bool:
	if not SimNavLineOfSight.segment_clear(a, b, obstacles, req.clearance):
		return false
	if req.pass_mask == 0:
		return true
	return _segment_passable_clear(a, b, req.pass_mask)


func _segment_passable_clear(a: Vector2, b: Vector2, pass_mask: int) -> bool:
	var origin := _nav_map.origin
	var cell_size := _nav_map.navcell_size
	var i0 := int(floor((a.x - origin.x) / cell_size))
	var j0 := int(floor((a.y - origin.y) / cell_size))
	var i1 := int(floor((b.x - origin.x) / cell_size))
	var j1 := int(floor((b.y - origin.y) / cell_size))
	if not _nav_map.is_passable_navcell(Vector2i(i0, j0), pass_mask):
		return false
	if i0 == i1 and j0 == j1:
		return true
	var dx := b.x - a.x
	var dy := b.y - a.y
	var step_i := 0
	var step_j := 0
	var t_max_x := INF
	var t_max_y := INF
	var delta_t_x := INF
	var delta_t_y := INF
	if dx > 0.0:
		step_i = 1
		t_max_x = (origin.x + float(i0 + 1) * cell_size - a.x) / dx
		delta_t_x = cell_size / dx
	elif dx < 0.0:
		step_i = -1
		t_max_x = (origin.x + float(i0) * cell_size - a.x) / dx
		delta_t_x = -cell_size / dx
	if dy > 0.0:
		step_j = 1
		t_max_y = (origin.y + float(j0 + 1) * cell_size - a.y) / dy
		delta_t_y = cell_size / dy
	elif dy < 0.0:
		step_j = -1
		t_max_y = (origin.y + float(j0) * cell_size - a.y) / dy
		delta_t_y = -cell_size / dy
	var i := i0
	var j := j0
	var max_steps := absi(i1 - i0) + absi(j1 - j0) + 4
	while (i != i1 or j != j1) and max_steps > 0:
		max_steps -= 1
		if t_max_x < t_max_y:
			i += step_i
			t_max_x += delta_t_x
		else:
			j += step_j
			t_max_y += delta_t_y
		if not _nav_map.is_passable_navcell(Vector2i(i, j), pass_mask):
			return false
	return true


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
