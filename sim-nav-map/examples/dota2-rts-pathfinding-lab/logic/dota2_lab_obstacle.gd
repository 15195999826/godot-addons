class_name Dota2LabObstacle
extends RefCounted


var id: String = ""
var center: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2(64.0, 64.0)
var rotation_rad: float = 0.0


func _init(
	p_id: String = "",
	p_center: Vector2 = Vector2.ZERO,
	p_size: Vector2 = Vector2(64.0, 64.0),
	p_rotation_rad: float = 0.0
) -> void:
	id = p_id
	center = p_center
	size = p_size
	rotation_rad = p_rotation_rad


func contains_point_with_clearance(point: Vector2, clearance: float) -> bool:
	# Axis-aligned only (rotation_rad always 0 for now). If rotation is
	# introduced later, project via cos/sin like SimNavObstructionShapeStatic.
	var half := size * 0.5 + Vector2(clearance, clearance)
	var delta := point - center
	return abs(delta.x) <= half.x and abs(delta.y) <= half.y
