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


func compute_path_result(query: SimNavLongPathQuery) -> SimNavLongPathResult:
	var result := SimNavLongPathResult.new()
	if query == null:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_GOAL_MISSING)
		return result
	result.configure_query(query, _nav_map)
	result.post_process = _normalized_post_process(query.post_process)
	result.waypoint_spacing = _effective_waypoint_spacing(query)

	if _nav_map == null:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_NAV_MAP_MISSING)
		return result
	if query.goal == null:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_GOAL_MISSING)
		return result
	if query.pass_mask == 0:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_PASS_MASK_MISSING)
		return result
	if _nav_map.width >= _PACK_LIMIT or _nav_map.height >= _PACK_LIMIT:
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_MAP_TOO_LARGE)
		return result

	var start_cell := _nav_map.world_to_navcell(query.start_world)
	result.start_navcell = start_cell
	result.effective_start_navcell = start_cell
	result.effective_start_world = query.start_world
	if not _nav_map.is_valid_navcell(start_cell):
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_START_OUT_OF_BOUNDS)
		return result
	if not _nav_map.is_inside_playable_bounds(query.start_world):
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_START_OUT_OF_BOUNDS)
		return result
	if not _is_passable_with_exclusions(start_cell, query.pass_mask, query.excluded_regions):
		result.set_failure(SimNavLongPathResult.STATUS_INVALID_START, SimNavLongPathResult.FAILURE_START_BLOCKED)
		return result

	if query.goal.type == SimNavPathGoal.Type.POINT:
		var goal_cell := _nav_map.world_to_navcell(query.goal.center)
		result.canonical_navcell = goal_cell
		if not _nav_map.is_valid_navcell(goal_cell):
			result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_GOAL_OUT_OF_BOUNDS)
			return result
		if not _nav_map.is_inside_playable_bounds(query.goal.center):
			result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_GOAL_OUT_OF_BOUNDS)
			return result
		if not _is_passable_with_exclusions(goal_cell, query.pass_mask, query.excluded_regions):
			result.set_failure(SimNavLongPathResult.STATUS_UNREACHABLE, SimNavLongPathResult.FAILURE_GOAL_BLOCKED)
			return result

	if query.goal.navcell_contains_goal(_nav_map, start_cell):
		var direct_path := SimNavWaypointPath.new()
		direct_path.push_back(query.goal.nearest_point_on_goal(query.start_world))
		var direct_cells: Array[Vector2i] = [start_cell]
		var refined_direct := _refine_waypoint_path(direct_path, query, result.post_process, result.waypoint_spacing)
		result.apply_search_diagnostics(_new_search_diagnostics("direct"))
		result.set_paths(SimNavLongPathResult.STATUS_DIRECT_GOAL, direct_cells, direct_path, refined_direct, 0)
		return result

	var diagnostics := _new_search_diagnostics("jps")
	var raw_cells: Array[Vector2i] = []
	var refinement_cells: Array[Vector2i] = []
	if query.excluded_regions.is_empty():
		var sparse_cells := _jps_cells(start_cell, query.goal, query.pass_mask, diagnostics)
		refinement_cells = sparse_cells
		raw_cells = _expand_sparse_navcell_path(sparse_cells)
	else:
		diagnostics = _new_search_diagnostics("astar_excluded")
		raw_cells = _astar_cells(start_cell, query.goal, query.pass_mask, query.excluded_regions, diagnostics)
		refinement_cells = raw_cells
	_set_search_count(diagnostics, "path_cell_count", refinement_cells.size())
	result.apply_search_diagnostics(diagnostics)
	if raw_cells.is_empty():
		result.set_failure(SimNavLongPathResult.STATUS_NO_PATH, SimNavLongPathResult.FAILURE_NO_ROUTE)
		return result

	var raw_path := _waypoint_path_from_cells(raw_cells, query.goal)
	var refinement_path := raw_path
	if refinement_cells.size() != raw_cells.size():
		refinement_path = _waypoint_path_from_cells(refinement_cells, query.goal)
	var refined_path := _refine_waypoint_path(refinement_path, query, result.post_process, result.waypoint_spacing)
	result.canonical_navcell = raw_cells[raw_cells.size() - 1]
	result.set_paths(
		SimNavLongPathResult.STATUS_SUCCESS,
		raw_cells,
		raw_path,
		refined_path,
		_path_cost_for_cells(raw_cells)
	)
	return result


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


# Pay the bake + ray-table build (~10 ms on a 165x113 map) at rebuild time
# instead of on the first plan after it. Optional: queries prewarm lazily
# either way.
func prewarm_jump_point_cache(pass_mask: int) -> void:
	if _nav_map == null or pass_mask == 0:
		return
	_jump_point_cache(pass_mask)


# Dirty-flush entry (facade): incrementally repair every built cache for the
# currently-dirty navcells instead of discarding them. Must run BEFORE the
# dirty flags are cleared. invalidate_jump_point_cache() stays as the nuclear
# path for full rebuilds.
func repair_jump_point_caches() -> void:
	if _nav_map == null or not _nav_map.has_dirty_navcells():
		return
	var dirty_cells := _nav_map.collect_dirty_navcells()
	for cache_value in _jump_point_caches.values():
		(cache_value as SimNavJumpPointCache).repair_dirty_cells(dirty_cells)


func _astar_cells(
	start: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int,
	excluded_regions: Array[Dictionary],
	diagnostics: Dictionary = {}
) -> Array[Vector2i]:
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
	_increment_search_count(diagnostics, "push_count")
	_update_search_max_open(diagnostics, open_keys.size())

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var current := Vector2i(int(key[2]), int(key[3]))
		var current_pack := _pack_cell(current)
		if closed.has(current_pack):
			continue
		closed[current_pack] = true
		_increment_search_count(diagnostics, "expansion_count")
		_set_search_count(diagnostics, "closed_count", closed.size())
		if goal.navcell_contains_goal(_nav_map, current):
			return _reconstruct_cells(came_from, start_pack, current_pack)

		var current_g: int = int(g_score[current_pack])
		for direction in _DIRECTIONS:
			var next_cell := current + direction
			if not _can_step_with_exclusions(current, next_cell, direction, pass_mask, excluded_regions):
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
			_increment_search_count(diagnostics, "push_count")
			_update_search_max_open(diagnostics, open_keys.size())
	return []


func _reconstruct_cells(came_from: Dictionary, start_pack: int, goal_pack: int) -> Array[Vector2i]:
	var reverse_cells: Array[int] = [goal_pack]
	var current := goal_pack
	while current != start_pack:
		if not came_from.has(current):
			return []
		current = int(came_from[current])
		reverse_cells.append(current)
	var cells: Array[Vector2i] = []
	for i in range(reverse_cells.size() - 1, -1, -1):
		cells.append(_cell_from_pack(reverse_cells[i]))
	return cells


func _expand_sparse_navcell_path(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 1:
		return cells.duplicate()
	var expanded: Array[Vector2i] = [cells[0]]
	for i in range(1, cells.size()):
		var segment := _expand_navcell_segment(cells[i - 1], cells[i])
		for j in range(1, segment.size()):
			expanded.append(segment[j])
	return expanded


func _expand_navcell_segment(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var segment: Array[Vector2i] = [from_cell]
	var delta := to_cell - from_cell
	var step_count := maxi(absi(delta.x), absi(delta.y))
	if step_count <= 0:
		return segment
	for step in range(1, step_count + 1):
		var t := float(step) / float(step_count)
		var cell := Vector2i(
			from_cell.x + int(round(float(delta.x) * t)),
			from_cell.y + int(round(float(delta.y) * t))
		)
		if segment[segment.size() - 1] != cell:
			segment.append(cell)
	if segment[segment.size() - 1] != to_cell:
		segment.append(to_cell)
	return segment


func _waypoint_path_from_cells(cells: Array[Vector2i], goal: SimNavPathGoal) -> SimNavWaypointPath:
	var path := SimNavWaypointPath.new()
	for i in range(cells.size() - 1, 0, -1):
		var point := _nav_map.navcell_center_world(cells[i])
		if i == cells.size() - 1:
			point = goal.nearest_point_on_goal(point)
		path.push_back(point)
	return path


func _refine_waypoint_path(
	raw_path: SimNavWaypointPath,
	query: SimNavLongPathQuery,
	post_process: String,
	spacing: float
) -> SimNavWaypointPath:
	if raw_path == null or raw_path.is_empty():
		return SimNavWaypointPath.new()
	if post_process == SimNavLongPathQuery.POST_PROCESS_RAW:
		return _clone_waypoint_path(raw_path)

	# Segment checks walk every crossed navcell; the baked-grid twin drops two
	# cross-object calls per cell. Excluded regions stay on the generic path.
	var segment_cache: SimNavJumpPointCache = null
	if query.excluded_regions.is_empty():
		segment_cache = _jump_point_cache(query.pass_mask)
	var execution_points := _path_to_execution_points(raw_path)
	execution_points = _compress_execution_points(
		query.start_world, execution_points, query.pass_mask, query.excluded_regions, segment_cache)
	if spacing > 0.0:
		execution_points = _apply_waypoint_spacing(query.start_world, execution_points, spacing)
	return _execution_points_to_path(execution_points)


func _path_to_execution_points(path: SimNavWaypointPath) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in range(path.waypoints.size() - 1, -1, -1):
		result.append(path.waypoints[i])
	return result


func _execution_points_to_path(points: Array[Vector2]) -> SimNavWaypointPath:
	var path := SimNavWaypointPath.new()
	for i in range(points.size() - 1, -1, -1):
		path.push_back(points[i])
	return path


func _compress_execution_points(
	start_world: Vector2,
	points: Array[Vector2],
	pass_mask: int,
	excluded_regions: Array[Dictionary],
	segment_cache: SimNavJumpPointCache = null
) -> Array[Vector2]:
	if points.is_empty():
		return []
	var result: Array[Vector2] = []
	var anchor := start_world
	var idx := 0
	while idx < points.size():
		var chosen := idx
		for j in range(points.size() - 1, idx - 1, -1):
			if _segment_passable_clear(anchor, points[j], pass_mask, excluded_regions, segment_cache):
				chosen = j
				break
		result.append(points[chosen])
		anchor = points[chosen]
		idx = chosen + 1
	return result


func _apply_waypoint_spacing(start_world: Vector2, points: Array[Vector2], spacing: float) -> Array[Vector2]:
	if spacing <= 0.0 or points.is_empty():
		return points.duplicate()
	var result: Array[Vector2] = []
	var anchor := start_world
	for point in points:
		var distance := anchor.distance_to(point)
		var steps := maxi(1, int(ceil(distance / spacing)))
		for step in range(1, steps + 1):
			result.append(anchor.lerp(point, float(step) / float(steps)))
		anchor = point
	return result


func _segment_passable_clear(
	a: Vector2,
	b: Vector2,
	pass_mask: int,
	excluded_regions: Array[Dictionary],
	segment_cache: SimNavJumpPointCache = null
) -> bool:
	if segment_cache != null:
		return segment_cache.segment_clear(a, b)
	# Visit every navcell the segment crosses with an Amanatides-Woo voxel
	# traversal instead of the prior uniform sampling at navcell*0.5. Uniform
	# sampling can skip a cell whose crossing arc is shorter than the sample
	# step (mirrors 0 A.D. CheckLineMovement's per-cell walk in
	# Pathfinding.cpp); this version cannot.
	var origin := _nav_map.origin
	var cell_size := _nav_map.navcell_size
	var i0 := int(floor((a.x - origin.x) / cell_size))
	var j0 := int(floor((a.y - origin.y) / cell_size))
	var i1 := int(floor((b.x - origin.x) / cell_size))
	var j1 := int(floor((b.y - origin.y) / cell_size))
	if not _is_passable_with_exclusions(Vector2i(i0, j0), pass_mask, excluded_regions):
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
	# Each iteration advances one cell along the segment; the loop ends after
	# at most |i1 - i0| + |j1 - j0| steps. Safety bound caps runaway loops in
	# pathological FP cases (segment length effectively zero with non-equal
	# endpoint cells).
	var max_steps := absi(i1 - i0) + absi(j1 - j0) + 4
	while i != i1 or j != j1:
		# Fail closed on budget exhaustion — an unverified segment must not
		# be reported as clear.
		if max_steps <= 0:
			return false
		max_steps -= 1
		# Axis-convergence guard (0 A.D. CheckLineMovement, Pathfinding.cpp:
		# 83-91): once one axis has reached the target, only the other axis
		# may advance — an endpoint on an exact grid line otherwise steps off
		# the target row on a t_max tie and never lands.
		if i == i1:
			j += step_j
			t_max_y += delta_t_y
		elif j == j1:
			i += step_i
			t_max_x += delta_t_x
		elif t_max_x < t_max_y:
			i += step_i
			t_max_x += delta_t_x
		else:
			j += step_j
			t_max_y += delta_t_y
		if not _is_passable_with_exclusions(Vector2i(i, j), pass_mask, excluded_regions):
			return false
	return true


func _clone_waypoint_path(path: SimNavWaypointPath) -> SimNavWaypointPath:
	var cloned_path := SimNavWaypointPath.new()
	if path == null:
		return cloned_path
	for point in path.waypoints:
		cloned_path.push_back(point)
	return cloned_path


func _path_cost_for_cells(cells: Array[Vector2i]) -> int:
	var total := 0
	for i in range(1, cells.size()):
		total += _movement_cost(cells[i - 1], cells[i])
	return total


func _normalized_post_process(post_process: String) -> String:
	if post_process in [
		SimNavLongPathQuery.POST_PROCESS_RAW,
		SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT,
		SimNavLongPathQuery.POST_PROCESS_MAX_SPACING,
	]:
		return post_process
	return SimNavLongPathQuery.POST_PROCESS_RAW


func _effective_waypoint_spacing(query: SimNavLongPathQuery) -> float:
	if query == null or query.post_process == SimNavLongPathQuery.POST_PROCESS_RAW:
		return 0.0
	if query.waypoint_spacing > 0.0:
		return query.waypoint_spacing
	if query.goal != null and query.goal.maxdist > 0.0:
		return query.goal.maxdist
	return 0.0


func _new_search_diagnostics(algorithm: String) -> Dictionary:
	return {
		"algorithm": algorithm,
		"expansion_count": 0,
		"push_count": 0,
		"jump_count": 0,
		"closed_count": 0,
		"max_open_count": 0,
		"path_cell_count": 0,
	}


func _increment_search_count(diagnostics: Dictionary, key: String) -> void:
	diagnostics[key] = int(diagnostics.get(key, 0)) + 1


func _set_search_count(diagnostics: Dictionary, key: String, value: int) -> void:
	diagnostics[key] = value


func _update_search_max_open(diagnostics: Dictionary, open_count: int) -> void:
	if open_count > int(diagnostics.get("max_open_count", 0)):
		diagnostics["max_open_count"] = open_count


func _can_step_with_exclusions(
	from_cell: Vector2i,
	to_cell: Vector2i,
	direction: Vector2i,
	pass_mask: int,
	excluded_regions: Array[Dictionary]
) -> bool:
	if not _is_passable_with_exclusions(to_cell, pass_mask, excluded_regions):
		return false
	if direction.x != 0 and direction.y != 0:
		if not _is_passable_with_exclusions(Vector2i(from_cell.x + direction.x, from_cell.y), pass_mask, excluded_regions):
			return false
		if not _is_passable_with_exclusions(Vector2i(from_cell.x, from_cell.y + direction.y), pass_mask, excluded_regions):
			return false
	return true


func _is_passable_with_exclusions(cell: Vector2i, pass_mask: int, excluded_regions: Array[Dictionary]) -> bool:
	if not _nav_map.is_passable_navcell(cell, pass_mask):
		return false
	if _is_cell_excluded(cell, excluded_regions):
		return false
	return true


func _is_cell_excluded(cell: Vector2i, excluded_regions: Array[Dictionary]) -> bool:
	if excluded_regions.is_empty() or not _nav_map.is_valid_navcell(cell):
		return false
	var center := _nav_map.navcell_center_world(cell)
	for region in excluded_regions:
		var region_dict := region as Dictionary
		var radius := maxf(0.0, float(region_dict.get("radius", 0.0)))
		if radius <= 0.0:
			continue
		var region_center: Vector2 = region_dict.get("center", Vector2.ZERO)
		if center.distance_to(region_center) <= radius:
			return true
	return false


func _jps(start: Vector2i, goal: SimNavPathGoal, pass_mask: int) -> SimNavWaypointPath:
	var cells := _jps_cells(start, goal, pass_mask, _new_search_diagnostics("jps_immediate"))
	if cells.is_empty():
		return SimNavWaypointPath.new()
	return _waypoint_path_from_cells(cells, goal)


func _jps_cells(
	start: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int,
	diagnostics: Dictionary = {}
) -> Array[Vector2i]:
	var cache := _jump_point_cache(pass_mask)
	# POINT goals take the all-int table-jump path: same jump targets, no Hit
	# allocations and no per-cell goal containment calls on the hot loop.
	var use_point_jump := goal.type == SimNavPathGoal.Type.POINT
	var point_goal_cell := _nav_map.world_to_navcell(goal.center) if use_point_jump else Vector2i.ZERO
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
	_increment_search_count(diagnostics, "push_count")
	_update_search_max_open(diagnostics, open_keys.size())

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var current := Vector2i(int(key[2]), int(key[3]))
		var current_pack := _pack_cell(current)
		if closed.has(current_pack):
			continue
		closed[current_pack] = true
		_increment_search_count(diagnostics, "expansion_count")
		_set_search_count(diagnostics, "closed_count", closed.size())
		if goal.navcell_contains_goal(_nav_map, current):
			return _reconstruct_cells(came_from, start_pack, current_pack)

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
				insertion_seq,
				diagnostics
			)
			continue
		for direction in _successor_directions(current, current_pack, start_pack, came_from, pass_mask):
			_increment_search_count(diagnostics, "jump_count")
			var jump := cache.jump_point(current, direction, point_goal_cell) if use_point_jump \
					else _jump(current, direction, goal, pass_mask, cache)
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
			_increment_search_count(diagnostics, "push_count")
			_update_search_max_open(diagnostics, open_keys.size())
	return []


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
	insertion_seq: int,
	diagnostics: Dictionary = {}
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
		_increment_search_count(diagnostics, "push_count")
		_update_search_max_open(diagnostics, open_keys.size())
	return insertion_seq


func _jump_point_cache(pass_mask: int) -> SimNavJumpPointCache:
	if not _jump_point_caches.has(pass_mask):
		var new_cache := SimNavJumpPointCache.new()
		new_cache.reset(_nav_map, pass_mask)
		_jump_point_caches[pass_mask] = new_cache
		# The fresh build already baked the current map data — repairing for
		# still-uncleared dirty flags here would be pure redundant work.
		return new_cache
	var cache: SimNavJumpPointCache = _jump_point_caches[pass_mask]
	if cache.is_dirty():
		cache.reset(_nav_map, pass_mask)
	elif _nav_map != null and _nav_map.has_dirty_navcells():
		# Uncleared dirty flags (integrations that never flush through the
		# facade): repair per query — idempotent, and strictly cheaper than
		# the full reset this path used to pay.
		cache.repair_dirty_cells(_nav_map.collect_dirty_navcells())
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
		if not _is_passable(Vector2i(current.x - dx, current.y - 1), pass_mask):
			_append_successor_direction(result, Vector2i(dx, -1))
			_append_successor_direction(result, Vector2i(0, -1))
		if not _is_passable(Vector2i(current.x - dx, current.y + 1), pass_mask):
			_append_successor_direction(result, Vector2i(dx, 1))
			_append_successor_direction(result, Vector2i(0, 1))
	elif dy != 0:
		_append_successor_direction(result, Vector2i(0, dy))
		if not _is_passable(Vector2i(current.x - 1, current.y - dy), pass_mask):
			_append_successor_direction(result, Vector2i(-1, dy))
			_append_successor_direction(result, Vector2i(-1, 0))
		if not _is_passable(Vector2i(current.x + 1, current.y - dy), pass_mask):
			_append_successor_direction(result, Vector2i(1, dy))
			_append_successor_direction(result, Vector2i(1, 0))
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
