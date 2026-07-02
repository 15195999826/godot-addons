class_name Dota2LabUnit
extends RefCounted

# Fable motion model: a unit is either executing a move order (MOVING) or not
# (IDLE). There are no waiting/holding/failed resident states — planning is
# synchronous and terminal outcomes live on `last_order`. All per-tick motion
# behavior (path following, turning, separation) is Dota2LabMotionEngine's;
# this class is the unit's data + order bookkeeping.

const STATE_IDLE := "IDLE"
const STATE_MOVING := "MOVING"

# Dota2-style turn rate reference. Gameplay data is usually expressed as
# radians per 0.03 seconds; 0.6 turns 180 degrees in about 0.157s. The lab uses
# a slower visual default because small 2D arrows read as instant at raw Dota2
# speed.
const DOTA2_TURN_RATE_INTERVAL_SEC := 0.03
const DOTA2_DEFAULT_TURN_RATE := 0.6
const DOTA2_REFERENCE_TURN_RATE_RAD_PER_SEC := DOTA2_DEFAULT_TURN_RATE / DOTA2_TURN_RATE_INTERVAL_SEC
const LAB_TURN_RATE_FEEL_SCALE := 0.5
const DEFAULT_TURN_RATE_RAD_PER_SEC := DOTA2_REFERENCE_TURN_RATE_RAD_PER_SEC * LAB_TURN_RATE_FEEL_SCALE

const TRACE_LIMIT := 300


var id: String = ""
var group_id: String = ""
var position: Vector2 = Vector2.ZERO
var radius: float = 10.0
var speed: float = 90.0
var facing_angle_rad: float = 0.0
var turn_rate_rad_per_sec: float = DEFAULT_TURN_RATE_RAD_PER_SEC
# mobile == false means the unit is an unpushable circular blocker: it never
# moves, never receives orders, and has zero pushability in the separation
# solve.
var mobile: bool = true

var state: String = STATE_IDLE
# Last commanded goal (kept after the order ends, for diagnostics).
var move_target: Vector2 = Vector2.ZERO
# Where the current path actually ends (canonicalized goal when move_target
# is unreachable). Arrival is judged against this point.
var effective_target: Vector2 = Vector2.ZERO
var path: SimNavWaypointPath = SimNavWaypointPath.new()

var current_order: Dota2LabMoveOrder = null
var last_order: Dota2LabMoveOrder = null

# Watchdog bookkeeping (engine-owned semantics).
var stall_seconds: float = 0.0
var repath_count: int = 0
var prev_tick_position: Vector2 = Vector2.ZERO
# Best distance-to-goal seen this order: near the goal, "moving but never
# getting closer" (orbiting a crowd) counts as a stall.
var best_goal_distance: float = INF

# Per-tick motion diagnostics for frontend/smoke.
var last_speed_factor: float = 0.0
var last_turn_delta_rad: float = 0.0

# Contact-steering side lock (+1 / -1, 0 = unlocked): the go-around side is
# chosen geometrically on first contact and held while contact persists, so
# a unit never flip-flops sides mid-squeeze.
var steer_side: float = 0.0

# Frontend / debug.
var trace: PackedVector2Array = PackedVector2Array()

var _next_order_id: int = 1


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
	prev_tick_position = p_position
	move_target = p_position
	effective_target = p_position
	radius = p_radius
	speed = p_speed
	mobile = p_mobile
	facing_angle_rad = p_facing_angle_rad
	turn_rate_rad_per_sec = p_turn_rate_rad_per_sec


func begin_order(goal: Vector2, tick: int) -> Dota2LabMoveOrder:
	var order := Dota2LabMoveOrder.new(_next_order_id, goal, tick)
	_next_order_id += 1
	current_order = order
	move_target = goal
	effective_target = goal
	path = SimNavWaypointPath.new()
	state = STATE_MOVING
	stall_seconds = 0.0
	repath_count = 0
	best_goal_distance = INF
	last_speed_factor = 0.0
	last_turn_delta_rad = 0.0
	steer_side = 0.0
	return order


func finish_order(tick: int, completed: bool, reason: String) -> void:
	if current_order != null:
		if completed:
			current_order.complete(tick, reason)
		else:
			current_order.fail(tick, reason)
		last_order = current_order
		current_order = null
	state = STATE_IDLE
	path = SimNavWaypointPath.new()
	stall_seconds = 0.0
	last_speed_factor = 0.0
	last_turn_delta_rad = 0.0
	steer_side = 0.0


func is_moving() -> bool:
	return state == STATE_MOVING


func has_path() -> bool:
	return path != null and not path.is_empty()


func current_waypoint() -> Vector2:
	if not has_path():
		return effective_target
	return path.back()


func active_order_id() -> int:
	if current_order == null:
		return 0
	return current_order.order_id


func last_order_failed() -> bool:
	return last_order != null and last_order.status == Dota2LabMoveOrder.STATUS_FAILED


func remember_position() -> void:
	trace.append(position)
	if trace.size() > TRACE_LIMIT:
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
