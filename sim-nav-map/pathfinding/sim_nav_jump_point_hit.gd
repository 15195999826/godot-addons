class_name SimNavJumpPointHit
extends RefCounted


enum Kind {
	NONE,
	GOAL,
	JUMP,
	OBSTRUCTION,
	BOUNDARY,
}

var kind: int = Kind.NONE
var cell: Vector2i = Vector2i(-1, -1)
var steps: int = 0


func _init(p_kind: int = Kind.NONE, p_cell: Vector2i = Vector2i(-1, -1), p_steps: int = 0) -> void:
	kind = p_kind
	cell = p_cell
	steps = p_steps


func is_blocked() -> bool:
	return kind == Kind.OBSTRUCTION


func is_goal() -> bool:
	return kind == Kind.GOAL


func is_jump() -> bool:
	return kind == Kind.JUMP
