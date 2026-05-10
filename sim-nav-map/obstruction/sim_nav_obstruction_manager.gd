class_name SimNavObstructionManager
extends RefCounted


var _nav_map: SimNavMap = null


func _init(nav_map: SimNavMap = null) -> void:
	_nav_map = nav_map


func add_static_shape(
	entity_id: String,
	center: Vector2,
	rotation_rad: float,
	width: float,
	height: float,
	flags: int,
	control_group: String = "",
	control_group_2: String = ""
) -> int:
	if _nav_map == null:
		push_error("[SimNavObstructionManager] add_static_shape: nav_map is null")
		return 0
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = entity_id
	shape.center = center
	shape.rotation_rad = rotation_rad
	shape.width = width
	shape.height = height
	shape.flags = flags
	shape.control_group = control_group
	shape.control_group_2 = control_group_2
	return _nav_map.add_static_obstruction(shape)


func add_unit_shape(
	entity_id: String,
	center: Vector2,
	clearance: float,
	flags: int,
	control_group: String = ""
) -> int:
	if _nav_map == null:
		push_error("[SimNavObstructionManager] add_unit_shape: nav_map is null")
		return 0
	var shape := SimNavObstructionShapeUnit.new()
	shape.entity_id = entity_id
	shape.center = center
	shape.clearance = clearance
	shape.flags = flags
	shape.control_group = control_group
	shape.moving = (flags & SimNavObstructionFlags.MOVING) != 0
	return _nav_map.add_dynamic_obstruction(shape)


func remove_shape(tag: int) -> bool:
	if _nav_map == null:
		return false
	return _nav_map.remove_obstruction(tag)


func move_shape(tag: int, center: Vector2, rotation_rad: float = 0.0) -> bool:
	if _nav_map == null:
		return false
	return _nav_map.move_obstruction(tag, center, rotation_rad)


func set_unit_moving_flag(tag: int, moving: bool) -> bool:
	var shape := get_shape(tag)
	if not (shape is SimNavObstructionShapeUnit):
		return false
	var unit_shape := shape as SimNavObstructionShapeUnit
	unit_shape.moving = moving
	if moving:
		unit_shape.flags = unit_shape.flags | SimNavObstructionFlags.MOVING
	else:
		unit_shape.flags = unit_shape.flags & ~SimNavObstructionFlags.MOVING
	return true


func set_control_group(tag: int, control_group: String, control_group_2: String = "") -> bool:
	var shape := get_shape(tag)
	if shape == null:
		return false
	shape.control_group = control_group
	shape.control_group_2 = control_group_2
	return true


func set_static_flags(tag: int, flags: int) -> bool:
	var shape := get_shape(tag)
	if not (shape is SimNavObstructionShapeStatic):
		return false
	shape.flags = flags
	return true


func set_unit_flags(tag: int, flags: int) -> bool:
	var shape := get_shape(tag)
	if not (shape is SimNavObstructionShapeUnit):
		return false
	var unit_shape := shape as SimNavObstructionShapeUnit
	unit_shape.flags = flags
	unit_shape.moving = (flags & SimNavObstructionFlags.MOVING) != 0
	return true


func get_shape(tag: int) -> SimNavObstructionShape:
	if _nav_map == null:
		return null
	return _nav_map.get_obstruction_shape(tag)


func get_obstructions_in_range(center: Vector2, query_range: float) -> Array[SimNavObstructionShape]:
	if _nav_map == null:
		return []
	return _nav_map.get_obstruction_shapes_in_range(center, query_range)


func get_obstructions_in_range_filtered(
	center: Vector2,
	query_range: float,
	filter: SimNavObstructionFilter
) -> Array[SimNavObstructionShape]:
	if _nav_map == null:
		return []
	return _nav_map.get_obstruction_shapes_in_range_filtered(center, query_range, filter)


func rasterize() -> void:
	if _nav_map != null:
		_nav_map.rasterize_dirty_obstructions()
