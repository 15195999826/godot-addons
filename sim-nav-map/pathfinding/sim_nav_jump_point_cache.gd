class_name SimNavJumpPointCache
extends RefCounted


var _nav_map: SimNavMap = null
var _pass_mask: int = 0
var _dirty: bool = true
var _cached_hits: Dictionary = {}


func reset(nav_map: SimNavMap, pass_mask: int) -> void:
	_nav_map = nav_map
	_pass_mask = pass_mask
	_dirty = false
	_cached_hits.clear()


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
	var current := start
	var steps := 0
	var last_passable := start
	while true:
		current += direction
		steps += 1
		if not _nav_map.is_valid_navcell(current):
			var boundary_hit := SimNavJumpPointHit.new(SimNavJumpPointHit.Kind.BOUNDARY, last_passable, steps - 1)
			_cached_hits[key] = boundary_hit
			return boundary_hit
		if not _nav_map.is_passable_navcell(current, _pass_mask):
			var obstruction_hit := SimNavJumpPointHit.new(SimNavJumpPointHit.Kind.OBSTRUCTION, current, steps)
			_cached_hits[key] = obstruction_hit
			return obstruction_hit
		if _has_forced_cardinal_jump(current, direction):
			var jump_hit := SimNavJumpPointHit.new(SimNavJumpPointHit.Kind.JUMP, current, steps)
			_cached_hits[key] = jump_hit
			return jump_hit
		last_passable = current
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


func _has_forced_cardinal_jump(cell: Vector2i, direction: Vector2i) -> bool:
	if direction.x != 0:
		return (
			(not _is_passable(Vector2i(cell.x - direction.x, cell.y - 1)) and _is_passable(Vector2i(cell.x, cell.y - 1)))
			or (not _is_passable(Vector2i(cell.x - direction.x, cell.y + 1)) and _is_passable(Vector2i(cell.x, cell.y + 1)))
		)
	return (
		(not _is_passable(Vector2i(cell.x - 1, cell.y - direction.y)) and _is_passable(Vector2i(cell.x - 1, cell.y)))
		or (not _is_passable(Vector2i(cell.x + 1, cell.y - direction.y)) and _is_passable(Vector2i(cell.x + 1, cell.y)))
	)


func _is_passable(cell: Vector2i) -> bool:
	return _nav_map.is_passable_navcell(cell, _pass_mask)


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
