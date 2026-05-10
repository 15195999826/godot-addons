class_name SimNavVertexPathfinder
extends RefCounted


const COORD_INT_SCALE: int = 10
# Small outward delta on visibility-graph corners so segments tangent to the
# inflated obstacle aren't classified as crossing it under FP rounding. Mirrors
# 0 A.D. VertexPathfinder.cpp EDGE_EXPAND_DELTA (1/16 in fixed-point); 0.5 px
# is its float-math equivalent at the lab's clearance scale.
const EDGE_EXPAND_DELTA: float = 0.5
const _MAX_PATH_LENGTH: float = 1.0e20
const _MAX_VISIBILITY_NEIGHBORS: int = 8

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

	var diagnostics := _new_graph_diagnostics()
	var visibility_inputs := _collect_visibility_inputs(req, diagnostics, false)
	var best_path := _compute_to_goal(req, visibility_inputs, diagnostics)
	if best_path.is_empty():
		var terrain_diagnostics := _new_graph_diagnostics()
		visibility_inputs = _collect_visibility_inputs(req, terrain_diagnostics, true)
		if _terrain_fallback_added_vertices(terrain_diagnostics):
			diagnostics = terrain_diagnostics
			best_path = _compute_to_goal(req, visibility_inputs, diagnostics)
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

	result.candidate_count = 1
	if not _goal_in_search_range(req):
		result.set_failure(SimNavShortPathResult.STATUS_OUT_OF_RANGE, SimNavShortPathResult.FAILURE_RANGE_EXCEEDED)
		return result

	var diagnostics := _new_graph_diagnostics()
	var visibility_inputs := _collect_visibility_inputs(req, diagnostics, false)
	var best_path := _compute_to_goal(req, visibility_inputs, diagnostics)
	if best_path.is_empty():
		var terrain_diagnostics := _new_graph_diagnostics()
		visibility_inputs = _collect_visibility_inputs(req, terrain_diagnostics, true)
		if _terrain_fallback_added_vertices(terrain_diagnostics):
			diagnostics = terrain_diagnostics
			best_path = _compute_to_goal(req, visibility_inputs, diagnostics)
	if best_path.is_empty():
		result.set_failure(SimNavShortPathResult.STATUS_NO_PATH, SimNavShortPathResult.FAILURE_NO_ROUTE)
		_apply_graph_diagnostics(result, diagnostics)
		return result
	var status := SimNavShortPathResult.STATUS_SUCCESS
	if best_path.size() == 1:
		status = SimNavShortPathResult.STATUS_DIRECT_GOAL
	result.set_path(status, best_path)
	_apply_graph_diagnostics(result, diagnostics)
	return result


func _compute_to_goal(
	req: SimNavShortPathRequest,
	visibility_inputs: Dictionary,
	diagnostics: Dictionary
) -> SimNavWaypointPath:
	var start := req.start
	var obstacles: Array = visibility_inputs.get("obstacles", [])
	var initial_goal := _goal_point_for_vertex(req, start)
	if start.distance_squared_to(initial_goal) < 1.0:
		var same := SimNavWaypointPath.new()
		same.push_back(initial_goal)
		return same
	diagnostics["vertex_count"] = maxi(int(diagnostics.get("vertex_count", 0)), 2)
	if _segment_clear_for_request(req, start, initial_goal, obstacles, diagnostics):
		var direct := SimNavWaypointPath.new()
		direct.push_back(initial_goal)
		return direct

	var vertices: Array[Vector2] = [start, initial_goal]
	var obstacle_vertices: Array = visibility_inputs.get("vertices", [])
	for vertex in obstacle_vertices:
		if _vertex_covered_by_obstacles(vertex as Vector2, obstacles, req):
			continue
		vertices.append(vertex as Vector2)
	diagnostics["vertex_count"] = maxi(int(diagnostics.get("vertex_count", 0)), vertices.size())

	return _astar_visibility(vertices, obstacles, req, diagnostics)


func _goal_in_search_range(req: SimNavShortPathRequest) -> bool:
	if req.range_px <= 0.0:
		return true
	return req.goal.distance_to_point(req.start) <= req.range_px + req.clearance + 0.001


func _goal_point_for_vertex(req: SimNavShortPathRequest, from: Vector2) -> Vector2:
	var goal_point := req.goal.nearest_point_on_goal(from)
	if req.range_px <= 0.0:
		return goal_point
	var to_goal := goal_point - req.start
	var goal_dist := to_goal.length()
	if goal_dist <= req.range_px or goal_dist <= 0.001:
		return goal_point
	return req.start + to_goal / goal_dist * req.range_px


func _terrain_fallback_added_vertices(diagnostics: Dictionary) -> bool:
	return int(diagnostics.get("terrain_vertex_count", 0)) > 0


func _new_graph_diagnostics() -> Dictionary:
	return {
		"obstruction_count": 0,
		"explicit_static_obstruction_count": 0,
		"explicit_unit_obstruction_count": 0,
		"terrain_edge_count": 0,
		"terrain_vertex_count": 0,
		"vertex_count": 0,
		"visibility_check_count": 0,
		"astar_expansion_count": 0,
	}


func _apply_graph_diagnostics(result: SimNavShortPathResult, diagnostics: Dictionary) -> void:
	result.obstruction_count = int(diagnostics.get("obstruction_count", 0))
	result.explicit_static_obstruction_count = int(diagnostics.get("explicit_static_obstruction_count", 0))
	result.explicit_unit_obstruction_count = int(diagnostics.get("explicit_unit_obstruction_count", 0))
	result.terrain_edge_count = int(diagnostics.get("terrain_edge_count", 0))
	result.terrain_vertex_count = int(diagnostics.get("terrain_vertex_count", 0))
	result.vertex_count = int(diagnostics.get("vertex_count", 0))
	result.visibility_check_count = int(diagnostics.get("visibility_check_count", 0))
	result.astar_expansion_count = int(diagnostics.get("astar_expansion_count", 0))


func _collect_visibility_inputs(req: SimNavShortPathRequest, diagnostics: Dictionary, include_terrain: bool) -> Dictionary:
	diagnostics["obstruction_count"] = 0
	diagnostics["explicit_static_obstruction_count"] = 0
	diagnostics["explicit_unit_obstruction_count"] = 0
	diagnostics["terrain_edge_count"] = 0
	diagnostics["terrain_vertex_count"] = 0
	var obstacles: Array = []
	var vertices: Array[Vector2] = []
	var seen_vertices: Dictionary = {}
	var filter := req.get_obstruction_filter()
	var query_range := _obstruction_query_range(req)
	var static_shapes := _nav_map.get_static_obstruction_shapes()
	if query_range > 0.0:
		static_shapes = _nav_map.get_static_obstruction_shapes_in_range(req.start, query_range)
	for static_shape in static_shapes:
		if (static_shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		if filter != null and not filter.matches(static_shape):
			continue
		obstacles.append(static_shape)
		diagnostics["explicit_static_obstruction_count"] = int(diagnostics.get("explicit_static_obstruction_count", 0)) + 1
		_append_static_obstacle_vertices(vertices, seen_vertices, req, static_shape)
	if include_terrain:
		_append_terrain_edge_vertices(vertices, seen_vertices, req, filter, diagnostics)
	var unit_shapes := _nav_map.get_dynamic_obstruction_shapes()
	if query_range > 0.0:
		unit_shapes = _nav_map.get_dynamic_obstruction_shapes_in_range(req.start, query_range)
	for unit_shape in unit_shapes:
		if (unit_shape.flags & SimNavObstructionFlags.BLOCK_MOVEMENT) == 0:
			continue
		if filter != null and not filter.matches(unit_shape):
			continue
		obstacles.append(unit_shape)
		diagnostics["explicit_unit_obstruction_count"] = int(diagnostics.get("explicit_unit_obstruction_count", 0)) + 1
		_append_unit_obstacle_vertices(vertices, seen_vertices, req, unit_shape)
	diagnostics["obstruction_count"] = obstacles.size()
	diagnostics["terrain_vertex_count"] = int(diagnostics.get("terrain_vertex_count", 0))
	return {
		"obstacles": obstacles,
		"vertices": vertices,
	}


func _append_static_obstacle_vertices(
	vertices: Array[Vector2],
	seen_vertices: Dictionary,
	req: SimNavShortPathRequest,
	static_shape: SimNavObstructionShapeStatic
) -> void:
	var axes := static_shape.get_axes()
	var su := axes[0]
	var sv := axes[1]
	var ehw := static_shape.width * 0.5 + req.clearance + req.static_vertex_extra_outset + EDGE_EXPAND_DELTA
	var ehh := static_shape.height * 0.5 + req.clearance + req.static_vertex_extra_outset + EDGE_EXPAND_DELTA
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_append_unique_vertex(vertices, seen_vertices, static_shape.center + sx * ehw * su + sy * ehh * sv)


func _append_unit_obstacle_vertices(
	vertices: Array[Vector2],
	seen_vertices: Dictionary,
	req: SimNavShortPathRequest,
	unit_shape: SimNavObstructionShapeUnit
) -> void:
	var radius := unit_shape.clearance + req.clearance + EDGE_EXPAND_DELTA
	_append_unique_vertex(vertices, seen_vertices, unit_shape.center + Vector2(radius, radius))
	_append_unique_vertex(vertices, seen_vertices, unit_shape.center + Vector2(radius, -radius))
	_append_unique_vertex(vertices, seen_vertices, unit_shape.center + Vector2(-radius, -radius))
	_append_unique_vertex(vertices, seen_vertices, unit_shape.center + Vector2(-radius, radius))


func _append_terrain_edge_vertices(
	vertices: Array[Vector2],
	seen_vertices: Dictionary,
	req: SimNavShortPathRequest,
	filter: SimNavObstructionFilter,
	diagnostics: Dictionary
) -> void:
	if req.pass_mask == 0:
		return
	var bounds := _short_path_search_bounds(req)
	var min_cell := _nav_map.world_to_navcell(bounds.position)
	var max_cell := _nav_map.world_to_navcell(bounds.position + bounds.size)
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
			_append_exposed_terrain_cell_vertices(vertices, seen_vertices, coord, req, diagnostics)


func _append_exposed_terrain_cell_vertices(
	vertices: Array[Vector2],
	seen_vertices: Dictionary,
	coord: Vector2i,
	req: SimNavShortPathRequest,
	diagnostics: Dictionary
) -> void:
	var left := Vector2i(coord.x - 1, coord.y)
	var right := Vector2i(coord.x + 1, coord.y)
	var up := Vector2i(coord.x, coord.y - 1)
	var down := Vector2i(coord.x, coord.y + 1)
	if _nav_map.is_passable_navcell(left, req.pass_mask):
		diagnostics["terrain_edge_count"] = int(diagnostics.get("terrain_edge_count", 0)) + 1
		_append_terrain_corner(vertices, seen_vertices, coord, -1.0, -1.0, req, diagnostics)
		_append_terrain_corner(vertices, seen_vertices, coord, -1.0, 1.0, req, diagnostics)
	if _nav_map.is_passable_navcell(right, req.pass_mask):
		diagnostics["terrain_edge_count"] = int(diagnostics.get("terrain_edge_count", 0)) + 1
		_append_terrain_corner(vertices, seen_vertices, coord, 1.0, -1.0, req, diagnostics)
		_append_terrain_corner(vertices, seen_vertices, coord, 1.0, 1.0, req, diagnostics)
	if _nav_map.is_passable_navcell(up, req.pass_mask):
		diagnostics["terrain_edge_count"] = int(diagnostics.get("terrain_edge_count", 0)) + 1
		_append_terrain_corner(vertices, seen_vertices, coord, -1.0, -1.0, req, diagnostics)
		_append_terrain_corner(vertices, seen_vertices, coord, 1.0, -1.0, req, diagnostics)
	if _nav_map.is_passable_navcell(down, req.pass_mask):
		diagnostics["terrain_edge_count"] = int(diagnostics.get("terrain_edge_count", 0)) + 1
		_append_terrain_corner(vertices, seen_vertices, coord, -1.0, 1.0, req, diagnostics)
		_append_terrain_corner(vertices, seen_vertices, coord, 1.0, 1.0, req, diagnostics)


func _append_terrain_corner(
	vertices: Array[Vector2],
	seen_vertices: Dictionary,
	coord: Vector2i,
	sx: float,
	sy: float,
	req: SimNavShortPathRequest,
	diagnostics: Dictionary
) -> void:
	var half_cell := _nav_map.navcell_size * 0.5
	var corner := _nav_map.navcell_center_world(coord) + Vector2(sx * (half_cell + EDGE_EXPAND_DELTA), sy * (half_cell + EDGE_EXPAND_DELTA))
	if not _nav_map.is_passable_navcell(_nav_map.world_to_navcell(corner), req.pass_mask):
		return
	var before := vertices.size()
	_append_unique_vertex(vertices, seen_vertices, corner)
	if vertices.size() > before:
		diagnostics["terrain_vertex_count"] = int(diagnostics.get("terrain_vertex_count", 0)) + 1


func _append_unique_vertex(vertices: Array[Vector2], seen_vertices: Dictionary, point: Vector2) -> void:
	var key := Vector2i(_coord_int(point.x), _coord_int(point.y))
	if seen_vertices.has(key):
		return
	seen_vertices[key] = true
	vertices.append(point)


func _static_shape_covers_navcell(coord: Vector2i, clearance: float, filter: SimNavObstructionFilter) -> bool:
	var center_world := _nav_map.navcell_center_world(coord)
	var query_range := clearance + _nav_map.navcell_size
	for shape in _nav_map.get_static_obstruction_shapes_in_range(center_world, query_range):
		if (shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		if filter != null and not filter.matches(shape):
			continue
		if shape.contains_point_with_clearance(center_world, clearance):
			return true
	return false


func _obstruction_query_range(req: SimNavShortPathRequest) -> float:
	if req.range_px <= 0.0:
		return -1.0
	return req.range_px + req.clearance + _nav_map.navcell_size * 2.0


func _short_path_search_bounds(req: SimNavShortPathRequest) -> Rect2:
	var virtual_goal := req.goal.nearest_point_on_goal(req.start)
	if req.range_px > 0.0:
		var to_goal := virtual_goal - req.start
		var goal_dist := to_goal.length()
		if goal_dist > req.range_px and goal_dist > 0.001:
			virtual_goal = req.start + to_goal / goal_dist * req.range_px
	var padding := maxf(req.clearance + _nav_map.navcell_size * 2.0, _nav_map.navcell_size)
	var min_world := Vector2(
		minf(req.start.x, virtual_goal.x) - padding,
		minf(req.start.y, virtual_goal.y) - padding
	)
	var max_world := Vector2(
		maxf(req.start.x, virtual_goal.x) + padding,
		maxf(req.start.y, virtual_goal.y) + padding
	)
	return Rect2(min_world, max_world - min_world)


func _astar_visibility(
	vertices: Array[Vector2],
	obstacles: Array,
	req: SimNavShortPathRequest,
	diagnostics: Dictionary
) -> SimNavWaypointPath:
	var open_keys: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var insertion_seq := 0
	var heuristic_weight := 1.0

	var goal_idx := 1
	g_score[0] = 0.0
	var h0 := req.goal.distance_to_point(vertices[0]) * heuristic_weight
	open_keys.append([h0, h0, _coord_int(vertices[0].x), _coord_int(vertices[0].y), insertion_seq, 0])
	insertion_seq += 1

	# Mirror 0 A.D. VertexPathfinder.cpp:868-900 — track the heuristically best
	# reachable vertex and reconstruct the path to it when the actual goal is
	# unreachable. Without this, A* returning empty causes motion to spin in
	# blocked_recovery → short path no_route → max_failed_movements forever
	# (e.g. when goal sits inside a static obstacle's swept clearance ring).
	var idx_best := 0
	var h_best := h0

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var current_idx := int(key[5])
		if closed.has(current_idx):
			continue
		closed[current_idx] = true
		if current_idx == goal_idx:
			return _reconstruct(vertices, came_from, current_idx)
		if current_idx != 0 and req.goal.contains_point(vertices[current_idx]):
			return _reconstruct(vertices, came_from, current_idx)
		diagnostics["astar_expansion_count"] = int(diagnostics.get("astar_expansion_count", 0)) + 1

		var current_pos := vertices[current_idx]
		var current_g: float = float(g_score[current_idx])
		for next_idx in _visibility_neighbor_indices(vertices, current_idx, goal_idx, closed):
			var next_pos := vertices[next_idx]
			if next_idx == goal_idx:
				next_pos = _goal_point_for_vertex(req, current_pos)
			if not _segment_clear_for_request(req, current_pos, next_pos, obstacles, diagnostics):
				continue
			var next_g := current_g + current_pos.distance_to(next_pos)
			if g_score.has(next_idx) and next_g >= float(g_score[next_idx]):
				continue
			if next_idx == goal_idx:
				vertices[goal_idx] = next_pos
			g_score[next_idx] = next_g
			came_from[next_idx] = current_idx
			var next_h := 0.0 if next_idx == goal_idx else req.goal.distance_to_point(next_pos) * heuristic_weight
			var f := next_g + next_h
			SimNavPathfinderHeap.insert(open_keys, [f, next_h, _coord_int(next_pos.x), _coord_int(next_pos.y), insertion_seq, next_idx])
			insertion_seq += 1
			if next_h < h_best:
				h_best = next_h
				idx_best = next_idx
	# Goal unreachable. If we reached anywhere closer to the goal than the start,
	# emit a partial path to that best vertex (lets motion make progress and
	# replan next tick). Otherwise the goal was unreachable from start, return
	# empty so the caller surfaces no_route.
	if idx_best != 0:
		return _reconstruct(vertices, came_from, idx_best)
	return SimNavWaypointPath.new()


func _visibility_neighbor_indices(
	vertices: Array[Vector2],
	current_idx: int,
	goal_idx: int,
	closed: Dictionary
) -> Array[int]:
	var result: Array[int] = []
	if current_idx != goal_idx and not closed.has(goal_idx):
		result.append(goal_idx)
	var current_pos := vertices[current_idx]
	var keys: Array = []
	for next_idx in range(vertices.size()):
		if next_idx == current_idx or next_idx == goal_idx or closed.has(next_idx):
			continue
		var next_pos := vertices[next_idx]
		keys.append([current_pos.distance_squared_to(next_pos), next_idx])
	keys.sort_custom(func(a: Array, b: Array) -> bool:
		if float(a[0]) == float(b[0]):
			return int(a[1]) < int(b[1])
		return float(a[0]) < float(b[0])
	)
	var limit := mini(_MAX_VISIBILITY_NEIGHBORS, keys.size())
	for i in range(limit):
		result.append(int(keys[i][1]))
	return result


# Mirror 0 A.D. VertexPathfinder.cpp:727-734 — vertices that fall inside another
# obstacle's dilated outline are unreachable, A* must not consider them.
# Without this an obstacle corner can be covered by a neighbor's collision ring
# and force A* to detour to a far, uncovered corner (regressive first waypoint).
func _vertex_covered_by_obstacles(vertex: Vector2, obstacles: Array, req: SimNavShortPathRequest) -> bool:
	var buffer := req.clearance
	for shape in obstacles:
		if shape is SimNavObstructionShapeUnit:
			var unit_shape := shape as SimNavObstructionShapeUnit
			var threshold := unit_shape.clearance + buffer + EDGE_EXPAND_DELTA
			if unit_shape.center.distance_to(vertex) < threshold - 0.001:
				return true
		elif shape is SimNavObstructionShapeStatic:
			var static_shape := shape as SimNavObstructionShapeStatic
			var extra := buffer + req.static_vertex_extra_outset + EDGE_EXPAND_DELTA - 0.001
			if static_shape.contains_point_with_clearance(vertex, extra):
				return true
	return false


func _segment_clear_for_request(
	req: SimNavShortPathRequest,
	a: Vector2,
	b: Vector2,
	obstacles: Array,
	diagnostics: Dictionary = {}
) -> bool:
	if diagnostics != null:
		diagnostics["visibility_check_count"] = int(diagnostics.get("visibility_check_count", 0)) + 1
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
