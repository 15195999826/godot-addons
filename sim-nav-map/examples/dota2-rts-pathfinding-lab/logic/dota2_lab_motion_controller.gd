class_name Dota2LabMotionController
extends RefCounted

# Dota2 RTS Pathfinding Lab — motion controller.
#
# Implements the explicit state machine specified in
# docs/design-notes/motion-controller-design.md. Five states per unit, eight
# transitions, fixed per-tick phase order, no magic-number-driven implicit
# transitions. Target LOC ≤300.
#
# Critical invariant (NO_SAME_TICK_TAKEOVER): when step_unit() enqueues a
# short or long detour because of a block, it must NOT take a result, mutate
# the path, or move in the same tick. The unit transitions to a WAITING_*
# state and the function returns.

const MotionUpdateScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_motion_update.gd")

const MAX_RETRY := 5
const ARRIVE_EPSILON := 4.0
# Short-path search range. Conservative single value; 0AD scales by failure
# count, dota2 lab does not (we instead grow retry_count → FAILED faster).
const SHORT_PATH_SEARCH_RANGE := 12.0 * 16.0  # 12 navcells * 16 px

# Counters surfaced via diagnostics(). Reset only by callers (typically once
# per test); the controller does not reset on its own.
var long_path_requests: int = 0
var short_path_requests: int = 0
var blocked_by_unit_count: int = 0
var blocked_by_static_count: int = 0
var move_failed_count: int = 0
var reached_goal_count: int = 0
var pending_count_peak: int = 0

var _motion_updates: Array[Dota2LabMotionUpdate] = []


# ─────────────────────────── External entry points ───────────────────────────

# Called from world.issue_move(). Cancels any prior state and starts fresh.
func start_move_order(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	_cancel_pending(unit, pathfinder)
	unit.retry_count = 0
	_enqueue_long(unit, pathfinder, tick)


# Called when world deletes/edits obstacles and any active mover needs a new
# long path. Equivalent to start_move_order with the existing move_target.
func replan_active(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if unit.state == Dota2LabUnit.STATE_IDLE or unit.state == Dota2LabUnit.STATE_FAILED:
		return
	_cancel_pending(unit, pathfinder)
	_enqueue_long(unit, pathfinder, tick)


# Drain motion updates emitted this tick. World calls this after every phase
# and dispatches each update to unit.on_motion_update() etc.
func drain_motion_updates() -> Array[Dota2LabMotionUpdate]:
	var result: Array[Dota2LabMotionUpdate] = _motion_updates.duplicate()
	_motion_updates.clear()
	return result


# ─────────────────────────── Per-tick phase 1: collect results ───────────────

# Drains pending tickets that have results, drives WAITING_* → FOLLOWING or
# FAILED transitions. Does not move the unit.
func apply_path_results(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if unit.pending_long_ticket > 0:
		var long_result := pathfinder.take_long_path_result(unit.pending_long_ticket)
		if long_result != null:
			unit.pending_long_ticket = 0
			_handle_long_result(unit, long_result, pathfinder, tick)
	if unit.pending_short_ticket > 0:
		var short_result := pathfinder.take_short_path_result(unit.pending_short_ticket)
		if short_result != null:
			unit.pending_short_ticket = 0
			_handle_short_result(unit, short_result, pathfinder, tick)


# ─────────────────────────── Per-tick phase 2: walk path ─────────────────────

# Only FOLLOWING units advance. A block transitions to WAITING_SHORT or
# WAITING_LONG and returns; no result is consumed this tick.
func step_unit(
	unit: Dota2LabUnit,
	delta: float,
	pathfinder: Dota2LabPathfinderWrapper,
	units: Array[Dota2LabUnit],
	tick: int
) -> void:
	if unit.state != Dota2LabUnit.STATE_FOLLOWING:
		return

	# Arrive check before walking. Mirrors 0AD's PossiblyAtDestination but
	# without the obstructed-branch tolerance — dota2 has no push, so the
	# unit either reaches move_target or it doesn't.
	if unit.position.distance_to(unit.move_target) <= ARRIVE_EPSILON:
		_finish_arrived(unit, tick)
		return

	var remaining_distance := unit.speed * delta
	var moved := false
	while remaining_distance > 0.0001 and unit.has_path():
		var waypoint := unit.current_waypoint()
		var to_waypoint := waypoint - unit.position
		var waypoint_distance := to_waypoint.length()
		if waypoint_distance <= 0.0001:
			unit.consume_current_waypoint()
			continue
		var reaches_waypoint := waypoint_distance <= remaining_distance
		var move_distance := waypoint_distance if reaches_waypoint else remaining_distance
		var candidate := waypoint if reaches_waypoint else unit.position + to_waypoint / waypoint_distance * move_distance

		# Validate the segment from current position to waypoint (not to
		# candidate). Matches 0AD's CCmpUnitMotion::PerformMove: anchoring
		# the LOS target to the planned end-point catches a fundamentally
		# unreachable waypoint immediately rather than only after multiple
		# frames of per-candidate slippage.
		var line_result := pathfinder.validate_movement_line(unit, unit.position, waypoint, units, false)
		if not line_result.is_success():
			_handle_step_block(unit, line_result, pathfinder, tick)
			return

		unit.position = candidate
		unit.remember_position()
		moved = true
		remaining_distance -= move_distance
		if reaches_waypoint:
			unit.consume_current_waypoint()

	# Walked the full path without blocking; check arrival or re-request.
	if unit.position.distance_to(unit.move_target) <= ARRIVE_EPSILON:
		_finish_arrived(unit, tick)
		return
	if not unit.has_path():
		# Detour finished but not at goal: re-enqueue long (per design §6.3).
		_enqueue_long(unit, pathfinder, tick)
		return
	# moved but path not empty and not arrived → keep FOLLOWING for next tick.
	_unused(moved)


# ─────────────────────────── Internal transitions ────────────────────────────

func _handle_long_result(
	unit: Dota2LabUnit,
	result: SimNavLongPathResult,
	_pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	# Accept only paths to the ORIGINAL goal (success or direct_goal).
	# STATUS_CANONICALIZED means the long pathfinder returned a fallback to
	# the nearest reachable navcell — accepting that path would loop the
	# unit toward an inner-cage canonical point forever (start at cage
	# interior, goal outside cage, canonical = best in-cage substitute).
	# STATUS_START_RECOVERED similarly means the unit's current position
	# was unrecoverable; dota2 lab terminates rather than warp.
	# Design notes §9: trust the long pathfinder's unreachable/no_path
	# result to drive FAILED.
	var accepted := (
		result.status == SimNavLongPathResult.STATUS_SUCCESS
		or result.status == SimNavLongPathResult.STATUS_DIRECT_GOAL
	)
	if accepted and result.path != null and not result.path.is_empty():
		unit.path = result.path
		unit.state = Dota2LabUnit.STATE_FOLLOWING
		return
	_terminal_failed(unit, "long_path_unreachable:" + str(result.status), tick)


func _handle_short_result(
	unit: Dota2LabUnit,
	result: SimNavShortPathResult,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if result.is_success() and result.path != null and not result.path.is_empty():
		unit.path = result.path
		unit.state = Dota2LabUnit.STATE_FOLLOWING
		return
	# Short detour failed. Budget check, then either retry via long or fail.
	unit.retry_count += 1
	if unit.retry_count > MAX_RETRY:
		_terminal_failed(unit, "max_retry_exceeded", tick)
		return
	_enqueue_long(unit, pathfinder, tick)


func _handle_step_block(
	unit: Dota2LabUnit,
	line_result: SimNavMovementLineResult,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	# Discriminate: unit blocker → short detour; static blocker → long replan.
	var reason := line_result.failure_reason
	if reason == SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED:
		blocked_by_unit_count += 1
		_enqueue_short(unit, pathfinder, tick)
		return
	# All other failure reasons (PASSABILITY_BLOCKED, STATIC_OBSTRUCTION_BLOCKED,
	# end_out_of_bounds, ...) → re-enqueue long. Static obstructions don't
	# change between ticks so a long replan is the right move; out_of_bounds
	# means goal is unreachable and the long pathfinder will surface that.
	blocked_by_static_count += 1
	_enqueue_long(unit, pathfinder, tick)


func _enqueue_long(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	_tick: int
) -> void:
	_cancel_pending(unit, pathfinder)
	unit.path = SimNavWaypointPath.new()
	unit.pending_long_ticket = pathfinder.enqueue_long_path(unit, unit.move_target)
	unit.state = Dota2LabUnit.STATE_WAITING_LONG
	long_path_requests += 1
	_track_pending_peak(pathfinder)


# CRITICAL: enqueues short request and freezes the current path. Must NOT
# take the result, mutate path, or move this tick. Caller (step_unit on
# block) returns immediately after calling this.
func _enqueue_short(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	_tick: int
) -> void:
	# Cancel any prior pending long (target switch case is handled by
	# start_move_order; this branch only fires from step_unit when a block
	# is detected mid-FOLLOWING, in which case pending_long is 0).
	if unit.pending_long_ticket > 0:
		pathfinder.cancel(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
	# Path is intentionally NOT cleared — the next tick's apply_path_results
	# may install a short detour that replaces it. If the short fails, the
	# long re-enqueue clears it. Keeping it here is harmless because state
	# is WAITING_SHORT, not FOLLOWING, and step_unit short-circuits.
	var goal := SimNavPathGoal.point(unit.move_target)
	unit.pending_short_ticket = pathfinder.enqueue_short_path(unit, goal, SHORT_PATH_SEARCH_RANGE)
	unit.state = Dota2LabUnit.STATE_WAITING_SHORT
	short_path_requests += 1
	_track_pending_peak(pathfinder)


func _cancel_pending(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper
) -> void:
	if unit.pending_long_ticket > 0:
		pathfinder.cancel(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
	if unit.pending_short_ticket > 0:
		pathfinder.cancel(unit.pending_short_ticket)
		unit.pending_short_ticket = 0


func _finish_arrived(unit: Dota2LabUnit, tick: int) -> void:
	_emit_motion_update(unit, Dota2LabMotionUpdate.TYPE_REACHED_GOAL, "", tick)
	unit.complete_order(tick)
	reached_goal_count += 1


func _terminal_failed(unit: Dota2LabUnit, reason: String, tick: int) -> void:
	_emit_motion_update(unit, Dota2LabMotionUpdate.TYPE_MOVE_FAILED, reason, tick)
	unit.fail_order(tick, reason)
	move_failed_count += 1


func _emit_motion_update(
	unit: Dota2LabUnit,
	update_type: String,
	reason: String,
	tick: int
) -> void:
	_motion_updates.append(Dota2LabMotionUpdate.new(
		unit.id,
		unit.active_order_id(),
		update_type,
		tick,
		unit.position,
		reason
	))


func _track_pending_peak(pathfinder: Dota2LabPathfinderWrapper) -> void:
	if pathfinder.path_queue == null:
		return
	var pending := pathfinder.path_queue.pending_count()
	if pending > pending_count_peak:
		pending_count_peak = pending


# ─────────────────────────── Diagnostics ─────────────────────────────────────

func diagnostics(units: Array[Dota2LabUnit]) -> Dictionary:
	var state_counts := {
		Dota2LabUnit.STATE_IDLE: 0,
		Dota2LabUnit.STATE_WAITING_LONG: 0,
		Dota2LabUnit.STATE_FOLLOWING: 0,
		Dota2LabUnit.STATE_WAITING_SHORT: 0,
		Dota2LabUnit.STATE_FAILED: 0,
	}
	var retry_count_max := 0
	for unit in units:
		state_counts[unit.state] = int(state_counts.get(unit.state, 0)) + 1
		if unit.retry_count > retry_count_max:
			retry_count_max = unit.retry_count
	return {
		"long_path_requests": long_path_requests,
		"short_path_requests": short_path_requests,
		"blocked_by_unit_count": blocked_by_unit_count,
		"blocked_by_static_count": blocked_by_static_count,
		"move_failed_count": move_failed_count,
		"reached_goal_count": reached_goal_count,
		"pending_count_peak": pending_count_peak,
		"state_counts": state_counts,
		"retry_count_max": retry_count_max,
	}


func _unused(_v) -> void:
	pass
