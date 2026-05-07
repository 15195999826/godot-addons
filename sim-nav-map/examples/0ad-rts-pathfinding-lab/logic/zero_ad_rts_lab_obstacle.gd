class_name ZeroAdRtsLabObstacle
extends RefCounted


var id: String = ""
var center: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2.ZERO


func _init(p_id: String = "", p_center: Vector2 = Vector2.ZERO, p_size: Vector2 = Vector2.ZERO) -> void:
	id = p_id
	center = p_center
	size = p_size


func get_rect() -> Rect2:
	return Rect2(center - size * 0.5, size)


func contains_point_with_clearance(point: Vector2, clearance: float) -> bool:
	return get_rect().grow(maxf(clearance, 0.0)).has_point(point)

