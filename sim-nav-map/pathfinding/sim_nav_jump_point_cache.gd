class_name SimNavJumpPointCache
extends RefCounted


var _nav_map: SimNavMap = null
var _pass_mask: int = 0
var _dirty: bool = true
var _cached_hits: Dictionary = {}
# Composed passability baked into a flat array at reset. Ray scans are the
# hot path of every cache miss — and misses are the common case in real play
# (rays are keyed by start cell, which changes whenever units move). Reading
# a local packed array beats three-layer composition through two levels of
# cross-object calls per cell by a wide margin. Rebaked on reset; dirty
# navcells already invalidate the whole cache, so staleness cannot leak.
var _baked: PackedInt32Array = PackedInt32Array()
var _baked_width: int = 0
var _baked_height: int = 0


func reset(nav_map: SimNavMap, pass_mask: int) -> void:
	_nav_map = nav_map
	_pass_mask = pass_mask
	_dirty = false
	_cached_hits.clear()
	_bake_grid()


func _bake_grid() -> void:
	if _nav_map == null:
		_baked = PackedInt32Array()
		_baked_width = 0
		_baked_height = 0
		return
	_baked_width = _nav_map.width
	_baked_height = _nav_map.height
	_baked.resize(_baked_width * _baked_height)
	var i := 0
	for y in range(_baked_height):
		for x in range(_baked_width):
			_baked[i] = _nav_map.get_navcell_data(Vector2i(x, y))
			i += 1


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
	var cached_hit := _find_cached_jump_obstruction_or_boundary(start, direction)
	var goal_hit := _find_goal_before_hit(start, direction, goal, cached_hit)
	if goal_hit.kind != SimNavJumpPointHit.Kind.NONE:
		return goal_hit
	return cached_hit


func _find_cached_jump_obstruction_or_boundary(start: Vector2i, direction: Vector2i) -> SimNavJumpPointHit:
	var key := _cache_key(start, direction)
	if _cached_hits.has(key):
		return _cached_hits[key] as SimNavJumpPointHit
	var cx := start.x
	var cy := start.y
	var dx := direction.x
	var dy := direction.y
	var last_x := cx
	var last_y := cy
	var steps := 0
	while true:
		cx += dx
		cy += dy
		steps += 1
		if cx < 0 or cy < 0 or cx >= _baked_width or cy >= _baked_height:
			var boundary_hit := SimNavJumpPointHit.new(
				SimNavJumpPointHit.Kind.BOUNDARY, Vector2i(last_x, last_y), steps - 1)
			_cached_hits[key] = boundary_hit
			return boundary_hit
		if (_baked[cy * _baked_width + cx] & _pass_mask) != 0:
			var obstruction_hit := SimNavJumpPointHit.new(
				SimNavJumpPointHit.Kind.OBSTRUCTION, Vector2i(cx, cy), steps)
			_cached_hits[key] = obstruction_hit
			return obstruction_hit
		var forced: bool
		if dx != 0:
			forced = (not _baked_passable(cx - dx, cy - 1) and _baked_passable(cx, cy - 1)) \
				or (not _baked_passable(cx - dx, cy + 1) and _baked_passable(cx, cy + 1))
		else:
			forced = (not _baked_passable(cx - 1, cy - dy) and _baked_passable(cx - 1, cy)) \
				or (not _baked_passable(cx + 1, cy - dy) and _baked_passable(cx + 1, cy))
		if forced:
			var jump_hit := SimNavJumpPointHit.new(
				SimNavJumpPointHit.Kind.JUMP, Vector2i(cx, cy), steps)
			_cached_hits[key] = jump_hit
			return jump_hit
		last_x = cx
		last_y = cy
	return SimNavJumpPointHit.new()


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
	# This runs on EVERY cardinal probe (diagonal jumps issue two per step),
	# so the generic per-cell scan below dominated whole-query cost for the
	# most common goal shape.
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


# Integer keys: this runs on every cardinal probe, and string formatting +
# string hashing dominated the cache lookup itself.
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
