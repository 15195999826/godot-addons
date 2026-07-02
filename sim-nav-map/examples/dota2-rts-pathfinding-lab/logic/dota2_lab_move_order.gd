class_name Dota2LabMoveOrder
extends RefCounted

# One move command's lifecycle record. `target` is what the caller asked for;
# `effective_target` is where the path actually ends (canonicalized when the
# asked-for point is unreachable). Terminal reasons are the whole "how did
# this order end" vocabulary — there is no holding/retry state to inspect.

const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"

# Completed reasons.
const REASON_ARRIVED := "arrived"
# Goal itself is unreachable; unit stopped at the nearest reachable point.
const REASON_ARRIVED_PARTIAL := "arrived_partial"
# Goal area is crowded/blocked by other units; unit settled nearby.
const REASON_ARRIVED_CROWDED := "arrived_crowded"

# Failed reasons.
const REASON_CANCELLED := "cancelled"
const REASON_NO_PATH := "no_path"
# No progress for the full watchdog budget (after one replan attempt).
const REASON_STALLED := "stalled"


var order_id: int = 0
var target: Vector2 = Vector2.ZERO
var effective_target: Vector2 = Vector2.ZERO
var status: String = STATUS_ACTIVE
var reason: String = ""
var started_tick: int = 0
var ended_tick: int = -1


func _init(
	p_order_id: int = 0,
	p_target: Vector2 = Vector2.ZERO,
	p_started_tick: int = 0
) -> void:
	order_id = p_order_id
	target = p_target
	effective_target = p_target
	started_tick = p_started_tick


func is_active() -> bool:
	return status == STATUS_ACTIVE


func complete(tick: int, p_reason: String) -> void:
	status = STATUS_COMPLETED
	reason = p_reason
	ended_tick = tick


func fail(tick: int, p_reason: String) -> void:
	status = STATUS_FAILED
	reason = p_reason
	ended_tick = tick


func to_snapshot() -> Dictionary:
	return {
		"order_id": order_id,
		"target": {"x": target.x, "y": target.y},
		"effective_target": {"x": effective_target.x, "y": effective_target.y},
		"status": status,
		"reason": reason,
		"started_tick": started_tick,
		"ended_tick": ended_tick,
	}
