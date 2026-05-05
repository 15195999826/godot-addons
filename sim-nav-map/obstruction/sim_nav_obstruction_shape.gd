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
var flags: int = 0
var control_group: String = ""
var control_group_2: String = ""


func contains_point(_point: Vector2) -> bool:
	return false
