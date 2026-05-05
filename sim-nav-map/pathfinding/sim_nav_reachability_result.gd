class_name SimNavReachabilityResult
extends RefCounted


const FAILURE_NONE := "none"
const FAILURE_NOT_RECOMPUTED := "not_recomputed"
const FAILURE_INVALID_QUERY := "invalid_query"
const FAILURE_NO_START_REGION := "no_start_region"
const FAILURE_ORIGINAL_GOAL_UNREACHABLE := "original_goal_unreachable"
const FAILURE_NO_REACHABLE_GOAL := "no_reachable_goal"

var is_reachable: bool = false
var canonicalized: bool = false
var failure_reason: String = FAILURE_NONE
var pass_mask: int = 0
var passability_class_name: String = ""
var start_navcell: Vector2i = Vector2i(-1, -1)
var effective_start_navcell: Vector2i = Vector2i(-1, -1)
var canonical_navcell: Vector2i = Vector2i(-1, -1)
var start_global_region: int = 0
var canonical_global_region: int = 0
var query_goal: SimNavPathGoal = null
var canonical_goal: SimNavPathGoal = null


func has_canonical_goal() -> bool:
	return canonical_goal != null


func is_failure() -> bool:
	return failure_reason != FAILURE_NONE and not has_canonical_goal()


func configure_query(
	p_start_navcell: Vector2i,
	p_goal: SimNavPathGoal,
	p_pass_mask: int,
	p_passability_class_name: String = ""
) -> void:
	start_navcell = p_start_navcell
	effective_start_navcell = p_start_navcell
	pass_mask = p_pass_mask
	passability_class_name = p_passability_class_name
	if p_goal != null:
		query_goal = p_goal.clone()


func set_failure(reason: String) -> void:
	failure_reason = reason
	is_reachable = false
	canonicalized = false
	canonical_goal = null
	canonical_navcell = Vector2i(-1, -1)
	canonical_global_region = 0


func set_reachable(
	p_canonical_goal: SimNavPathGoal,
	p_canonical_navcell: Vector2i,
	p_start_global_region: int,
	p_canonical_global_region: int
) -> void:
	is_reachable = true
	canonicalized = false
	failure_reason = FAILURE_NONE
	canonical_goal = p_canonical_goal.clone() if p_canonical_goal != null else null
	canonical_navcell = p_canonical_navcell
	start_global_region = p_start_global_region
	canonical_global_region = p_canonical_global_region


func set_canonicalized(
	p_canonical_goal: SimNavPathGoal,
	p_canonical_navcell: Vector2i,
	p_start_global_region: int,
	p_canonical_global_region: int,
	reason: String = FAILURE_ORIGINAL_GOAL_UNREACHABLE
) -> void:
	is_reachable = false
	canonicalized = true
	failure_reason = reason
	canonical_goal = p_canonical_goal.clone() if p_canonical_goal != null else null
	canonical_navcell = p_canonical_navcell
	start_global_region = p_start_global_region
	canonical_global_region = p_canonical_global_region
