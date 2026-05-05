class_name RtsPathfindingLabObstacle
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


func get_inflated_rect(amount: float) -> Rect2:
	var rect := get_rect()
	var pad := Vector2(amount, amount)
	return Rect2(rect.position - pad, rect.size + pad * 2.0)


func get_inflated_corners(amount: float, outset: float) -> Array[Vector2]:
	var rect := get_inflated_rect(amount)
	var base: Array[Vector2] = [
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		rect.position + rect.size,
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	]
	var result: Array[Vector2] = []
	for point in base:
		var dir := point - center
		if dir.length_squared() <= 0.0001:
			result.append(point)
		else:
			result.append(point + dir.normalized() * outset)
	return result

