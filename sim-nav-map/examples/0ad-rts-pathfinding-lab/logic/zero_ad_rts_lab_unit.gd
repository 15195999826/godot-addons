class_name ZeroAdRtsLabUnit
extends RefCounted


const MoveOrderScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_move_order.gd")
const MotionUpdateScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_motion_update.gd")

var id: String = ""
var group_id: String = ""
var control_group_id: String = ""
var position: Vector2 = Vector2.ZERO
var radius: float = 10.0
var speed: float = 90.0
var mobile: bool = true
var blocks_pathfinding: bool = true
var target: Vector2 = Vector2.ZERO
var path_target: Vector2 = Vector2.ZERO
var has_move_order: bool = false
var arrived: bool = true
var move_failed: bool = false
var was_obstructed: bool = false
var obstruction_state: String = ""
var failed_movements: int = 0
var pushing_pressure: int = 0
var follow_known_imperfect_path_countdown: int = 0
var long_path: SimNavWaypointPath = SimNavWaypointPath.new()
var short_path: SimNavWaypointPath = SimNavWaypointPath.new()
var trace: PackedVector2Array = PackedVector2Array()
var pending_long_ticket: int = 0
var pending_short_ticket: int = 0
var short_repath_cooldown: float = 0.0
var current_order: RefCounted = null
var last_order: RefCounted = null
var _next_order_id: int = 1


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


func begin_move_order(goal: Vector2, tick: int = 0) -> void:
	var order: RefCounted = MoveOrderScript.new(_next_order_id, goal, tick)
	_next_order_id += 1
	current_order = order
	target = goal
	path_target = goal
	has_move_order = true
	arrived = false
	move_failed = false
	was_obstructed = false
	obstruction_state = ""
	failed_movements = 0
	follow_known_imperfect_path_countdown = 0
	long_path = SimNavWaypointPath.new()
	short_path = SimNavWaypointPath.new()
	pending_long_ticket = 0
	pending_short_ticket = 0
	short_repath_cooldown = 0.0


func finish_move_order(tick: int = 0) -> void:
	if current_order != null:
		current_order.complete(tick)
		last_order = current_order
		current_order = null
	has_move_order = false
	arrived = true
	move_failed = false
	was_obstructed = false
	obstruction_state = ""
	failed_movements = 0
	follow_known_imperfect_path_countdown = 0
	long_path = SimNavWaypointPath.new()
	short_path = SimNavWaypointPath.new()
	path_target = position
	pending_long_ticket = 0
	pending_short_ticket = 0
	short_repath_cooldown = 0.0


func fail_move_order(tick: int = 0, reason: String = "") -> void:
	if current_order != null:
		current_order.fail(tick, reason)
		last_order = current_order
		current_order = null
	has_move_order = false
	arrived = false
	move_failed = true
	was_obstructed = true
	obstruction_state = "likely_failure"
	failed_movements = 0
	follow_known_imperfect_path_countdown = 0
	long_path = SimNavWaypointPath.new()
	short_path = SimNavWaypointPath.new()
	pending_long_ticket = 0
	pending_short_ticket = 0
	short_repath_cooldown = 0.0


func active_order_id() -> int:
	if current_order == null:
		return 0
	return current_order.order_id


func note_order_metric(metric_name: String, amount: int = 1) -> void:
	if current_order != null:
		current_order.note_metric(metric_name, amount)


func on_motion_update(update: RefCounted) -> void:
	if update == null:
		return
	if update.order_id != 0 and active_order_id() != 0 and update.order_id != active_order_id():
		return
	match update.update_type:
		MotionUpdateScript.TYPE_CLEAR:
			was_obstructed = false
			obstruction_state = ""
		MotionUpdateScript.TYPE_REACHED_GOAL:
			finish_move_order(update.tick)
		MotionUpdateScript.TYPE_OBSTRUCTED:
			was_obstructed = true
			obstruction_state = "obstructed"
		MotionUpdateScript.TYPE_VERY_OBSTRUCTED:
			was_obstructed = true
			obstruction_state = "very_obstructed"
		MotionUpdateScript.TYPE_KNOWN_IMPERFECT:
			was_obstructed = true
			obstruction_state = "known_imperfect_path"
		MotionUpdateScript.TYPE_LIKELY_FAILURE:
			fail_move_order(update.tick, update.reason)


func current_order_snapshot() -> Dictionary:
	if current_order == null:
		return {}
	return current_order.to_snapshot()


func last_order_snapshot() -> Dictionary:
	if last_order == null:
		return {}
	return last_order.to_snapshot()


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
