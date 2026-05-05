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
var _static_obstructions: Dictionary = {}
var _dynamic_obstructions: Dictionary = {}
var _static_obstruction_index: SimNavSpatialIndex = null
var _dynamic_obstruction_index: SimNavSpatialIndex = null
var _next_obstruction_tag: int = 1


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
	_dynamic_obstructions[tag] = shape
	_dynamic_obstruction_index.add(tag, _shape_bounds_min(shape), _shape_bounds_max(shape))
	return tag


func remove_obstruction(tag: int) -> bool:
	if _static_obstructions.has(tag):
		var static_shape := _static_obstructions[tag] as SimNavObstructionShapeStatic
		_mark_obstruction_shape_dirty(static_shape)
		_static_obstruction_index.remove(tag)
		_static_obstructions.erase(tag)
		return true
	if _dynamic_obstructions.has(tag):
		_dynamic_obstruction_index.remove(tag)
		_dynamic_obstructions.erase(tag)
		return true
	return false


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


func rebuild_dirty() -> void:
	var old_data := _compose_navcell_data()
	_clear_obstruction_navcell_data()
	for tag in _static_obstructions.keys():
		var shape := _static_obstructions[tag] as SimNavObstructionShapeStatic
		if shape == null:
			continue
		if (shape.flags & SimNavObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		_rasterize_static_obstruction(shape, false)
	_mark_rebuild_changes_dirty(old_data)
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
	var result: Array[Vector2i] = []
	for y in range(height):
		var row_base := y * width
		for x in range(width):
			if _obstruction_dirtiness[row_base + x] != 0:
				result.append(Vector2i(x, y))
	return result


func has_dirty_navcells() -> bool:
	for value in _dirtiness:
		if value != 0:
			return true
	return false


func has_dirty_obstruction_navcells() -> bool:
	for value in _obstruction_dirtiness:
		if value != 0:
			return true
	return false


func clear_dirty_navcells() -> void:
	for i in range(_dirtiness.size()):
		_dirtiness[i] = 0


func clear_dirty_obstruction_navcells() -> void:
	for i in range(_obstruction_dirtiness.size()):
		_obstruction_dirtiness[i] = 0


func is_valid_navcell(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < width and coord.y < height


func _rasterize_static_obstruction(shape: SimNavObstructionShapeStatic, mark_dirty: bool = true) -> void:
	for y in range(height):
		for x in range(width):
			var coord := Vector2i(x, y)
			var center_world := navcell_center_world(coord)
			var blocked_mask := _blocked_mask_for_point(shape, center_world)
			if blocked_mask != 0:
				_or_obstruction_navcell_data_internal(coord, blocked_mask, mark_dirty)


func _blocked_mask_for_point(shape: SimNavObstructionShapeStatic, point: Vector2) -> int:
	var result := 0
	for config in _passability_registry.get_classes():
		if not config.affects_pathfinding:
			continue
		if shape.contains_point_with_clearance(point, config.clearance):
			result |= 1 << config.bit_index
	return result


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
	var end_x := mini(width - 1, start.x + navcells_per_tile - 1)
	var end_y := mini(height - 1, start.y + navcells_per_tile - 1)
	for y in range(start.y, end_y + 1):
		for x in range(start.x, end_x + 1):
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
	return _blocked_mask_for_terrain_data(get_navcell_terrain_data(coord))


func _blocked_mask_for_terrain_data(terrain_data: int) -> int:
	var result := 0
	for config in _passability_registry.get_classes():
		if not config.affects_pathfinding:
			continue
		if config.terrain_mask == 0:
			continue
		if (terrain_data & config.terrain_mask) != 0:
			result |= 1 << config.bit_index
	return result


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
			_obstruction_dirtiness[_index(Vector2i(x, y))] = 1


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
