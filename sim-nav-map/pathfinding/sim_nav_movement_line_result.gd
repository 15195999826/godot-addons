class_name SimNavMovementLineResult
extends RefCounted


const STATUS_CLEAR := "clear"
const STATUS_BLOCKED := "blocked"
const STATUS_INVALID_QUERY := "invalid_query"

const FAILURE_NONE := "none"
const FAILURE_NAV_MAP_MISSING := "nav_map_missing"
const FAILURE_PASSABILITY_BLOCKED := "passability_blocked"
const FAILURE_START_OUT_OF_BOUNDS := "start_out_of_bounds"
const FAILURE_END_OUT_OF_BOUNDS := "end_out_of_bounds"
const FAILURE_STATIC_OBSTRUCTION_BLOCKED := "static_obstruction_blocked"
const FAILURE_UNIT_OBSTRUCTION_BLOCKED := "unit_obstruction_blocked"

var status: String = STATUS_INVALID_QUERY
var failure_reason: String = FAILURE_NONE
var start: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var clearance: float = 0.0
var pass_mask: int = 0
var unit_only: bool = false
var checked_navcell_count: int = 0
var checked_obstruction_count: int = 0
var blocked_navcell: Vector2i = Vector2i(-1, -1)
var blocked_obstruction_tag: int = 0
var blocked_obstruction_entity_id: String = ""
var blocked_obstruction_type: int = -1
var obstruction_filter: SimNavObstructionFilter = null


func configure_query(
	p_start: Vector2,
	p_target: Vector2,
	p_clearance: float,
	p_pass_mask: int,
	p_filter: SimNavObstructionFilter,
	p_unit_only: bool
) -> void:
	start = p_start
	target = p_target
	clearance = p_clearance
	pass_mask = p_pass_mask
	obstruction_filter = p_filter.clone() if p_filter != null else SimNavObstructionFilter.new()
	unit_only = p_unit_only


func set_clear() -> void:
	status = STATUS_CLEAR
	failure_reason = FAILURE_NONE


func set_invalid(reason: String) -> void:
	status = STATUS_INVALID_QUERY
	failure_reason = reason


func set_passability_blocked(reason: String, coord: Vector2i) -> void:
	status = STATUS_BLOCKED
	failure_reason = reason
	blocked_navcell = coord


func set_obstruction_blocked(shape: SimNavObstructionShape) -> void:
	status = STATUS_BLOCKED
	if shape is SimNavObstructionShapeUnit:
		failure_reason = FAILURE_UNIT_OBSTRUCTION_BLOCKED
	else:
		failure_reason = FAILURE_STATIC_OBSTRUCTION_BLOCKED
	if shape == null:
		return
	blocked_obstruction_tag = shape.tag
	blocked_obstruction_entity_id = shape.entity_id
	blocked_obstruction_type = int(shape.type)


func is_success() -> bool:
	return status == STATUS_CLEAR
