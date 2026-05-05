class_name SimNavObstructionShapeStatic
extends SimNavObstructionShape


var width: float = 0.0
var height: float = 0.0
var rotation_rad: float = 0.0


func _init() -> void:
	type = Type.STATIC


func get_corners() -> Array[Vector2]:
	var u := _axis_u()
	var v := _axis_v()
	var hw := width * 0.5
	var hh := height * 0.5
	return [
		center + u * hw + v * hh,
		center + u * hw - v * hh,
		center - u * hw - v * hh,
		center - u * hw + v * hh,
	]


func get_axes() -> Array[Vector2]:
	return [_axis_u(), _axis_v()]


func contains_point(point: Vector2) -> bool:
	var delta := point - center
	var u := _axis_u()
	var v := _axis_v()
	var local_x := delta.dot(u)
	var local_y := delta.dot(v)
	return absf(local_x) <= width * 0.5 and absf(local_y) <= height * 0.5


func contains_point_with_clearance(point: Vector2, clearance: float) -> bool:
	var delta := point - center
	var u := _axis_u()
	var v := _axis_v()
	var local_x := delta.dot(u)
	var local_y := delta.dot(v)
	return absf(local_x) <= width * 0.5 + clearance and absf(local_y) <= height * 0.5 + clearance


func _axis_u() -> Vector2:
	return Vector2(cos(rotation_rad), sin(rotation_rad))


func _axis_v() -> Vector2:
	return Vector2(-sin(rotation_rad), cos(rotation_rad))
