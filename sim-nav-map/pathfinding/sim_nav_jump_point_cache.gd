class_name SimNavJumpPointCache
extends RefCounted

# JPS+ style precomputed ray tables. The old shape — lazily cache each
# (start_cell, direction) ray scan in a Dictionary — had a ~0% hit rate in
# real play: rays are keyed by start cell, and start cells change whenever
# units move, so every query re-paid the full per-cell scan (measured ~9.5k
# passability probes / ~4.8k scanned cells per cross-map query). The tables
# below precompute every cardinal ray once per reset, so a query-time probe
# is a single packed-array read. Reset cost is O(4 * cells) and rides the
# existing invalidation contract: dirty navcells already invalidate the whole
# cache, so staleness cannot leak.

# Ray table entry: (steps << 2) | kind. `cell = start + direction * steps`
# holds for all kinds (JUMP: forced-neighbor cell, OBSTRUCTION: first blocked
# cell, BOUNDARY: last passable cell before the map edge).
const _RAY_JUMP := 0
const _RAY_OBSTRUCTION := 1
const _RAY_BOUNDARY := 2
# Entry for impassable start cells. Never read on healthy paths: find()
# guards impassable starts, and jump walks only stand on passable cells.
const _RAY_IMPASSABLE := 3


var _nav_map: SimNavMap = null
var _pass_mask: int = 0
var _dirty: bool = true
# find() results memoized per (start, direction), same observable behavior as
# the pre-table cache (cached_entry_count() counts distinct rays queried
# through find()). Hot paths bypass find() and read the tables directly.
var _cached_hits: Dictionary = {}
# Composed passability baked into a flat array at reset (input for the ray
# tables, and the per-cell test for diagonal walks / segment walks).
var _baked: PackedInt32Array = PackedInt32Array()
var _baked_width: int = 0
var _baked_height: int = 0
var _origin: Vector2 = Vector2.ZERO
var _cell_size: float = 1.0
# Cardinal ray tables, indexed like _cache_key directions:
# east (+1,0) / west (-1,0) / south (0,+1) / north (0,-1).
var _ray_east: PackedInt32Array = PackedInt32Array()
var _ray_west: PackedInt32Array = PackedInt32Array()
var _ray_south: PackedInt32Array = PackedInt32Array()
var _ray_north: PackedInt32Array = PackedInt32Array()


func reset(nav_map: SimNavMap, pass_mask: int) -> void:
	_nav_map = nav_map
	_pass_mask = pass_mask
	_dirty = false
	_cached_hits.clear()
	_bake_grid()
	_build_ray_tables()


func _bake_grid() -> void:
	if _nav_map == null:
		_baked = PackedInt32Array()
		_baked_width = 0
		_baked_height = 0
		return
	_baked_width = _nav_map.width
	_baked_height = _nav_map.height
	_origin = _nav_map.origin
	_cell_size = _nav_map.navcell_size
	_baked = _nav_map.composed_navcell_data()


func invalidate_all() -> void:
	_dirty = true
	_cached_hits.clear()


func invalidate_dirty_navcells(nav_map: SimNavMap) -> bool:
	if nav_map == null or not nav_map.has_dirty_navcells():
		return false
	invalidate_all()
	return true


func is_dirty() -> bool:
	return _dirty


func cached_entry_count() -> int:
	return _cached_hits.size()


func find(start: Vector2i, direction: Vector2i, goal: SimNavPathGoal) -> SimNavJumpPointHit:
	if _dirty or _nav_map == null or goal == null:
		return SimNavJumpPointHit.new()
	if not _is_cardinal_direction(direction):
		push_error("[SimNavJumpPointCache] only cardinal directions are supported")
		return SimNavJumpPointHit.new()
	if not _nav_map.is_valid_navcell(start) or not _nav_map.is_passable_navcell(start, _pass_mask):
		return SimNavJumpPointHit.new()
	var cached_hit := _ray_hit(start, direction)
	if cached_hit.kind == SimNavJumpPointHit.Kind.NONE:
		return cached_hit
	var goal_hit := _find_goal_before_hit(start, direction, goal, cached_hit)
	if goal_hit.kind != SimNavJumpPointHit.Kind.NONE:
		return goal_hit
	return cached_hit


# ── Hot paths (all-int, POINT goals) ─────────────────────────────────────────

# Full jump dispatch for POINT goals; mirrors SimNavLongPathfinder._jump and
# returns `start` when there is no jump in `direction`. Callers guarantee
# `start` is a passable in-bounds cell and the cache is fresh.
func jump_point(start: Vector2i, direction: Vector2i, goal_cell: Vector2i) -> Vector2i:
	if direction.x != 0 and direction.y != 0:
		return _jump_diagonal_point(start, direction, goal_cell)
	var entry := _ray_table_for(direction)[start.y * _baked_width + start.x]
	var kind := entry & 3
	var steps := entry >> 2
	var max_steps := steps - 1 if kind == _RAY_OBSTRUCTION else steps
	var step_count := (goal_cell.x - start.x) * direction.x + (goal_cell.y - start.y) * direction.y
	if step_count >= 1 and step_count <= max_steps \
			and start.x + direction.x * step_count == goal_cell.x \
			and start.y + direction.y * step_count == goal_cell.y:
		return goal_cell
	if kind == _RAY_JUMP:
		return Vector2i(start.x + direction.x * steps, start.y + direction.y * steps)
	return start


func _jump_diagonal_point(start: Vector2i, direction: Vector2i, goal_cell: Vector2i) -> Vector2i:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	var dx := direction.x
	var dy := direction.y
	var gx := goal_cell.x
	var gy := goal_cell.y
	var h_table := _ray_east if dx == 1 else _ray_west
	var v_table := _ray_south if dy == 1 else _ray_north
	var cx := start.x
	var cy := start.y
	while true:
		var nx := cx + dx
		var ny := cy + dy
		# _can_step: to-cell plus both cardinal-adjacent cells must be passable
		# (no corner cutting). (nx, cy) and (cx, ny) are in bounds once nx/ny are.
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			return start
		if (_baked[ny * w + nx] & mask) != 0:
			return start
		if (_baked[cy * w + nx] & mask) != 0:
			return start
		if (_baked[ny * w + cx] & mask) != 0:
			return start
		if nx == gx and ny == gy:
			return Vector2i(nx, ny)
		# Diagonal jump point: either cardinal ray from the advanced cell sees
		# a forced jump or the goal within its passable run.
		var entry := h_table[ny * w + nx]
		var kind := entry & 3
		if kind == _RAY_JUMP:
			return Vector2i(nx, ny)
		var step_count := (gx - nx) * dx
		if gy == ny and step_count >= 1 \
				and step_count <= (entry >> 2) - (1 if kind == _RAY_OBSTRUCTION else 0):
			return Vector2i(nx, ny)
		entry = v_table[ny * w + nx]
		kind = entry & 3
		if kind == _RAY_JUMP:
			return Vector2i(nx, ny)
		step_count = (gy - ny) * dy
		if gx == nx and step_count >= 1 \
				and step_count <= (entry >> 2) - (1 if kind == _RAY_OBSTRUCTION else 0):
			return Vector2i(nx, ny)
		cx = nx
		cy = ny
	return start


# Straight-segment passability against the baked grid. Twin of
# SimNavLongPathfinder._segment_passable_clear for the no-excluded-regions
# case — keep the traversal (Amanatides-Woo walk + axis-convergence guard)
# in lockstep with that twin; only the per-cell test differs.
func segment_clear(a: Vector2, b: Vector2) -> bool:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	var cell_size := _cell_size
	var i0 := int(floor((a.x - _origin.x) / cell_size))
	var j0 := int(floor((a.y - _origin.y) / cell_size))
	var i1 := int(floor((b.x - _origin.x) / cell_size))
	var j1 := int(floor((b.y - _origin.y) / cell_size))
	if i0 < 0 or j0 < 0 or i0 >= w or j0 >= h:
		return false
	if (_baked[j0 * w + i0] & mask) != 0:
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
		t_max_x = (_origin.x + float(i0 + 1) * cell_size - a.x) / dx
		delta_t_x = cell_size / dx
	elif dx < 0.0:
		step_i = -1
		t_max_x = (_origin.x + float(i0) * cell_size - a.x) / dx
		delta_t_x = -cell_size / dx
	if dy > 0.0:
		step_j = 1
		t_max_y = (_origin.y + float(j0 + 1) * cell_size - a.y) / dy
		delta_t_y = cell_size / dy
	elif dy < 0.0:
		step_j = -1
		t_max_y = (_origin.y + float(j0) * cell_size - a.y) / dy
		delta_t_y = -cell_size / dy
	var i := i0
	var j := j0
	var max_steps := absi(i1 - i0) + absi(j1 - j0) + 4
	while i != i1 or j != j1:
		if max_steps <= 0:
			return false
		max_steps -= 1
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
		if i < 0 or j < 0 or i >= w or j >= h:
			return false
		if (_baked[j * w + i] & mask) != 0:
			return false
	return true


# ── Ray tables ───────────────────────────────────────────────────────────────

func _ray_hit(start: Vector2i, direction: Vector2i) -> SimNavJumpPointHit:
	var key := _cache_key(start, direction)
	if _cached_hits.has(key):
		return _cached_hits[key] as SimNavJumpPointHit
	var entry := _ray_table_for(direction)[start.y * _baked_width + start.x]
	var kind_code := entry & 3
	if kind_code == _RAY_IMPASSABLE:
		return SimNavJumpPointHit.new()
	var steps := entry >> 2
	var kind := SimNavJumpPointHit.Kind.JUMP
	if kind_code == _RAY_OBSTRUCTION:
		kind = SimNavJumpPointHit.Kind.OBSTRUCTION
	elif kind_code == _RAY_BOUNDARY:
		kind = SimNavJumpPointHit.Kind.BOUNDARY
	var hit := SimNavJumpPointHit.new(kind, start + direction * steps, steps)
	_cached_hits[key] = hit
	return hit


func _ray_table_for(direction: Vector2i) -> PackedInt32Array:
	if direction.x == 1:
		return _ray_east
	if direction.x == -1:
		return _ray_west
	if direction.y == 1:
		return _ray_south
	return _ray_north


func _build_ray_tables() -> void:
	var size := _baked_width * _baked_height
	if size <= 0:
		_ray_east = PackedInt32Array()
		_ray_west = PackedInt32Array()
		_ray_south = PackedInt32Array()
		_ray_north = PackedInt32Array()
		return
	_ray_east = _build_ray_table_horizontal(1)
	_ray_west = _build_ray_table_horizontal(-1)
	_ray_south = _build_ray_table_vertical(1)
	_ray_north = _build_ray_table_vertical(-1)


# DP sweep against the scan direction: a ray from (x, y) first examines the
# neighbor cell n = (x + dir, y); if n is passable and not a forced-jump cell
# the ray continues exactly as the ray from n, one step longer. Forced-cell
# test matches the runtime scan the tables replace (see _has_forced flags in
# SimNavLongPathfinder._has_forced_cardinal_jump).
func _build_ray_table_horizontal(dir: int) -> PackedInt32Array:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	var table := PackedInt32Array()
	table.resize(w * h)
	var x_from := w - 1 if dir == 1 else 0
	var x_to := -1 if dir == 1 else w
	var x_step := -dir
	for y in range(h):
		var row := y * w
		var x := x_from
		while x != x_to:
			var i := row + x
			if (_baked[i] & mask) != 0:
				table[i] = _RAY_IMPASSABLE
				x += x_step
				continue
			var nx := x + dir
			if nx < 0 or nx >= w:
				table[i] = _RAY_BOUNDARY
				x += x_step
				continue
			var ni := row + nx
			if (_baked[ni] & mask) != 0:
				table[i] = (1 << 2) | _RAY_OBSTRUCTION
				x += x_step
				continue
			var forced := false
			if y > 0:
				# blocked at (nx - dir, y - 1) with (nx, y - 1) open
				if (_baked[ni - w - dir] & mask) != 0 and (_baked[ni - w] & mask) == 0:
					forced = true
			if not forced and y + 1 < h:
				if (_baked[ni + w - dir] & mask) != 0 and (_baked[ni + w] & mask) == 0:
					forced = true
			if forced:
				table[i] = (1 << 2) | _RAY_JUMP
			else:
				table[i] = table[ni] + 4
			x += x_step
	return table


func _build_ray_table_vertical(dir: int) -> PackedInt32Array:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	var table := PackedInt32Array()
	table.resize(w * h)
	var y_from := h - 1 if dir == 1 else 0
	var y_to := -1 if dir == 1 else h
	var y_step := -dir
	var dir_row := dir * w
	for x in range(w):
		var y := y_from
		while y != y_to:
			var i := y * w + x
			if (_baked[i] & mask) != 0:
				table[i] = _RAY_IMPASSABLE
				y += y_step
				continue
			var ny := y + dir
			if ny < 0 or ny >= h:
				table[i] = _RAY_BOUNDARY
				y += y_step
				continue
			var ni := i + dir_row
			if (_baked[ni] & mask) != 0:
				table[i] = (1 << 2) | _RAY_OBSTRUCTION
				y += y_step
				continue
			var forced := false
			if x > 0:
				# blocked at (x - 1, ny - dir) with (x - 1, ny) open
				if (_baked[ni - 1 - dir_row] & mask) != 0 and (_baked[ni - 1] & mask) == 0:
					forced = true
			if not forced and x + 1 < w:
				if (_baked[ni + 1 - dir_row] & mask) != 0 and (_baked[ni + 1] & mask) == 0:
					forced = true
			if forced:
				table[i] = (1 << 2) | _RAY_JUMP
			else:
				table[i] = table[ni] + 4
			y += y_step
	return table


func _find_goal_before_hit(
	start: Vector2i,
	direction: Vector2i,
	goal: SimNavPathGoal,
	obstruction_hit: SimNavJumpPointHit
) -> SimNavJumpPointHit:
	var max_steps := obstruction_hit.steps
	if obstruction_hit.kind == SimNavJumpPointHit.Kind.OBSTRUCTION:
		max_steps -= 1
	# POINT goals resolve in O(1): the goal is on this cardinal ray iff its
	# axis projection lands within range and reconstructs the same cell.
	if goal.type == SimNavPathGoal.Type.POINT:
		var goal_cell := _nav_map.world_to_navcell(goal.center)
		var delta := goal_cell - start
		var step_count := delta.x * direction.x + delta.y * direction.y
		if step_count < 1 or step_count > max_steps:
			return SimNavJumpPointHit.new()
		if start + direction * step_count != goal_cell:
			return SimNavJumpPointHit.new()
		return SimNavJumpPointHit.new(SimNavJumpPointHit.Kind.GOAL, goal_cell, step_count)
	for step in range(1, max_steps + 1):
		var cell := start + direction * step
		if goal.navcell_contains_goal(_nav_map, cell):
			return SimNavJumpPointHit.new(SimNavJumpPointHit.Kind.GOAL, cell, step)
	return SimNavJumpPointHit.new()


func _is_cardinal_direction(direction: Vector2i) -> bool:
	return (
		(direction.x == 1 and direction.y == 0)
		or (direction.x == -1 and direction.y == 0)
		or (direction.x == 0 and direction.y == 1)
		or (direction.x == 0 and direction.y == -1)
	)


func _baked_passable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _baked_width or y >= _baked_height:
		return false
	return (_baked[y * _baked_width + x] & _pass_mask) == 0


# Integer keys: string formatting + string hashing dominated the lookup here
# before; keep them packed ints.
const _KEY_STRIDE := 1 << 17

func _cache_key(start: Vector2i, direction: Vector2i) -> int:
	var dir_index := 0
	if direction.x == -1:
		dir_index = 1
	elif direction.y == 1:
		dir_index = 2
	elif direction.y == -1:
		dir_index = 3
	return (start.x * _KEY_STRIDE + start.y) * 4 + dir_index
