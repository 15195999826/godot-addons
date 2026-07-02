class_name Dota2LabMotionUpdate
extends RefCounted


const TYPE_CLEAR := "clear"
const TYPE_REACHED_GOAL := "reached_goal"
const TYPE_OBSTRUCTED := "obstructed"
const TYPE_MOVE_FAILED := "move_failed"
const TYPE_MOVE_HOLDING := "move_holding"


var actor_id: String = ""
var order_id: int = 0
var update_type: String = ""
var tick: int = 0
var position: Vector2 = Vector2.ZERO
var reason: String = ""


func _init(
	p_actor_id: String = "",
	p_order_id: int = 0,
	p_update_type: String = "",
	p_tick: int = 0,
	p_position: Vector2 = Vector2.ZERO,
	p_reason: String = ""
) -> void:
	actor_id = p_actor_id
	order_id = p_order_id
	update_type = p_update_type
	tick = p_tick
	position = p_position
	reason = p_reason


func to_snapshot() -> Dictionary:
	return {
		"actor_id": actor_id,
		"order_id": order_id,
		"type": update_type,
		"tick": tick,
		"position": {"x": position.x, "y": position.y},
		"reason": reason,
	}
