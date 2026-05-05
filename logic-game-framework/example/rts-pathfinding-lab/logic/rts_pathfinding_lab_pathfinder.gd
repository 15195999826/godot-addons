class_name RtsPathfindingLabPathfinder
extends RefCounted


const LabObstacle := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabUnit := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")

const CORNER_OUTSET_MIN: float = 5.0
const INF: float = 1.0e20

var map_size: Vector2 = Vector2(720.0, 420.0)
var cell_size: float = 16.0
var unit_radius: float = 11.0
var last_report: Dictionary = {}


func _init(p_map_size: Vector2 = Vector2(720.0, 420.0), p_cell_size: float = 16.0, p_unit_radius: float = 11.0) -> void:
	map_size = p_map_size
	cell_size = p_cell_size
	unit_radius = p_unit_radius


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
	var reachable_goal := goal
	var used_make_goal_reachable := false
	if not is_point_passable(goal, active_obstacles, unit_radius):
		reachable_goal = _make_goal_reachable(goal, active_obstacles, unit_radius)
		used_make_goal_reachable = true

	var vertex_path := _find_vertex_path(start, reachable_goal, active_obstacles, unit_radius)
	if not vertex_path.is_empty():
		last_report = {
			"used_vertex": true,
			"used_grid_fallback": false,
			"used_make_goal_reachable": used_make_goal_reachable,
			"reachable_goal": reachable_goal,
			"path_size": vertex_path.size(),
		}
		return vertex_path

	var grid_path := _find_grid_path(start, reachable_goal, active_obstacles, unit_radius)
	var smoothed := _string_pull(start, grid_path, active_obstacles, unit_radius)
	last_report = {
		"used_vertex": false,
		"used_grid_fallback": true,
		"used_make_goal_reachable": used_make_goal_reachable,
		"reachable_goal": reachable_goal,
		"path_size": smoothed.size(),
	}
	return smoothed


func is_point_passable(point: Vector2, obstacles: Array[RtsPathfindingLabObstacle], clearance: float) -> bool:
	if point.x < 0.0 or point.y < 0.0 or point.x > map_size.x or point.y > map_size.y:
		return false
	for obstacle in obstacles:
		if obstacle.get_inflated_rect(clearance).has_point(point):
			return false
	return true


func segment_clear(a: Vector2, b: Vector2, obstacles: Array[RtsPathfindingLabObstacle], clearance: float) -> bool:
	if a.x < -1.0 or b.x < -1.0 or a.y < -1.0 or b.y < -1.0:
		return false
	if a.x > map_size.x + 1.0 or b.x > map_size.x + 1.0:
		return false
	if a.y > map_size.y + 1.0 or b.y > map_size.y + 1.0:
		return false
	for obstacle in obstacles:
		if _segment_intersects_rect(a, b, obstacle.get_inflated_rect(clearance)):
			return false
	return true


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


func _find_vertex_path(
	start: Vector2,
	goal: Vector2,
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> Array[Vector2]:
	if segment_clear(start, goal, obstacles, clearance):
		return [goal]

	var vertices: Array[Vector2] = [start, goal]
	var sorted_obstacles := obstacles.duplicate()
	sorted_obstacles.sort_custom(func(a: RtsPathfindingLabObstacle, b: RtsPathfindingLabObstacle) -> bool:
		return a.id < b.id
	)
	var outset: float = maxf(CORNER_OUTSET_MIN, clearance * 0.45)
	for obstacle in sorted_obstacles:
		for corner in obstacle.get_inflated_corners(clearance, outset):
			if is_point_passable(corner, obstacles, clearance * 0.15):
				vertices.append(corner)

	return _astar_visibility(vertices, obstacles, clearance)


func _astar_visibility(
	vertices: Array[Vector2],
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> Array[Vector2]:
	var open: Array[int] = [0]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {0: 0.0}
	var closed: Dictionary = {}

	while not open.is_empty():
		var current := _pop_best_vertex(open, vertices, g_score)
		if current == 1:
			return _reconstruct_vertex_path(vertices, came_from, current)
		closed[current] = true

		for next_idx in range(vertices.size()):
			if next_idx == current or closed.has(next_idx):
				continue
			if not segment_clear(vertices[current], vertices[next_idx], obstacles, clearance):
				continue
			var tentative: float = float(g_score.get(current, INF)) + vertices[current].distance_to(vertices[next_idx])
			if tentative >= float(g_score.get(next_idx, INF)):
				continue
			came_from[next_idx] = current
			g_score[next_idx] = tentative
			if not open.has(next_idx):
				open.append(next_idx)
	return []


func _pop_best_vertex(open: Array[int], vertices: Array[Vector2], g_score: Dictionary) -> int:
	var best_pos := 0
	var best_idx := open[0]
	var best_f: float = float(g_score.get(best_idx, INF)) + vertices[best_idx].distance_to(vertices[1])
	var best_h: float = vertices[best_idx].distance_to(vertices[1])
	for k in range(1, open.size()):
		var idx: int = open[k]
		var h := vertices[idx].distance_to(vertices[1])
		var f: float = float(g_score.get(idx, INF)) + h
		if f < best_f or (is_equal_approx(f, best_f) and (h < best_h or (is_equal_approx(h, best_h) and idx < best_idx))):
			best_pos = k
			best_idx = idx
			best_f = f
			best_h = h
	open.remove_at(best_pos)
	return best_idx


func _reconstruct_vertex_path(vertices: Array[Vector2], came_from: Dictionary, current: int) -> Array[Vector2]:
	var reversed_path: Array[Vector2] = [vertices[current]]
	while came_from.has(current):
		current = int(came_from[current])
		if current != 0:
			reversed_path.append(vertices[current])
	reversed_path.reverse()
	return reversed_path


func _find_grid_path(
	start: Vector2,
	goal: Vector2,
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> Array[Vector2]:
	var start_cell := _world_to_cell(start)
	var goal_cell := _world_to_cell(goal)
	if not _is_cell_passable(goal_cell, obstacles, clearance, start_cell):
		goal_cell = _nearest_passable_cell(goal_cell, obstacles, clearance, start_cell)

	var open: Array[Vector2i] = [start_cell]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cell: 0.0}
	var closed: Dictionary = {}

	while not open.is_empty():
		var current := _pop_best_cell(open, goal_cell, g_score)
		if current == goal_cell:
			var points := _reconstruct_cell_path(came_from, current, start_cell)
			points.append(goal)
			return points
		closed[current] = true

		for nb in _neighbors(current):
			if closed.has(nb):
				continue
			if not _is_cell_passable(nb, obstacles, clearance, start_cell):
				continue
			var step_cost := _cell_center(current).distance_to(_cell_center(nb))
			var tentative: float = float(g_score.get(current, INF)) + step_cost
			if tentative >= float(g_score.get(nb, INF)):
				continue
			came_from[nb] = current
			g_score[nb] = tentative
			if not open.has(nb):
				open.append(nb)
	return []


func _pop_best_cell(open: Array[Vector2i], goal_cell: Vector2i, g_score: Dictionary) -> Vector2i:
	var best_pos := 0
	var best_cell := open[0]
	var best_h := _cell_center(best_cell).distance_to(_cell_center(goal_cell))
	var best_f: float = float(g_score.get(best_cell, INF)) + best_h
	for k in range(1, open.size()):
		var cell: Vector2i = open[k]
		var h := _cell_center(cell).distance_to(_cell_center(goal_cell))
		var f: float = float(g_score.get(cell, INF)) + h
		if f < best_f or (is_equal_approx(f, best_f) and (h < best_h or (is_equal_approx(h, best_h) and _cell_key_less(cell, best_cell)))):
			best_pos = k
			best_cell = cell
			best_f = f
			best_h = h
	open.remove_at(best_pos)
	return best_cell


func _reconstruct_cell_path(came_from: Dictionary, current: Vector2i, start_cell: Vector2i) -> Array[Vector2]:
	var cells: Array[Vector2i] = []
	while current != start_cell:
		cells.append(current)
		current = came_from[current] as Vector2i
	cells.reverse()
	var result: Array[Vector2] = []
	for cell in cells:
		result.append(_cell_center(cell))
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


func _make_goal_reachable(
	goal: Vector2,
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> Vector2:
	var goal_cell := _world_to_cell(goal)
	var passable_cell := _nearest_passable_cell(goal_cell, obstacles, clearance, Vector2i(-999999, -999999))
	return _cell_center(passable_cell)


func _nearest_passable_cell(
	origin: Vector2i,
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float,
	start_cell: Vector2i
) -> Vector2i:
	if _is_cell_passable(origin, obstacles, clearance, start_cell):
		return origin
	var max_radius := maxi(_grid_width(), _grid_height())
	for radius in range(1, max_radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if x != origin.x - radius and x != origin.x + radius and y != origin.y - radius and y != origin.y + radius:
					continue
				var cell := Vector2i(x, y)
				if _is_cell_passable(cell, obstacles, clearance, start_cell):
					return cell
	return origin


func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			if x == cell.x and y == cell.y:
				continue
			result.append(Vector2i(x, y))
	return result


func _is_cell_passable(
	cell: Vector2i,
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float,
	start_cell: Vector2i
) -> bool:
	if cell == start_cell:
		return true
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_width() or cell.y >= _grid_height():
		return false
	return is_point_passable(_cell_center(cell), obstacles, clearance)


func _world_to_cell(point: Vector2) -> Vector2i:
	var x := clampi(int(floor(point.x / cell_size)), 0, _grid_width() - 1)
	var y := clampi(int(floor(point.y / cell_size)), 0, _grid_height() - 1)
	return Vector2i(x, y)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * cell_size, (float(cell.y) + 0.5) * cell_size)


func _grid_width() -> int:
	return int(ceil(map_size.x / cell_size))


func _grid_height() -> int:
	return int(ceil(map_size.y / cell_size))


func _cell_key_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


static func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var p0 := rect.position
	var p1 := Vector2(rect.position.x + rect.size.x, rect.position.y)
	var p2 := rect.position + rect.size
	var p3 := Vector2(rect.position.x, rect.position.y + rect.size.y)
	return _segments_intersect(a, b, p0, p1) \
		or _segments_intersect(a, b, p1, p2) \
		or _segments_intersect(a, b, p2, p3) \
		or _segments_intersect(a, b, p3, p0)


static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var r := b - a
	var s := d - c
	var denom := _cross(r, s)
	var qp := c - a
	if absf(denom) <= 0.00001:
		if absf(_cross(qp, r)) > 0.00001:
			return false
		var rr := r.length_squared()
		if rr <= 0.00001:
			return a.distance_to(c) <= 0.00001
		var t0 := qp.dot(r) / rr
		var t1 := t0 + s.dot(r) / rr
		if t0 > t1:
			var tmp := t0
			t0 = t1
			t1 = tmp
		return maxf(t0, 0.0) <= minf(t1, 1.0)
	var t := _cross(qp, s) / denom
	var u := _cross(qp, r) / denom
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x
