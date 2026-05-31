class_name SimNavObstructionShape
extends RefCounted


enum Type {
	STATIC,
	UNIT,
}

var type: Type = Type.STATIC
var tag: int = 0
var entity_id: String = ""
var center: Vector2 = Vector2.ZERO
var flags: int = 0: set = _set_flags
var control_group: String = ""
var control_group_2: String = ""

# Weak back-reference to the SimNavMap this shape is registered with. Set by
# nav_map.add_*_obstruction() and cleared by remove_obstruction(). Lets the
# `flags` setter dirty-propagate when callers mutate `shape.flags = ...`
# directly instead of going through the manager API.
var _owning_nav_map_ref: WeakRef = null


func _set_flags(value: int) -> void:
	if flags == value:
		return
	flags = value
	if _owning_nav_map_ref == null:
		return
	var nav_map := _owning_nav_map_ref.get_ref() as SimNavMap
	if nav_map == null:
		return
	if type == Type.STATIC:
		nav_map.mark_obstruction_shape_dirty(self)


func contains_point(_point: Vector2) -> bool:
	return false
