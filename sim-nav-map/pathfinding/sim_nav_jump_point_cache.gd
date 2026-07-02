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


# Refresh observability (fissure-style runtime walls): how often this cache
# repaired locally vs rebuilt from scratch.
var repair_count: int = 0
var full_reset_count: int = 0
# Dirty revision this cache last repaired/rebuilt against (see
# SimNavMap.dirty_navcell_revision) — lets per-tick hot entries skip repeat
# repairs while the dirty set is unchanged.
var repaired_dirty_revision: int = -1


func reset(nav_map: SimNavMap, pass_mask: int) -> void:
	_nav_map = nav_map
	_pass_mask = pass_mask
	_dirty = false
	_cached_hits.clear()
	_bake_grid()
	_build_ray_tables()
	full_reset_count += 1
	if _nav_map != null:
		repaired_dirty_revision = _nav_map.dirty_navcell_revision()


# Incrementally refresh the baked grid + ray tables for changed navcells.
# A changed cell only influences ray rows y-1..y+1 (horizontal forced checks
# read the adjacent rows) and ray columns x-1..x+1; those bands are rebuilt
# with the same row/col bodies the full build uses, so repair output is
# byte-identical to a full rebuild by construction (welded by
# smoke_sim_nav_jump_table_repair). Falls back to reset() when the band
# approaches half of a full rebuild.
func repair_dirty_cells(dirty_cells: Array[Vector2i]) -> void:
	if _nav_map == null:
		return
	if _dirty or _baked.is_empty():
		reset(_nav_map, _pass_mask)
		return
	if dirty_cells.is_empty():
		return
	var w := _baked_width
	var h := _baked_height
	var rows: Dictionary = {}
	var cols: Dictionary = {}
	for cell in dirty_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
			continue
		_baked[cell.y * w + cell.x] = _nav_map.get_navcell_data(cell)
		for dy in range(-1, 2):
			var y := cell.y + dy
			if y >= 0 and y < h:
				rows[y] = true
		for dx in range(-1, 2):
			var x := cell.x + dx
			if x >= 0 and x < w:
				cols[x] = true
	if rows.is_empty():
		return
	if rows.size() * 2 * w + cols.size() * 2 * h > 2 * w * h:
		reset(_nav_map, _pass_mask)
		return
	_rebuild_ray_rows(rows.keys())
	_rebuild_ray_cols(cols.keys())
	_cached_hits.clear()
	repair_count += 1


# Equality weld for the repair smoke: incremental repair must reproduce a
# full rebuild bit-for-bit.
func tables_equal(other: SimNavJumpPointCache) -> bool:
	return _baked == other._baked \
		and _ray_east == other._ray_east \
		and _ray_west == other._ray_west \
		and _ray_south == other._ray_south \
		and _ray_north == other._ray_north


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


# Boolean escape-rule raster walk, twin of
# SimNavPathfinderFacade._first_blocked_line_navcell (0 A.D.
# CheckLineMovement): movement may START on an impassable navcell and keep
# walking through impassable cells until it first reaches a passable one;
# after that, re-entering impassable fails. Keep the traversal in lockstep
# with the facade twin — only the per-cell reads differ (baked grid instead
# of two cross-object calls per crossed cell).
func movement_line_clear(a: Vector2, b: Vector2) -> bool:
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
	var on_impassable := (_baked[j0 * w + i0] & mask) != 0
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
	var max_steps := absi(i1 - i0) + absi(j1 - j0) + 4
	var ci := i0
	var cj := j0
	while ci != i1 or cj != j1:
		if max_steps <= 0:
			return false
		max_steps -= 1
		if ci == i1:
			cj += step_j
			t_max_y += delta_t_y
		elif cj == j1:
			ci += step_i
			t_max_x += delta_t_x
		elif t_max_x < t_max_y:
			ci += step_i
			t_max_x += delta_t_x
		else:
			cj += step_j
			t_max_y += delta_t_y
		if ci < 0 or cj < 0 or ci >= w or cj >= h:
			return false
		if (_baked[cj * w + ci] & mask) == 0:
			on_impassable = false
		elif not on_impassable:
			return false
	return true


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
	_ray_east = PackedInt32Array()
	_ray_west = PackedInt32Array()
	_ray_south = PackedInt32Array()
	_ray_north = PackedInt32Array()
	if size <= 0:
		return
	_ray_east.resize(size)
	_ray_west.resize(size)
	_ray_south.resize(size)
	_ray_north.resize(size)
	_rebuild_ray_rows(range(_baked_height))
	_rebuild_ray_cols(range(_baked_width))


# DP sweep against the scan direction: a ray from (x, y) first examines the
# neighbor cell n = (x + dir, y); if n is passable and not a forced-jump cell
# the ray continues exactly as the ray from n, one step longer. Forced-cell
# test matches the runtime scan the tables replace (see
# SimNavLongPathfinder._has_forced_cardinal_jump).
#
# A row's horizontal entries are a pure intra-row function of the baked grid
# (forced checks read baked rows y±1, never other table rows), and columns
# mirror that — so full build and incremental repair share these bodies and
# rebuild order cannot matter. All table access goes through the member
# arrays directly: packed arrays are copy-on-write values in GDScript, so a
# hoisted local alias would silently detach from the member on first write.
func _rebuild_ray_rows(rows: Array) -> void:
	for row_value in rows:
		var y := int(row_value)
		_rebuild_ray_row_east(y)
		_rebuild_ray_row_west(y)


func _rebuild_ray_cols(cols: Array) -> void:
	for col_value in cols:
		var x := int(col_value)
		_rebuild_ray_col_south(x)
		_rebuild_ray_col_north(x)


func _rebuild_ray_row_east(y: int) -> void:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	var row := y * w
	for step in range(w):
		var x := w - 1 - step
		var i := row + x
		if (_baked[i] & mask) != 0:
			_ray_east[i] = _RAY_IMPASSABLE
			continue
		if x + 1 >= w:
			_ray_east[i] = _RAY_BOUNDARY
			continue
		var ni := i + 1
		if (_baked[ni] & mask) != 0:
			_ray_east[i] = (1 << 2) | _RAY_OBSTRUCTION
			continue
		var forced := false
		if y > 0:
			# blocked at (x, y - 1) with (x + 1, y - 1) open
			if (_baked[i - w] & mask) != 0 and (_baked[ni - w] & mask) == 0:
				forced = true
		if not forced and y + 1 < h:
			if (_baked[i + w] & mask) != 0 and (_baked[ni + w] & mask) == 0:
				forced = true
		if forced:
			_ray_east[i] = (1 << 2) | _RAY_JUMP
		else:
			_ray_east[i] = _ray_east[ni] + 4


func _rebuild_ray_row_west(y: int) -> void:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	var row := y * w
	for x in range(w):
		var i := row + x
		if (_baked[i] & mask) != 0:
			_ray_west[i] = _RAY_IMPASSABLE
			continue
		if x - 1 < 0:
			_ray_west[i] = _RAY_BOUNDARY
			continue
		var ni := i - 1
		if (_baked[ni] & mask) != 0:
			_ray_west[i] = (1 << 2) | _RAY_OBSTRUCTION
			continue
		var forced := false
		if y > 0:
			# blocked at (x, y - 1) with (x - 1, y - 1) open
			if (_baked[i - w] & mask) != 0 and (_baked[ni - w] & mask) == 0:
				forced = true
		if not forced and y + 1 < h:
			if (_baked[i + w] & mask) != 0 and (_baked[ni + w] & mask) == 0:
				forced = true
		if forced:
			_ray_west[i] = (1 << 2) | _RAY_JUMP
		else:
			_ray_west[i] = _ray_west[ni] + 4


func _rebuild_ray_col_south(x: int) -> void:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	for step in range(h):
		var y := h - 1 - step
		var i := y * w + x
		if (_baked[i] & mask) != 0:
			_ray_south[i] = _RAY_IMPASSABLE
			continue
		if y + 1 >= h:
			_ray_south[i] = _RAY_BOUNDARY
			continue
		var ni := i + w
		if (_baked[ni] & mask) != 0:
			_ray_south[i] = (1 << 2) | _RAY_OBSTRUCTION
			continue
		var forced := false
		if x > 0:
			# blocked at (x - 1, y) with (x - 1, y + 1) open
			if (_baked[i - 1] & mask) != 0 and (_baked[ni - 1] & mask) == 0:
				forced = true
		if not forced and x + 1 < w:
			if (_baked[i + 1] & mask) != 0 and (_baked[ni + 1] & mask) == 0:
				forced = true
		if forced:
			_ray_south[i] = (1 << 2) | _RAY_JUMP
		else:
			_ray_south[i] = _ray_south[ni] + 4


func _rebuild_ray_col_north(x: int) -> void:
	var w := _baked_width
	var h := _baked_height
	var mask := _pass_mask
	for y in range(h):
		var i := y * w + x
		if (_baked[i] & mask) != 0:
			_ray_north[i] = _RAY_IMPASSABLE
			continue
		if y - 1 < 0:
			_ray_north[i] = _RAY_BOUNDARY
			continue
		var ni := i - w
		if (_baked[ni] & mask) != 0:
			_ray_north[i] = (1 << 2) | _RAY_OBSTRUCTION
			continue
		var forced := false
		if x > 0:
			# blocked at (x - 1, y) with (x - 1, y - 1) open
			if (_baked[i - 1] & mask) != 0 and (_baked[ni - 1] & mask) == 0:
				forced = true
		if not forced and x + 1 < w:
			if (_baked[i + 1] & mask) != 0 and (_baked[ni + 1] & mask) == 0:
				forced = true
		if forced:
			_ray_north[i] = (1 << 2) | _RAY_JUMP
		else:
			_ray_north[i] = _ray_north[ni] + 4


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
