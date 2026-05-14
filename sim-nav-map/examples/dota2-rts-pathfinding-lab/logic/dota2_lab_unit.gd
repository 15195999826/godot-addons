class_name Dota2LabUnit
extends RefCounted


const MoveOrderScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_move_order.gd")

# Motion FSM states. See docs/design-notes/motion-controller-design.md §3.1.
const STATE_IDLE := "IDLE"
const STATE_WAITING_LONG := "WAITING_LONG"
const STATE_FOLLOWING := "FOLLOWING"
const STATE_WAITING_SHORT := "WAITING_SHORT"
const STATE_FAILED := "FAILED"

const PATH_SOURCE_NONE := "none"
const PATH_SOURCE_LONG := "long"
const PATH_SOURCE_SHORT := "short"


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
var path_source: String = PATH_SOURCE_NONE
var last_path_request_kind: String = ""
var last_path_result_kind: String = ""
var last_path_result_status: String = ""
var last_path_failure_reason: String = ""
var last_short_goal: Vector2 = Vector2.ZERO
var last_short_range: float = 0.0

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


func apply_move_order_data(target: Vector2, tick: int) -> int:
	_assert_no_pending_tickets("apply_move_order_data")
	var order: RefCounted = MoveOrderScript.new(_next_order_id, target, tick)
	_next_order_id += 1
	current_order = order
	move_target = target
	state = STATE_IDLE
	path = SimNavWaypointPath.new()
	path_source = PATH_SOURCE_NONE
	retry_count = 0
	last_path_request_kind = ""
	last_path_result_kind = ""
	last_path_result_status = ""
	last_path_failure_reason = ""
	last_short_goal = Vector2.ZERO
	last_short_range = 0.0
	return order.order_id


func complete_order(tick: int) -> void:
	_assert_no_pending_tickets("complete_order")
	if current_order != null:
		current_order.complete(tick)
		last_order = current_order
		current_order = null
	state = STATE_IDLE
	path = SimNavWaypointPath.new()
	path_source = PATH_SOURCE_NONE
	retry_count = 0


func fail_order(tick: int, reason: String) -> void:
	_assert_no_pending_tickets("fail_order")
	if current_order != null:
		current_order.fail(tick, reason)
		last_order = current_order
		current_order = null
	state = STATE_FAILED
	path = SimNavWaypointPath.new()
	path_source = PATH_SOURCE_NONE


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


func _assert_no_pending_tickets(caller: String) -> void:
	Log.assert_crash(
		pending_long_ticket == 0 and pending_short_ticket == 0,
		"Dota2LabUnit",
		"%s must be called after controller cancels pending tickets (long=%d short=%d)"
			% [caller, pending_long_ticket, pending_short_ticket]
	)
