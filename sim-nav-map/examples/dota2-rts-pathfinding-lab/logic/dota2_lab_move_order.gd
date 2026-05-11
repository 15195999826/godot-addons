class_name Dota2LabMoveOrder
extends RefCounted


const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"


var order_id: int = 0
var target: Vector2 = Vector2.ZERO
var status: String = STATUS_ACTIVE
var started_tick: int = 0
var ended_tick: int = -1
var failure_reason: String = ""


func _init(
	p_order_id: int = 0,
	p_target: Vector2 = Vector2.ZERO,
	p_started_tick: int = 0
) -> void:
	order_id = p_order_id
	target = p_target
	started_tick = p_started_tick


func is_active() -> bool:
	return status == STATUS_ACTIVE


func complete(tick: int) -> void:
	status = STATUS_COMPLETED
	ended_tick = tick
	failure_reason = ""


func fail(tick: int, reason: String) -> void:
	status = STATUS_FAILED
	ended_tick = tick
	failure_reason = reason


func to_snapshot() -> Dictionary:
	return {
		"order_id": order_id,
		"target": {"x": target.x, "y": target.y},
		"status": status,
		"started_tick": started_tick,
		"ended_tick": ended_tick,
		"failure_reason": failure_reason,
	}
