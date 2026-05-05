class_name RtsPathfindingLabUnit
extends RefCounted


var id: String = ""
var group_id: String = ""
var position: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var radius: float = 11.0
var speed: float = 95.0
var mobile: bool = true
var blocks_pathfinding: bool = true
var arrived: bool = false
var has_move_order: bool = false
var path: Array[Vector2] = []
var path_index: int = 0
var trace: Array[Vector2] = []
var replan_timer: float = 0.0


func _init(
	p_id: String = "",
	p_group_id: String = "",
	p_position: Vector2 = Vector2.ZERO,
	p_radius: float = 11.0,
	p_speed: float = 95.0,
	p_mobile: bool = true
) -> void:
	id = p_id
	group_id = p_group_id
	position = p_position
	target = p_position
	radius = p_radius
	speed = p_speed
	mobile = p_mobile
	trace = [p_position]


func set_path(points: Array[Vector2]) -> void:
	path = points.duplicate()
	path_index = 0
	arrived = path.is_empty() and position.distance_to(target) <= radius
	if arrived:
		has_move_order = false


func current_waypoint() -> Vector2:
	if path_index >= path.size():
		return target
	return path[path_index]


func append_trace_point() -> void:
	if trace.is_empty() or trace.back().distance_to(position) >= 4.0:
		trace.append(position)
