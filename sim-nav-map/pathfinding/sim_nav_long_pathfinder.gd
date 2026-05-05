class_name SimNavLongPathfinder
extends RefCounted


const COST_HV: int = 65536
const COST_DIAG: int = 92682
const _PACK_LIMIT: int = 65536
const _NEIGHBOR_DX: Array[int] = [1, -1, 0, 0]
const _NEIGHBOR_DY: Array[int] = [0, 0, 1, -1]
const _DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

var _nav_map: SimNavMap = null
var _jump_point_caches: Dictionary = {}


func _init(nav_map: SimNavMap = null) -> void:
	_nav_map = nav_map


func compute_path_immediate(start_world: Vector2, goal: SimNavPathGoal, pass_mask: int) -> SimNavWaypointPath:
	if _nav_map == null:
		push_error("[SimNavLongPathfinder] compute_path_immediate: nav_map is null")
		return SimNavWaypointPath.new()
	if goal == null:
		push_error("[SimNavLongPathfinder] compute_path_immediate: goal is null")
		return SimNavWaypointPath.new()
	if _nav_map.width >= _PACK_LIMIT or _nav_map.height >= _PACK_LIMIT:
		push_error("[SimNavLongPathfinder] nav map is too large for packed cell ids")
		return SimNavWaypointPath.new()

	var start_cell := _nav_map.world_to_navcell(start_world)
	if not _nav_map.is_valid_navcell(start_cell):
		return SimNavWaypointPath.new()
	if goal.type == SimNavPathGoal.Type.POINT:
		var goal_cell := _nav_map.world_to_navcell(goal.center)
		if not _nav_map.is_valid_navcell(goal_cell):
			return SimNavWaypointPath.new()
		if not _nav_map.is_passable_navcell(goal_cell, pass_mask):
			return SimNavWaypointPath.new()
	if goal.navcell_contains_goal(_nav_map, start_cell):
		var same_cell := SimNavWaypointPath.new()
		same_cell.push_back(goal.nearest_point_on_goal(start_world))
		return same_cell
	var jps_path := _jps(start_cell, goal, pass_mask)
	if not jps_path.is_empty():
		return jps_path
	return _astar(start_cell, goal, pass_mask)


func invalidate_jump_point_cache() -> void:
	_jump_point_caches.clear()


func _jps(start: Vector2i, goal: SimNavPathGoal, pass_mask: int) -> SimNavWaypointPath:
	var cache := _jump_point_cache(pass_mask)
	var open_keys: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var insertion_seq := 0

	var start_pack := _pack_cell(start)
	g_score[start_pack] = 0
	var h0 := _heuristic(start, goal)
	open_keys.append([h0, h0, start.x, start.y, insertion_seq])
	insertion_seq += 1

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var current := Vector2i(int(key[2]), int(key[3]))
		var current_pack := _pack_cell(current)
		if closed.has(current_pack):
			continue
		closed[current_pack] = true
		if goal.navcell_contains_goal(_nav_map, current):
			return _reconstruct(came_from, start_pack, current_pack, goal)

		var current_g: int = int(g_score[current_pack])
		if current_pack == start_pack:
			insertion_seq = _add_start_successors(
				current,
				current_pack,
				current_g,
				goal,
				pass_mask,
				open_keys,
				came_from,
				g_score,
				closed,
				insertion_seq
			)
			continue
		for direction in _successor_directions(current, current_pack, start_pack, came_from, pass_mask):
			var jump := _jump(current, direction, goal, pass_mask, cache)
			if jump == current:
				continue
			var jump_pack := _pack_cell(jump)
			if closed.has(jump_pack):
				continue
			var jump_g := current_g + _movement_cost(current, jump)
			if g_score.has(jump_pack) and jump_g >= int(g_score[jump_pack]):
				continue
			g_score[jump_pack] = jump_g
			came_from[jump_pack] = current_pack
			var jump_h := _heuristic(jump, goal)
			var f := jump_g + jump_h
			SimNavPathfinderHeap.insert(open_keys, [f, jump_h, jump.x, jump.y, insertion_seq])
			insertion_seq += 1
	return SimNavWaypointPath.new()


func _add_start_successors(
	current: Vector2i,
	current_pack: int,
	current_g: int,
	goal: SimNavPathGoal,
	pass_mask: int,
	open_keys: Array,
	came_from: Dictionary,
	g_score: Dictionary,
	closed: Dictionary,
	insertion_seq: int
) -> int:
	for direction in _DIRECTIONS:
		var next_cell := current + direction
		if not _can_step(current, next_cell, direction, pass_mask):
			continue
		var next_pack := _pack_cell(next_cell)
		if closed.has(next_pack):
			continue
		var next_g := current_g + _movement_cost(current, next_cell)
		if g_score.has(next_pack) and next_g >= int(g_score[next_pack]):
			continue
		g_score[next_pack] = next_g
		came_from[next_pack] = current_pack
		var next_h := _heuristic(next_cell, goal)
		var f := next_g + next_h
		SimNavPathfinderHeap.insert(open_keys, [f, next_h, next_cell.x, next_cell.y, insertion_seq])
		insertion_seq += 1
	return insertion_seq


func _jump_point_cache(pass_mask: int) -> SimNavJumpPointCache:
	if not _jump_point_caches.has(pass_mask):
		var new_cache := SimNavJumpPointCache.new()
		new_cache.reset(_nav_map, pass_mask)
		_jump_point_caches[pass_mask] = new_cache
	var cache: SimNavJumpPointCache = _jump_point_caches[pass_mask]
	cache.invalidate_dirty_navcells(_nav_map)
	if cache.is_dirty():
		cache.reset(_nav_map, pass_mask)
	return cache


func _successor_directions(
	current: Vector2i,
	current_pack: int,
	start_pack: int,
	came_from: Dictionary,
	pass_mask: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if current_pack == start_pack or not came_from.has(current_pack):
		for direction in _DIRECTIONS:
			_append_successor_direction(result, direction)
		return result

	var parent := _cell_from_pack(int(came_from[current_pack]))
	var dx := _sign_int(current.x - parent.x)
	var dy := _sign_int(current.y - parent.y)
	if dx != 0 and dy != 0:
		_append_successor_direction(result, Vector2i(dx, dy))
		_append_successor_direction(result, Vector2i(dx, 0))
		_append_successor_direction(result, Vector2i(0, dy))
		if not _is_passable(Vector2i(current.x - dx, current.y), pass_mask) \
				and _is_passable(Vector2i(current.x - dx, current.y + dy), pass_mask):
			_append_successor_direction(result, Vector2i(-dx, dy))
		if not _is_passable(Vector2i(current.x, current.y - dy), pass_mask) \
				and _is_passable(Vector2i(current.x + dx, current.y - dy), pass_mask):
			_append_successor_direction(result, Vector2i(dx, -dy))
	elif dx != 0:
		_append_successor_direction(result, Vector2i(dx, 0))
		if not _is_passable(Vector2i(current.x, current.y - 1), pass_mask) \
				and _is_passable(Vector2i(current.x + dx, current.y - 1), pass_mask):
			_append_successor_direction(result, Vector2i(dx, -1))
		if not _is_passable(Vector2i(current.x, current.y + 1), pass_mask) \
				and _is_passable(Vector2i(current.x + dx, current.y + 1), pass_mask):
			_append_successor_direction(result, Vector2i(dx, 1))
	elif dy != 0:
		_append_successor_direction(result, Vector2i(0, dy))
		if not _is_passable(Vector2i(current.x - 1, current.y), pass_mask) \
				and _is_passable(Vector2i(current.x - 1, current.y + dy), pass_mask):
			_append_successor_direction(result, Vector2i(-1, dy))
		if not _is_passable(Vector2i(current.x + 1, current.y), pass_mask) \
				and _is_passable(Vector2i(current.x + 1, current.y + dy), pass_mask):
			_append_successor_direction(result, Vector2i(1, dy))
	return result


func _append_successor_direction(result: Array[Vector2i], direction: Vector2i) -> void:
	if direction == Vector2i.ZERO or result.has(direction):
		return
	result.append(direction)


func _jump(
	start: Vector2i,
	direction: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int,
	cache: SimNavJumpPointCache
) -> Vector2i:
	if direction.x == 0 or direction.y == 0:
		return _jump_cardinal(start, direction, goal, pass_mask, cache)
	return _jump_diagonal(start, direction, goal, pass_mask, cache)


func _jump_cardinal(
	start: Vector2i,
	direction: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int,
	cache: SimNavJumpPointCache
) -> Vector2i:
	if cache == null:
		return _jump_cardinal_uncached(start, direction, goal, pass_mask)
	var hit := cache.find(start, direction, goal)
	if hit.kind == SimNavJumpPointHit.Kind.GOAL or hit.kind == SimNavJumpPointHit.Kind.JUMP:
		return hit.cell
	return start


func _jump_cardinal_uncached(
	start: Vector2i,
	direction: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int
) -> Vector2i:
	var current := start
	while true:
		current += direction
		if not _is_passable(current, pass_mask):
			return start
		if goal.navcell_contains_goal(_nav_map, current):
			return current
		if _has_forced_cardinal_jump(current, direction, pass_mask):
			return current
	return start


func _jump_diagonal(
	start: Vector2i,
	direction: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int,
	cache: SimNavJumpPointCache
) -> Vector2i:
	var current := start
	while true:
		var next := current + direction
		if not _can_step(current, next, direction, pass_mask):
			return start
		if goal.navcell_contains_goal(_nav_map, next):
			return next
		var horizontal_jump := _jump_cardinal(next, Vector2i(direction.x, 0), goal, pass_mask, cache)
		var vertical_jump := _jump_cardinal(next, Vector2i(0, direction.y), goal, pass_mask, cache)
		if horizontal_jump != next or vertical_jump != next:
			return next
		current = next
	return start


func _can_step(from_cell: Vector2i, to_cell: Vector2i, direction: Vector2i, pass_mask: int) -> bool:
	if not _is_passable(to_cell, pass_mask):
		return false
	if direction.x != 0 and direction.y != 0:
		if not _is_passable(Vector2i(from_cell.x + direction.x, from_cell.y), pass_mask):
			return false
		if not _is_passable(Vector2i(from_cell.x, from_cell.y + direction.y), pass_mask):
			return false
	return true


func _has_forced_cardinal_jump(cell: Vector2i, direction: Vector2i, pass_mask: int) -> bool:
	if direction.x != 0:
		return (
			(not _is_passable(Vector2i(cell.x - direction.x, cell.y - 1), pass_mask)
				and _is_passable(Vector2i(cell.x, cell.y - 1), pass_mask))
			or (not _is_passable(Vector2i(cell.x - direction.x, cell.y + 1), pass_mask)
				and _is_passable(Vector2i(cell.x, cell.y + 1), pass_mask))
		)
	return (
		(not _is_passable(Vector2i(cell.x - 1, cell.y - direction.y), pass_mask)
			and _is_passable(Vector2i(cell.x - 1, cell.y), pass_mask))
		or (not _is_passable(Vector2i(cell.x + 1, cell.y - direction.y), pass_mask)
			and _is_passable(Vector2i(cell.x + 1, cell.y), pass_mask))
	)


func _astar(start: Vector2i, goal: SimNavPathGoal, pass_mask: int) -> SimNavWaypointPath:
	var open_keys: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var insertion_seq := 0

	var start_pack := _pack_cell(start)
	g_score[start_pack] = 0

	var h0 := _heuristic(start, goal)
	open_keys.append([h0, h0, start.x, start.y, insertion_seq])
	insertion_seq += 1

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var current := Vector2i(int(key[2]), int(key[3]))
		var current_pack := _pack_cell(current)
		if closed.has(current_pack):
			continue
		closed[current_pack] = true
		if goal.navcell_contains_goal(_nav_map, current):
			return _reconstruct(came_from, start_pack, current_pack, goal)

		var current_g: int = int(g_score[current_pack])
		for direction_idx in range(4):
			var next_cell := Vector2i(current.x + _NEIGHBOR_DX[direction_idx], current.y + _NEIGHBOR_DY[direction_idx])
			if not _nav_map.is_passable_navcell(next_cell, pass_mask):
				continue
			var next_pack := _pack_cell(next_cell)
			if closed.has(next_pack):
				continue
			var next_g := current_g + COST_HV
			if g_score.has(next_pack) and next_g >= int(g_score[next_pack]):
				continue
			g_score[next_pack] = next_g
			came_from[next_pack] = current_pack
			var next_h := _heuristic(next_cell, goal)
			var f := next_g + next_h
			SimNavPathfinderHeap.insert(open_keys, [f, next_h, next_cell.x, next_cell.y, insertion_seq])
			insertion_seq += 1
	return SimNavWaypointPath.new()


func _heuristic(cell: Vector2i, goal: SimNavPathGoal) -> int:
	if goal.type == SimNavPathGoal.Type.POINT:
		var goal_cell := _nav_map.world_to_navcell(goal.center)
		return _octile_cost(cell, goal_cell)
	var center_world := _nav_map.navcell_center_world(cell)
	return int(round(goal.distance_to_point(center_world) / _nav_map.navcell_size * float(COST_HV)))


func _octile_cost(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	var diagonal := mini(dx, dy)
	var straight := maxi(dx, dy) - diagonal
	return diagonal * COST_DIAG + straight * COST_HV


func _movement_cost(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return _octile_cost(from_cell, to_cell)


func _is_passable(cell: Vector2i, pass_mask: int) -> bool:
	return _nav_map.is_passable_navcell(cell, pass_mask)


func _sign_int(value: int) -> int:
	if value < 0:
		return -1
	if value > 0:
		return 1
	return 0


func _pack_cell(cell: Vector2i) -> int:
	return cell.x * _PACK_LIMIT + cell.y


func _cell_from_pack(packed_cell: int) -> Vector2i:
	@warning_ignore("integer_division")
	var x: int = packed_cell / _PACK_LIMIT
	var y: int = packed_cell % _PACK_LIMIT
	return Vector2i(x, y)


func _reconstruct(came_from: Dictionary, start_pack: int, goal_pack: int, goal: SimNavPathGoal) -> SimNavWaypointPath:
	var path := SimNavWaypointPath.new()
	var trail: Array[int] = [goal_pack]
	var current := goal_pack
	while current != start_pack:
		if not came_from.has(current):
			return SimNavWaypointPath.new()
		current = int(came_from[current])
		trail.append(current)
	for i in range(trail.size() - 1):
		var packed_cell := trail[i]
		var point := _nav_map.navcell_center_world(_cell_from_pack(packed_cell))
		if i == 0:
			point = goal.nearest_point_on_goal(point)
		path.push_back(point)
	return path
