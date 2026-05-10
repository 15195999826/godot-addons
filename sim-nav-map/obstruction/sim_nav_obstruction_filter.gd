class_name SimNavObstructionFilter
extends RefCounted


var include_static: bool = true
var include_units: bool = true
var include_moving_units: bool = true
var include_stationary_units: bool = true
var ignored_tag: int = 0
var ignored_tags: Array[int] = []
var ignored_entity_id: String = ""
var ignored_entity_ids: Array[String] = []
var control_group: String = ""
var ignored_control_groups: Array[String] = []
var required_flags: int = 0
var excluded_flags: int = 0


static func all() -> SimNavObstructionFilter:
	return SimNavObstructionFilter.new()


static func for_short_path(avoid_moving_units: bool = true, p_control_group: String = "") -> SimNavObstructionFilter:
	var filter := SimNavObstructionFilter.new()
	filter.include_moving_units = avoid_moving_units
	filter.control_group = p_control_group
	return filter


static func units_only(avoid_moving_units: bool = true, p_control_group: String = "") -> SimNavObstructionFilter:
	var filter := SimNavObstructionFilter.for_short_path(avoid_moving_units, p_control_group)
	filter.include_static = false
	filter.include_units = true
	return filter


func matches(shape: SimNavObstructionShape) -> bool:
	if shape == null:
		return false
	if shape is SimNavObstructionShapeStatic and not include_static:
		return false
	if shape is SimNavObstructionShapeUnit:
		if not include_units:
			return false
		var unit_shape := shape as SimNavObstructionShapeUnit
		var is_moving := unit_shape.moving or (unit_shape.flags & SimNavObstructionFlags.MOVING) != 0
		if is_moving and not include_moving_units:
			return false
		if not is_moving and not include_stationary_units:
			return false
	if ignored_tag > 0 and shape.tag == ignored_tag:
		return false
	if ignored_tags.has(shape.tag):
		return false
	if ignored_entity_id != "" and shape.entity_id == ignored_entity_id:
		return false
	if ignored_entity_ids.has(shape.entity_id):
		return false
	if _shape_matches_control_group(shape, control_group):
		return false
	for group in ignored_control_groups:
		if _shape_matches_control_group(shape, group):
			return false
	if required_flags != 0 and (shape.flags & required_flags) != required_flags:
		return false
	if excluded_flags != 0 and (shape.flags & excluded_flags) != 0:
		return false
	return true


func clone() -> SimNavObstructionFilter:
	var cloned_filter := SimNavObstructionFilter.new()
	cloned_filter.include_static = include_static
	cloned_filter.include_units = include_units
	cloned_filter.include_moving_units = include_moving_units
	cloned_filter.include_stationary_units = include_stationary_units
	cloned_filter.ignored_tag = ignored_tag
	cloned_filter.ignored_tags = ignored_tags.duplicate()
	cloned_filter.ignored_entity_id = ignored_entity_id
	cloned_filter.ignored_entity_ids = ignored_entity_ids.duplicate()
	cloned_filter.control_group = control_group
	cloned_filter.ignored_control_groups = ignored_control_groups.duplicate()
	cloned_filter.required_flags = required_flags
	cloned_filter.excluded_flags = excluded_flags
	return cloned_filter


func _shape_matches_control_group(shape: SimNavObstructionShape, group: String) -> bool:
	if group == "":
		return false
	return shape.control_group == group or shape.control_group_2 == group
