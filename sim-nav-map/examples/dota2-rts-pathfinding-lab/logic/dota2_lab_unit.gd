class_name Dota2LabUnit
extends RefCounted


const MoveOrderScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_move_order.gd")

# Motion FSM states. See docs/design-notes/motion-controller-design.md §3.1.
const STATE_IDLE := "IDLE"
const STATE_WAITING_LONG := "WAITING_LONG"
const STATE_FOLLOWING := "FOLLOWING"
const STATE_WAITING_SHORT := "WAITING_SHORT"
const STATE_FAILED := "FAILED"


var id: String = ""
var group_id: String = ""
var position: Vector2 = Vector2.ZERO
var radius: float = 10.0
var speed: float = 90.0
var mobile: bool = true
var blocks_pathfinding: bool = true

# Motion FSM fields (see design §3).
var state: String = STATE_IDLE
var move_target: Vector2 = Vector2.ZERO
var path: SimNavWaypointPath = SimNavWaypointPath.new()
var retry_count: int = 0
var pending_long_ticket: int = 0
var pending_short_ticket: int = 0

# Order tracking.
var current_order: RefCounted = null
var last_order: RefCounted = null
var _next_order_id: int = 1

# Frontend / debug.
var trace: PackedVector2Array = PackedVector2Array()


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
	move_target = p_position
	radius = p_radius
	speed = p_speed
	mobile = p_mobile


func begin_move_order(target: Vector2, tick: int) -> int:
	var order: RefCounted = MoveOrderScript.new(_next_order_id, target, tick)
	_next_order_id += 1
	current_order = order
	move_target = target
	state = STATE_IDLE
	path = SimNavWaypointPath.new()
	retry_count = 0
	pending_long_ticket = 0
	pending_short_ticket = 0
	return order.order_id


func complete_order(tick: int) -> void:
	if current_order != null:
		current_order.complete(tick)
		last_order = current_order
		current_order = null
	state = STATE_IDLE
	path = SimNavWaypointPath.new()
	retry_count = 0
	pending_long_ticket = 0
	pending_short_ticket = 0


func fail_order(tick: int, reason: String) -> void:
	if current_order != null:
		current_order.fail(tick, reason)
		last_order = current_order
		current_order = null
	state = STATE_FAILED
	path = SimNavWaypointPath.new()
	pending_long_ticket = 0
	pending_short_ticket = 0


func active_order_id() -> int:
	if current_order == null:
		return 0
	return current_order.order_id


func has_path() -> bool:
	return path != null and not path.is_empty()


func current_waypoint() -> Vector2:
	if not has_path():
		return move_target
	return path.back()


func consume_current_waypoint() -> void:
	if has_path():
		path.pop_back()


func remember_position() -> void:
	trace.append(position)
	if trace.size() > 80:
		trace.remove_at(0)


func clear_trace() -> void:
	trace = PackedVector2Array()
	trace.append(position)


func current_order_snapshot() -> Dictionary:
	if current_order == null:
		return {}
	return current_order.to_snapshot()


func last_order_snapshot() -> Dictionary:
	if last_order == null:
		return {}
	return last_order.to_snapshot()
