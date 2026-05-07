class_name SimNavMap
extends RefCounted


var width: int = 0
var height: int = 0
var navcell_size: float = 1.0
var origin: Vector2 = Vector2.ZERO
var navcells_per_tile: int = 1

var _terrain_tile_map: SimNavTerrainTileMap = null
var _passability_registry: SimNavPassabilityClassRegistry = SimNavPassabilityClassRegistry.new()
var _navcell_data: PackedInt32Array = PackedInt32Array()
var _terrain_navcell_data: PackedInt32Array = PackedInt32Array()
var _obstruction_navcell_data: PackedInt32Array = PackedInt32Array()
var _dirtiness: PackedByteArray = PackedByteArray()
var _obstruction_dirtiness: PackedByteArray = PackedByteArray()
# Parallel list of currently-dirty obstruction navcells. Lets collect/has/clear
# operations run in O(dirty_count) instead of scanning the full grid byte
# array. _obstruction_dirtiness remains the source of truth for membership;
# this list is appended whenever a cell flips 0 → 1 and is drained by
# clear_dirty_obstruction_navcells.
var _obstruction_dirty_cell_list: Array[Vector2i] = []
var _static_obstructions: Dictionary = {}
var _dynamic_obstructions: Dictionary = {}
var _static_obstruction_index: SimNavSpatialIndex = null
var _dynamic_obstruction_index: SimNavSpatialIndex = null
var _next_obstruction_tag: int = 1

# Playable bounds in world coordinates. Defaults to the full backing-grid
# extent so existing callers see no behavior change. set_bounds() lets a
# caller express a tighter rectangle: long-path start/goal queries reject
# points outside it (status=invalid_query, failure_reason=...out_of_bounds),
# and static rasterization clips to it (cells whose center is outside the
# rectangle are not marked blocked, so a straddling OBB only rasterizes its
# in-bounds portion). Mirrors 0 A.D. ICmpObstructionManager::SetBounds.
var _playable_bounds_min: Vector2 = Vector2.ZERO
var _playable_bounds_max: Vector2 = Vector2.ZERO


func _init(
	p_width: int = 0,
	p_height: int = 0,
	p_navcell_size: float = 1.0,
	p_origin: Vector2 = Vector2.ZERO,
	p_navcells_per_tile: int = 1
) -> void:
	width = p_width
	height = p_height
	navcell_size = p_navcell_size
	origin = p_origin
	navcells_per_tile = maxi(1, p_navcells_per_tile)
	_playable_bounds_min = origin
	_playable_bounds_max = origin + Vector2(float(width), float(height)) * navcell_size
	_terrain_tile_map = SimNavTerrainTileMap.new(width, height, navcells_per_tile)
	_static_obstruction_index = SimNavSpatialIndex.new(_default_spatial_cell_size())
	_dynamic_obstruction_index = SimNavSpatialIndex.new(_default_spatial_cell_size())
	_navcell_data.resize(width * height)
	_terrain_navcell_data.resize(width * height)
	_obstruction_navcell_data.resize(width * height)
	_dirtiness.resize(width * height)
	_obstruction_dirtiness.resize(width * height)
	_clear_navcell_data()


func register_passability_class(config: SimNavPassabilityClassConfig) -> int:
	var mask := _passability_registry.register(config)
	if mask != 0:
		rebuild_terrain_passability()
		_mark_all_static_obstructions_dirty()
	return mask


func get_passability_registry() -> SimNavPassabilityClassRegistry:
	return _passability_registry


func get_passability_classes() -> Array[SimNavPassabilityClassConfig]:
	return _passability_registry.get_classes()


func get_passability_mask(class_name_id: String) -> int:
	return _passability_registry.get_mask(class_name_id)


func get_terrain_tile_map() -> SimNavTerrainTileMap:
	return _terrain_tile_map


func navcell_to_terrain_tile(coord: Vector2i) -> Vector2i:
	return _terrain_tile_map.navcell_to_tile(coord)


func get_terrain_tile_data(tile: Vector2i) -> int:
	return _terrain_tile_map.get_tile_data(tile)


func set_terrain_tile_data(tile: Vector2i, value: int) -> void:
	if not _terrain_tile_map.is_valid_tile(tile):
		return
	var old_value := _terrain_tile_map.get_tile_data(tile)
	if old_value == value:
		return
	_terrain_tile_map.set_tile_data(tile, value)
	_rebuild_terrain_tile_passability(tile)


func get_navcell_terrain_data(coord: Vector2i) -> int:
	return _terrain_tile_map.get_navcell_terrain_data(coord)


func rebuild_terrain_passability() -> int:
	var changed_count := 0
	for y in range(height):
		for x in range(width):
			if _set_terrain_navcell_data(Vector2i(x, y), _blocked_mask_for_terrain_navcell(Vector2i(x, y)), true):
				changed_count += 1
	return changed_count


func add_static_obstruction(shape: SimNavObstructionShapeStatic) -> int:
	if shape == null:
		push_error("[SimNavMap] Static obstruction shape cannot be null")
		return 0
	var tag := _next_obstruction_tag
	_next_obstruction_tag += 1
	shape.tag = tag
	shape._owning_nav_map_ref = weakref(self)
	_static_obstructions[tag] = shape
	_static_obstruction_index.add(tag, _shape_bounds_min(shape), _shape_bounds_max(shape))
	_mark_obstruction_shape_dirty(shape)
	return tag


func add_dynamic_obstruction(shape: SimNavObstructionShapeUnit) -> int:
	if shape == null:
		push_error("[SimNavMap] Dynamic obstruction shape cannot be null")
		return 0
	var tag := _next_obstruction_tag
	_next_obstruction_tag += 1
	shape.tag = tag
	shape._owning_nav_map_ref = weakref(self)
	_dynamic_obstructions[tag] = shape
	_dynamic_obstruction_index.add(tag, _shape_bounds_min(shape), _shape_bounds_max(shape))
	return tag


func remove_obstruction(tag: int) -> bool:
	if _static_obstructions.has(tag):
		var static_shape := _static_obstructions[tag] as SimNavObstructionShapeStatic
		_mark_obstruction_shape_dirty(static_shape)
		static_shape._owning_nav_map_ref = null
		_static_obstruction_index.remove(tag)
		_static_obstructions.erase(tag)
		return true
	if _dynamic_obstructions.has(tag):
		var dyn_shape := _dynamic_obstructions[tag] as SimNavObstructionShapeUnit
		dyn_shape._owning_nav_map_ref = null
		_dynamic_obstruction_index.remove(tag)
		_dynamic_obstructions.erase(tag)
		return true
	return false


func mark_obstruction_shape_dirty(shape: SimNavObstructionShape) -> void:
	if shape is SimNavObstructionShapeStatic:
		_mark_obstruction_shape_dirty(shape as SimNavObstructionShapeStatic)


func move_obstruction(tag: int, center: Vector2, rotation_rad: float = 0.0) -> bool:
	var shape := get_obstruction_shape(tag)
	if shape == null:
		return false
	if shape is SimNavObstructionShapeStatic:
		_mark_obstruction_shape_dirty(shape as SimNavObstructionShapeStatic)
	shape.center = center
	if shape is SimNavObstructionShapeStatic:
		(shape as SimNavObstructionShapeStatic).rotation_rad = rotation_rad
		_static_obstruction_index.move(tag, _shape_bounds_min(shape), _shape_bounds_max(shape))
		_mark_obstruction_shape_dirty(shape as SimNavObstructionShapeStatic)
	else:
		_dynamic_obstruction_index.move(tag, _shape_bounds_min(shape), _shape_bounds_max(shape))
	return true


func clear_dynamic_obstructions() -> void:
	for shape in _dynamic_obstructions.values():
		(shape as SimNavObstructionShapeUnit)._owning_nav_map_ref = null
	_dynamic_obstructions.clear()
	_dynamic_obstruction_index.clear()


func replace_dynamic_obstructions(shapes: Array[SimNavObstructionShapeUnit]) -> void:
	clear_dynamic_obstructions()
	for shape in shapes:
		add_dynamic_obstruction(shape)


func get_obstruction_shape(tag: int) -> SimNavObstructionShape:
	if _static_obstructions.has(tag):
		return _static_obstructions[tag] as SimNavObstructionShape
	if _dynamic_obstructions.has(tag):
		return _dynamic_obstructions[tag] as SimNavObstructionShape
	return null


func get_obstruction_shapes_in_range(center: Vector2, query_range: float) -> Array[SimNavObstructionShape]:
	var result: Array[SimNavObstructionShape] = []
	var query_min := center - Vector2(query_range, query_range)
	var query_max := center + Vector2(query_range, query_range)
	for tag in _static_obstruction_index.query(query_min, query_max):
		var static_shape := _static_obstructions.get(tag, null) as SimNavObstructionShape
		if static_shape != null and static_shape.center.distance_to(center) <= query_range + _shape_query_radius(static_shape):
			result.append(static_shape)
	for tag in _dynamic_obstruction_index.query(query_min, query_max):
		var unit_shape := _dynamic_obstructions.get(tag, null) as SimNavObstructionShape
		if unit_shape != null and unit_shape.center.distance_to(center) <= query_range + _shape_query_radius(unit_shape):
			result.append(unit_shape)
	result.sort_custom(func(a: SimNavObstructionShape, b: SimNavObstructionShape) -> bool:
		return a.tag < b.tag
	)
	return result


func get_obstruction_shapes_in_range_filtered(
	center: Vector2,
	query_range: float,
	filter: SimNavObstructionFilter
) -> Array[SimNavObstructionShape]:
	var result: Array[SimNavObstructionShape] = []
	var active_filter := filter if filter != null else SimNavObstructionFilter.new()
	for shape in get_obstruction_shapes_in_range(center, query_range):
		if active_filter.matches(shape):
			result.append(shape)
	return result


func get_static_obstruction_shapes() -> Array[SimNavObstructionShapeStatic]:
	var result: Array[SimNavObstructionShapeStatic] = []
	var tags: Array = _static_obstructions.keys()
	tags.sort()
	for tag in tags:
		result.append(_static_obstructions[tag] as SimNavObstructionShapeStatic)
	return result


func get_dynamic_obstruction_shapes() -> Array[SimNavObstructionShapeUnit]:
	var result: Array[SimNavObstructionShapeUnit] = []
	var tags: Array = _dynamic_obstructions.keys()
	tags.sort()
	for tag in tags:
		result.append(_dynamic_obstructions[tag] as SimNavObstructionShapeUnit)
	return result


func get_dirtiness_snapshot() -> Dictionary:
	var dirty_navcells := collect_dirty_navcells()
	var dirty_obstruction_navcells := collect_dirty_obstruction_navcells()
	return {
		"dirty_navcells": dirty_navcells,
		"dirty_navcell_count": dirty_navcells.size(),
		"dirty_obstruction_navcells": dirty_obstruction_navcells,
		"dirty_obstruction_navcell_count": dirty_obstruction_navcells.size(),
		"has_dirty_navcells": not dirty_navcells.is_empty(),
		"has_dirty_obstruction_navcells": not dirty_obstruction_navcells.is_empty(),
	}


func get_diagnostics() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"navcell_size": navcell_size,
		"origin": origin,
		"navcells_per_tile": navcells_per_tile,
		"passability_class_count": get_passability_classes().size(),
		"static_obstruction_count": _static_obstructions.size(),
		"dynamic_obstruction_count": _dynamic_obstructions.size(),
		"dirtiness": get_dirtiness_snapshot(),
	}


func rebuild_dirty() -> void:
	# Scan only the cells that could legitimately change — the union of every
	# registered static shape's clearance-expanded AABB plus any cells already
	# in the obstruction dirty list (which captures the old footprint of a
	# removed/moved shape, since add/remove/move/flag-mutation all dirty their
	# AABB before applying). Avoids the O(grid) sweep that the previous
	# full-rebuild path used and that dominated rasterize_static cost.
	var expansion := _passability_registry.max_clearance() + navcell_size
	var scan_cells: Dictionary = {}
	for coord in collect_dirty_obstruction_navcells():
		scan_cells[coord] = true
	for tag in _static_obstructions.keys():
		var shape := _static_obstructions[tag] as SimNavObstructionShapeStatic
		if shape == null:
			continue
		var min_cell := world_to_navcell(_shape_bounds_min(shape) - Vector2(expansion, expansion))
		var max_cell := world_to_navcell(_shape_bounds_max(shape) + Vector2(expansion, expansion))
		var sx := maxi(0, mini(min_cell.x, max_cell.x))
		var ex := mini(width - 1, maxi(min_cell.x, max_cell.x))
		var sy := maxi(0, mini(min_cell.y, max_cell.y))
		var ey := mini(height - 1, maxi(min_cell.y, max_cell.y))
		for y in range(sy, ey + 1):
			for x in range(sx, ex + 1):
				scan_cells[Vector2i(x, y)] = true
	for cell in scan_cells:
		if not is_valid_navcell(cell):
			continue
		var idx := _index(cell)
		var old_composed := int(_navcell_data[idx]) | int(_terrain_navcell_data[idx]) | int(_obstruction_navcell_data[idx])
		_obstruction_navcell_data[idx] = _blocked_mask_for_static_obstructions_at(cell)
		var new_composed := int(_navcell_data[idx]) | int(_terrain_navcell_data[idx]) | int(_obstruction_navcell_data[idx])
		if old_composed != new_composed:
			_dirtiness[idx] = 1
	clear_dirty_obstruction_navcells()


func rasterize_dirty_obstructions() -> int:
	if not has_dirty_obstruction_navcells():
		return 0
	var changed_count := 0
	for coord in collect_dirty_obstruction_navcells():
		var idx := _index(coord)
		var old_value := get_navcell_data(coord)
		_obstruction_navcell_data[idx] = _blocked_mask_for_static_obstructions_at(coord)
		var next_value := get_navcell_data(coord)
		if old_value != next_value:
			_dirtiness[idx] = 1
			changed_count += 1
	clear_dirty_obstruction_navcells()
	return changed_count


func navcell_center_world(coord: Vector2i) -> Vector2:
	return origin + Vector2(float(coord.x) + 0.5, float(coord.y) + 0.5) * navcell_size


func world_to_navcell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floorf((world_pos.x - origin.x) / navcell_size)),
		int(floorf((world_pos.y - origin.y) / navcell_size))
	)


func is_passable_navcell(coord: Vector2i, passability_mask: int) -> bool:
	if not is_valid_navcell(coord):
		return false
	return (get_navcell_data(coord) & passability_mask) == 0


func get_navcell_data(coord: Vector2i) -> int:
	if not is_valid_navcell(coord):
		return 0
	var idx := _index(coord)
	return int(_navcell_data[idx]) | int(_terrain_navcell_data[idx]) | int(_obstruction_navcell_data[idx])


func set_navcell_data(coord: Vector2i, value: int) -> void:
	if not is_valid_navcell(coord):
		return
	var idx := _index(coord)
	var old_value := get_navcell_data(coord)
	if int(_navcell_data[idx]) == value:
		return
	_navcell_data[idx] = value
	if old_value != get_navcell_data(coord):
		_dirtiness[idx] = 1


func or_navcell_data(coord: Vector2i, mask: int) -> void:
	if not is_valid_navcell(coord):
		return
	var idx := _index(coord)
	var next_value := int(_navcell_data[idx]) | mask
	if next_value == int(_navcell_data[idx]):
		return
	var old_value := get_navcell_data(coord)
	_navcell_data[idx] = next_value
	if old_value != get_navcell_data(coord):
		_dirtiness[idx] = 1


func and_navcell_data(coord: Vector2i, inverse_mask: int) -> void:
	if not is_valid_navcell(coord):
		return
	var idx := _index(coord)
	var next_value := int(_navcell_data[idx]) & ~inverse_mask
	if next_value == int(_navcell_data[idx]):
		return
	var old_value := get_navcell_data(coord)
	_navcell_data[idx] = next_value
	if old_value != get_navcell_data(coord):
		_dirtiness[idx] = 1


func mark_dirty_navcell(coord: Vector2i) -> void:
	if is_valid_navcell(coord):
		_dirtiness[_index(coord)] = 1


func is_dirty_navcell(coord: Vector2i) -> bool:
	if not is_valid_navcell(coord):
		return false
	return _dirtiness[_index(coord)] != 0


func collect_dirty_navcells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(height):
		var row_base := y * width
		for x in range(width):
			if _dirtiness[row_base + x] != 0:
				result.append(Vector2i(x, y))
	return result


func collect_dirty_obstruction_navcells() -> Array[Vector2i]:
	return _obstruction_dirty_cell_list.duplicate()


func has_dirty_navcells() -> bool:
	for value in _dirtiness:
		if value != 0:
			return true
	return false


func has_dirty_obstruction_navcells() -> bool:
	return not _obstruction_dirty_cell_list.is_empty()


func clear_dirty_navcells() -> void:
	for i in range(_dirtiness.size()):
		_dirtiness[i] = 0


func clear_dirty_obstruction_navcells() -> void:
	for cell in _obstruction_dirty_cell_list:
		_obstruction_dirtiness[_index(cell)] = 0
	_obstruction_dirty_cell_list.clear()


func is_valid_navcell(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < width and coord.y < height


func _rasterize_static_obstruction(shape: SimNavObstructionShapeStatic, mark_dirty: bool = true) -> void:
	# Clip the per-cell containment scan to the shape's clearance-expanded AABB
	# instead of walking the entire navcell grid. The expansion mirrors what
	# _mark_obstruction_shape_dirty uses, so the raster iterates exactly the
	# cells the dirty pass already considers (and leaves a navcell of slack for
	# any future per-class clearance-extension radius).
	var expansion := _passability_registry.max_clearance() + navcell_size
	var min_cell := world_to_navcell(_shape_bounds_min(shape) - Vector2(expansion, expansion))
	var max_cell := world_to_navcell(_shape_bounds_max(shape) + Vector2(expansion, expansion))
	var start_x := maxi(0, mini(min_cell.x, max_cell.x))
	var end_x := mini(width - 1, maxi(min_cell.x, max_cell.x))
	var start_y := maxi(0, mini(min_cell.y, max_cell.y))
	var end_y := mini(height - 1, maxi(min_cell.y, max_cell.y))
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var coord := Vector2i(x, y)
			var center_world := navcell_center_world(coord)
			var blocked_mask := _blocked_mask_for_point(shape, center_world)
			if blocked_mask != 0:
				_or_obstruction_navcell_data_internal(coord, blocked_mask, mark_dirty)


func _blocked_mask_for_point(shape: SimNavObstructionShapeStatic, point: Vector2) -> int:
	if not is_inside_playable_bounds(point):
		return 0
	var result := 0
	for config in _passability_registry.get_classes():
		if not config.affects_pathfinding:
			continue
		if shape.contains_point_with_clearance(point, config.clearance):
			result |= 1 << config.bit_index
	return result


func set_bounds(x0: float, z0: float, x1: float, z1: float) -> void:
	_playable_bounds_min = Vector2(minf(x0, x1), minf(z0, z1))
	_playable_bounds_max = Vector2(maxf(x0, x1), maxf(z0, z1))
	_mark_all_static_obstructions_dirty()


func get_playable_bounds_min() -> Vector2:
	return _playable_bounds_min


func get_playable_bounds_max() -> Vector2:
	return _playable_bounds_max


func is_inside_playable_bounds(world_pos: Vector2) -> bool:
	return (
		world_pos.x >= _playable_bounds_min.x
		and world_pos.y >= _playable_bounds_min.y
		and world_pos.x <= _playable_bounds_max.x
		and world_pos.y <= _playable_bounds_max.y
	)


func _clear_navcell_data(mark_dirty: bool = false) -> void:
	for i in range(_navcell_data.size()):
		if mark_dirty and int(_navcell_data[i]) != 0:
			_dirtiness[i] = 1
		_navcell_data[i] = 0


func _clear_obstruction_navcell_data() -> void:
	for i in range(_obstruction_navcell_data.size()):
		_obstruction_navcell_data[i] = 0


func _rebuild_terrain_tile_passability(tile: Vector2i) -> int:
	if not _terrain_tile_map.is_valid_tile(tile):
		return 0
	var changed_count := 0
	var start := _terrain_tile_map.tile_origin_navcell(tile)
	var terrain_padding := _clearance_navcell_padding(_passability_registry.max_clearance())
	var start_x := maxi(0, start.x - terrain_padding)
	var start_y := maxi(0, start.y - terrain_padding)
	var end_x := mini(width - 1, start.x + navcells_per_tile - 1 + terrain_padding)
	var end_y := mini(height - 1, start.y + navcells_per_tile - 1 + terrain_padding)
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var coord := Vector2i(x, y)
			if _set_terrain_navcell_data(coord, _blocked_mask_for_terrain_navcell(coord), true):
				changed_count += 1
	return changed_count


func _set_terrain_navcell_data(coord: Vector2i, value: int, mark_dirty: bool) -> bool:
	if not is_valid_navcell(coord):
		return false
	var idx := _index(coord)
	if int(_terrain_navcell_data[idx]) == value:
		return false
	var old_value := get_navcell_data(coord)
	_terrain_navcell_data[idx] = value
	if mark_dirty and old_value != get_navcell_data(coord):
		_dirtiness[idx] = 1
		return true
	return false


func _blocked_mask_for_terrain_navcell(coord: Vector2i) -> int:
	var result := 0
	for config in _passability_registry.get_classes():
		if _terrain_blocks_navcell_for_class(coord, config):
			result |= 1 << config.bit_index
	return result


func _blocked_mask_for_terrain_data(terrain_data: int) -> int:
	var result := 0
	for config in _passability_registry.get_classes():
		if _terrain_data_blocks_class(terrain_data, config):
			result |= 1 << config.bit_index
	return result


func _terrain_blocks_navcell_for_class(coord: Vector2i, config: SimNavPassabilityClassConfig) -> bool:
	if not is_valid_navcell(coord):
		return false
	if not _class_uses_terrain_mask(config):
		return false
	if config.clearance <= 0.0:
		return _terrain_data_blocks_class(get_navcell_terrain_data(coord), config)
	var center_world := navcell_center_world(coord)
	var padding := _clearance_navcell_padding(config.clearance)
	var start_x := maxi(0, coord.x - padding)
	var end_x := mini(width - 1, coord.x + padding)
	var start_y := maxi(0, coord.y - padding)
	var end_y := mini(height - 1, coord.y + padding)
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var terrain_coord := Vector2i(x, y)
			if not _terrain_data_blocks_class(get_navcell_terrain_data(terrain_coord), config):
				continue
			if _point_overlaps_navcell_rect_with_clearance(center_world, terrain_coord, config.clearance):
				return true
	return false


func _terrain_data_blocks_class(terrain_data: int, config: SimNavPassabilityClassConfig) -> bool:
	if not _class_uses_terrain_mask(config):
		return false
	return (terrain_data & config.terrain_mask) != 0


func _class_uses_terrain_mask(config: SimNavPassabilityClassConfig) -> bool:
	if config == null:
		return false
	if not config.affects_pathfinding:
		return false
	return config.terrain_mask != 0


func _point_overlaps_navcell_rect_with_clearance(point: Vector2, coord: Vector2i, clearance: float) -> bool:
	var min_world := origin + Vector2(float(coord.x), float(coord.y)) * navcell_size
	var max_world := min_world + Vector2(navcell_size, navcell_size)
	var dx := 0.0
	if point.x < min_world.x:
		dx = min_world.x - point.x
	elif point.x > max_world.x:
		dx = point.x - max_world.x
	var dy := 0.0
	if point.y < min_world.y:
		dy = min_world.y - point.y
	elif point.y > max_world.y:
		dy = point.y - max_world.y
	return dx * dx + dy * dy <= clearance * clearance + 0.001


func _clearance_navcell_padding(clearance: float) -> int:
	if clearance <= 0.0:
		return 0
	return int(ceil(clearance / maxf(navcell_size, 0.001))) + 1


func _or_obstruction_navcell_data_internal(coord: Vector2i, mask: int, mark_dirty: bool) -> void:
	if not is_valid_navcell(coord):
		return
	var idx := _index(coord)
	var old_value := get_navcell_data(coord)
	var next_obstruction_value := int(_obstruction_navcell_data[idx]) | mask
	if next_obstruction_value == int(_obstruction_navcell_data[idx]):
		return
	_obstruction_navcell_data[idx] = next_obstruction_value
	if mark_dirty and old_value != get_navcell_data(coord):
		_dirtiness[idx] = 1


func _mark_rebuild_changes_dirty(old_data: PackedInt32Array) -> void:
	for i in range(_navcell_data.size()):
		var next_value := int(_navcell_data[i]) | int(_terrain_navcell_data[i]) | int(_obstruction_navcell_data[i])
		if int(old_data[i]) != next_value:
			_dirtiness[i] = 1


func _compose_navcell_data() -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(_navcell_data.size())
	for i in range(_navcell_data.size()):
		result[i] = int(_navcell_data[i]) | int(_terrain_navcell_data[i]) | int(_obstruction_navcell_data[i])
	return result


func _blocked_mask_for_static_obstructions_at(coord: Vector2i) -> int:
	var point := navcell_center_world(coord)
	var query_radius := _passability_registry.max_clearance() + navcell_size
	var result := 0
	for tag in _static_obstruction_index.query(point - Vector2(query_radius, query_radius), point + Vector2(query_radius, query_radius)):
		var shape := _static_obstructions.get(tag, null) as SimNavObstructionShapeStatic
		if shape == null:
			continue
		if (shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		result |= _blocked_mask_for_point(shape, point)
	return result


func _mark_all_static_obstructions_dirty() -> void:
	for shape in get_static_obstruction_shapes():
		_mark_obstruction_shape_dirty(shape)


func _mark_obstruction_shape_dirty(shape: SimNavObstructionShapeStatic) -> void:
	if shape == null:
		return
	var expansion := _passability_registry.max_clearance() + navcell_size
	var min_cell := world_to_navcell(_shape_bounds_min(shape) - Vector2(expansion, expansion))
	var max_cell := world_to_navcell(_shape_bounds_max(shape) + Vector2(expansion, expansion))
	var start_x := maxi(0, mini(min_cell.x, max_cell.x))
	var end_x := mini(width - 1, maxi(min_cell.x, max_cell.x))
	var start_y := maxi(0, mini(min_cell.y, max_cell.y))
	var end_y := mini(height - 1, maxi(min_cell.y, max_cell.y))
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var coord := Vector2i(x, y)
			var idx := _index(coord)
			if _obstruction_dirtiness[idx] == 0:
				_obstruction_dirtiness[idx] = 1
				_obstruction_dirty_cell_list.append(coord)


func _shape_query_radius(shape: SimNavObstructionShape) -> float:
	if shape is SimNavObstructionShapeStatic:
		var static_shape := shape as SimNavObstructionShapeStatic
		return sqrt(static_shape.width * static_shape.width + static_shape.height * static_shape.height) * 0.5
	if shape is SimNavObstructionShapeUnit:
		return (shape as SimNavObstructionShapeUnit).clearance
	return 0.0


func _shape_bounds_min(shape: SimNavObstructionShape) -> Vector2:
	var radius := _shape_query_radius(shape)
	return shape.center - Vector2(radius, radius)


func _shape_bounds_max(shape: SimNavObstructionShape) -> Vector2:
	var radius := _shape_query_radius(shape)
	return shape.center + Vector2(radius, radius)


func _default_spatial_cell_size() -> float:
	return maxf(navcell_size * 8.0, 16.0)


func _index(coord: Vector2i) -> int:
	return coord.y * width + coord.x
