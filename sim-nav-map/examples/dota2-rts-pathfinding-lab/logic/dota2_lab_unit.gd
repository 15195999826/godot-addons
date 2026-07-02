class_name Dota2LabUnit
extends RefCounted


const MoveOrderScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_move_order.gd")

# Motion FSM states. See docs/design-notes/movement-feel-policy.md (v2) and
# motion-controller-design.md §3.1. HOLDING = recovery budget exhausted while
# unit-blocked: order retained, position held, periodic long-path retries.
# FAILED is reachable only from a statically unreachable long-path result.
const STATE_IDLE := "IDLE"
const STATE_WAITING_LONG := "WAITING_LONG"
const STATE_FOLLOWING := "FOLLOWING"
const STATE_WAITING_SHORT := "WAITING_SHORT"
const STATE_HOLDING := "HOLDING"
const STATE_FAILED := "FAILED"

const PATH_SOURCE_NONE := "none"
const PATH_SOURCE_LONG := "long"
const PATH_SOURCE_SHORT := "short"

# Dota2-style turn rate reference. Gameplay data is usually expressed as
# radians per 0.03 seconds; 0.6 turns 180 degrees in about 0.157s. The lab uses
# a slower visual default because small 2D arrows read as instant at raw Dota2
# speed, while keeping the Dota2 action-cone rule in the motion controller.
const DOTA2_TURN_RATE_INTERVAL_SEC := 0.03
const DOTA2_DEFAULT_TURN_RATE := 0.6
const DOTA2_REFERENCE_TURN_RATE_RAD_PER_SEC := DOTA2_DEFAULT_TURN_RATE / DOTA2_TURN_RATE_INTERVAL_SEC
const LAB_TURN_RATE_FEEL_SCALE := 0.5
const DEFAULT_TURN_RATE_RAD_PER_SEC := DOTA2_REFERENCE_TURN_RATE_RAD_PER_SEC * LAB_TURN_RATE_FEEL_SCALE


var id: String = ""
var group_id: String = ""
var position: Vector2 = Vector2.ZERO
var radius: float = 10.0
var speed: float = 90.0
var facing_angle_rad: float = 0.0
var turn_rate_rad_per_sec: float = DEFAULT_TURN_RATE_RAD_PER_SEC
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
var desired_facing_angle_rad: float = 0.0
var last_turn_delta_rad: float = 0.0
var waiting_for_facing: bool = false
# HOLDING: ticks until the next long-path retry (BOUNDED_HOLDING_ACTIVITY).
var hold_retry_countdown: int = 0
# M1 micro-detour: the waypoint inserted to walk around a blocking unit
# (INF = none). Walking happens through the normal facing/step pipeline —
# never as a sideways displacement, which reads as ice-drift and fights the
# turn gate into pirouettes. The blocker id is kept so the detour leg's
# live check can ignore the unit being rounded (a walk-around necessarily
# hugs it; checking against it would void every inserted detour).
var active_detour_point: Vector2 = Vector2.INF
var active_detour_blocker_id: String = ""
# Detours inserted since the last real progress; a long run means the unit
# is circling a crowd instead of getting anywhere and must escalate.
var detour_streak: int = 0

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
	p_mobile: bool = true,
	p_facing_angle_rad: float = 0.0,
	p_turn_rate_rad_per_sec: float = DEFAULT_TURN_RATE_RAD_PER_SEC
) -> void:
	id = p_id
	group_id = p_group_id
	position = p_position
	move_target = p_position
	radius = p_radius
	speed = p_speed
	mobile = p_mobile
	facing_angle_rad = p_facing_angle_rad
	desired_facing_angle_rad = p_facing_angle_rad
	turn_rate_rad_per_sec = p_turn_rate_rad_per_sec


func apply_move_order_data(target: Vector2, tick: int) -> int:
	_assert_no_pending_tickets("apply_move_order_data")
	var order: RefCounted = MoveOrderScript.new(_next_order_id, target, tick)
	_next_order_id += 1
	current_order = order
	move_target = target
	state = STATE_IDLE
	path = SimNavWaypointPath.new()
	path_source = PATH_SOURCE_NONE
	clear_detour()
	retry_count = 0
	last_path_request_kind = ""
	last_path_result_kind = ""
	last_path_result_status = ""
	last_path_failure_reason = ""
	last_short_goal = Vector2.ZERO
	last_short_range = 0.0
	last_turn_delta_rad = 0.0
	waiting_for_facing = false
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
	clear_detour()
	retry_count = 0
	last_turn_delta_rad = 0.0
	waiting_for_facing = false


func fail_order(tick: int, reason: String) -> void:
	_assert_no_pending_tickets("fail_order")
	if current_order != null:
		current_order.fail(tick, reason)
		last_order = current_order
		current_order = null
	state = STATE_FAILED
	path = SimNavWaypointPath.new()
	path_source = PATH_SOURCE_NONE
	clear_detour()
	last_turn_delta_rad = 0.0
	waiting_for_facing = false


# Enter HOLDING: keep the current order (a move order never gives up on unit
# blockers), drop the stale path, and schedule the next long-path retry.
func hold_position(retry_countdown_ticks: int) -> void:
	_assert_no_pending_tickets("hold_position")
	state = STATE_HOLDING
	path = SimNavWaypointPath.new()
	path_source = PATH_SOURCE_NONE
	hold_retry_countdown = retry_countdown_ticks
	clear_detour()
	last_turn_delta_rad = 0.0
	waiting_for_facing = false


func clear_detour() -> void:
	active_detour_point = Vector2.INF
	active_detour_blocker_id = ""
	detour_streak = 0


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
