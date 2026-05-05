class_name SimNavObstructionShapeUnit
extends SimNavObstructionShape


var clearance: float = 0.0
var moving: bool = false


func _init() -> void:
	type = Type.UNIT


func contains_point(point: Vector2) -> bool:
	return center.distance_to(point) <= clearance
