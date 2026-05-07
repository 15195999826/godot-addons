class_name ZeroAdRtsLabUnit
extends RefCounted


var id: String = ""
var group_id: String = ""
var position: Vector2 = Vector2.ZERO
var radius: float = 10.0
var speed: float = 90.0
var mobile: bool = true
var blocks_pathfinding: bool = true
var target: Vector2 = Vector2.ZERO
var path_target: Vector2 = Vector2.ZERO
var has_move_order: bool = false
var arrived: bool = true
var was_obstructed: bool = false
var failed_movements: int = 0
var long_path: SimNavWaypointPath = SimNavWaypointPath.new()
var short_path: SimNavWaypointPath = SimNavWaypointPath.new()
var trace: PackedVector2Array = PackedVector2Array()
var pending_long_ticket: int = 0
var pending_short_ticket: int = 0
var short_repath_cooldown: float = 0.0


func _init(
	p_id: String = "",
	p_group_id: String = "",
	p_position: Vector2 = Vector2.ZERO,
	p_radius: float = 10.0,
	p_speed: float = 90.0,
	p_mobile: bool = true
) -> void:
	id = p_id
	group_id = p_group_id
	position = p_position
	target = p_position
	path_target = p_position
	radius = p_radius
	speed = p_speed
	mobile = p_mobile


func begin_move_order(goal: Vector2) -> void:
	target = goal
	path_target = goal
	has_move_order = true
	arrived = false
	was_obstructed = false
	failed_movements = 0
	long_path = SimNavWaypointPath.new()
	short_path = SimNavWaypointPath.new()
	pending_long_ticket = 0
	pending_short_ticket = 0
	short_repath_cooldown = 0.0


func finish_move_order() -> void:
	has_move_order = false
	arrived = true
	was_obstructed = false
	failed_movements = 0
	long_path = SimNavWaypointPath.new()
	short_path = SimNavWaypointPath.new()
	path_target = position
	pending_long_ticket = 0
	pending_short_ticket = 0
	short_repath_cooldown = 0.0


func active_path() -> SimNavWaypointPath:
	if short_path != null and not short_path.is_empty():
		return short_path
	return long_path


func has_path() -> bool:
	var path := active_path()
	return path != null and not path.is_empty()


func current_waypoint() -> Vector2:
	var path := active_path()
	if path == null or path.is_empty():
		return path_target
	return path.back()


func consume_current_waypoint() -> void:
	var path := active_path()
	if path == null or path.is_empty():
		return
	path.pop_back()


func remember_position() -> void:
	trace.append(position)
	if trace.size() > 80:
		trace.remove_at(0)
