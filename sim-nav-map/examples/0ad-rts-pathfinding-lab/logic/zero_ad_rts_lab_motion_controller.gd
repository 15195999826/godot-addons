class_name ZeroAdRtsLabMotionController
extends RefCounted


const MotionUpdateScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_motion_update.gd")

const ARRIVE_EPSILON: float = 8.0
const NAVCELL_SIZE: float = 16.0
const SHORT_PATH_MIN_SEARCH_RANGE: float = 12.0 * NAVCELL_SIZE
const SHORT_PATH_MAX_SEARCH_RANGE: float = 56.0 * NAVCELL_SIZE
const SHORT_PATH_SEARCH_RANGE_INCREMENT: float = 4.0 * NAVCELL_SIZE
const SHORT_PATH_SEARCH_RANGE_INCREASE_DELAY: int = 1
const SHORT_PATH_LONG_WAYPOINT_RANGE: float = 4.0 * NAVCELL_SIZE
const LONG_PATH_UNIT_LINE_SUBGOAL_RADIUS: float = 2.0 * NAVCELL_SIZE
const LONG_PATH_MIN_DIST: float = 16.0 * NAVCELL_SIZE
const DIRECT_PATH_RANGE: float = 24.0 * NAVCELL_SIZE
const KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN: int = 12
const MAX_FAILED_MOVEMENTS: int = 35
const ALTERNATE_PATH_TYPE_DELAY: int = 3
const ALTERNATE_PATH_TYPE_EVERY: int = 6
const BACKUP_HACK_DELAY: int = 10
const BACKUP_HACK_DISTANCE: float = 1.0
const VERY_OBSTRUCTED_THRESHOLD: int = 10
const PUSHING_CORRECTION: float = 5.0 / 7.0
const PUSHING_REDUCTION_FACTOR: float = 2.0
const PUSHING_RADIUS_MULTIPLIER: float = 8.0 / 5.0
const MOVING_PUSH_EXTENSION: float = 2.5
const STATIC_PUSH_EXTENSION: float = 2.0
const MAX_PUSHING_MULTIPLIER: float = 4.0
const PUSH_REFERENCE_SPEED: float = NAVCELL_SIZE * 6.0
const PUSH_MAX_PER_FRAME: float = 6.0
const MIN_PUSH: float = 0.05
const PUSH_BUCKET_SIZE: float = 48.0
const GOAL_OPPOSING_PUSH_DAMPING: float = 0.35
const MAX_PUSH_PRESSURE: int = 255
const MAX_PUSH_DAMPING_PRESSURE: int = 160
const PUSH_PRESSURE_DECAY: float = 0.60
const PUSH_PRESSURE_DECAY_TURN_SEC: float = 0.20
const PUSH_PRESSURE_OBSTRUCTED_THRESHOLD: int = 30
const MIN_PRESSURE_IF_OBSTRUCTED: int = 80
const PUSH_PRESSURE_SPEED_THRESHOLD: int = 10
const PUSH_PRESSURE_SPEED_FLOOR_RATIO: float = 0.25
const MOVING_PUSH_SPREAD: float = 0.625
const STATIC_PUSH_SPREAD: float = 0.625
const MAX_DISTANCE_FACTOR: float = 2.5
const PRESSURE_STATIC_FACTOR: float = 2.0
const PRESSURE_DISTANCE_FACTOR: float = 5.0
const SHORT_REPATH_COOLDOWN_SEC: float = 0.0
const MAX_PATH_DECISION_LOG_ENTRIES: int = 240
const CROSSING_NUDGE_DOT_THRESHOLD: float = -0.1
const CROSSING_NUDGE_DISTANCE: float = 3.0
const LONG_SEGMENT_TAKEOVER_POLICY_0AD_SKIP_BLOCKED_WAYPOINT: String = "0ad_skip_blocked_waypoint"
const LONG_SEGMENT_TAKEOVER_POLICY_LAB_KEEP_BLOCKED_WAYPOINT: String = "lab_keep_blocked_waypoint"

const MOTION_DEAD_ZONE_SQ: float = 1.0e-4
# Cosine threshold for "motion is facing the other unit". 0.05 ≈ angle <87°,
# i.e. roughly anything other than near-perpendicular counts as facing. Used to
# filter out the push-displacement-induced perpendicular jitter that would
# otherwise make side-by-side parallel-moving units register as facing each
# other from tick 2 onward (push pushes them apart, then their motion intent
# back toward their goal has a tiny component pointing at the partner).
const MOTION_FACING_COSINE_MIN: float = 0.05

var long_segment_takeover_policy: String = LONG_SEGMENT_TAKEOVER_POLICY_LAB_KEEP_BLOCKED_WAYPOINT
# Lab-only deviation from 0 A.D. (CCmpUnitMotion_System.cpp:794-796 adds
# pressure to both members of every push pair). When true, only the unit
# whose motion intent is heading toward the other one accumulates pressure;
# the "leader" stays at zero pressure and runs at full speed. See
# docs/custom-features/asymmetric-push-pressure.md.
var asymmetric_push_pressure_enabled: bool = true
var short_path_requests: int = 0
var long_path_requests: int = 0
var blocked_moves: int = 0
var move_failures: int = 0
var obstructed_notifications: int = 0
var very_obstructed_notifications: int = 0
var repath_suppressed: int = 0
var obsolete_path_requests: int = 0
var known_imperfect_paths: int = 0
var known_imperfect_suppressed: int = 0
var rejected_pushes: int = 0
var applied_pushes: int = 0
var crossing_nudges: int = 0
var goal_opposing_push_dampens: int = 0
var push_pressure_obstructions: int = 0
var path_results_applied: int = 0
var path_result_failures: int = 0
var push_pair_checks: int = 0
var push_grid_cells: int = 0
var _motion_updates: Array[RefCounted] = []
var _path_decisions: Array[Dictionary] = []
var _pending_short_path_contexts: Dictionary = {}


func start_move_order(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	tick: int = 0
) -> void:
	_cancel_pending_path_requests(unit, pathfinder)
	_record_path_decision(unit, "order_started", tick)
	_request_long_path(unit, unit.target, pathfinder, tick)


func replan_active_order(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	tick: int = 0
) -> void:
	if not unit.has_move_order:
		return
	_cancel_pending_path_requests(unit, pathfinder)
	unit.long_path = SimNavWaypointPath.new()
	unit.short_path = SimNavWaypointPath.new()
	unit.pending_long_ticket = 0
	unit.pending_short_ticket = 0
	unit.short_repath_cooldown = 0.0
	_record_path_decision(unit, "order_replanned", tick)
	_request_long_path(unit, unit.target, pathfinder, tick)


func drain_motion_updates() -> Array[RefCounted]:
	var result: Array[RefCounted] = _motion_updates.duplicate()
	_motion_updates.clear()
	return result


func recent_path_decisions() -> Array[Dictionary]:
	return _path_decisions.duplicate(true)


func apply_path_results(
	units: Array[ZeroAdRtsLabUnit],
	pathfinder: ZeroAdRtsLabPathfinder,
	tick: int = 0
) -> void:
	for unit in units:
		if unit.pending_long_ticket > 0:
			var long_result := pathfinder.take_long_path_result(unit.pending_long_ticket)
			if long_result != null:
				unit.pending_long_ticket = 0
				_apply_long_path_result(unit, long_result, tick)
		if unit.pending_short_ticket > 0:
			var short_ticket := unit.pending_short_ticket
			var short_result := pathfinder.take_short_path_result(short_ticket)
			if short_result != null:
				unit.pending_short_ticket = 0
				_apply_short_path_result(unit, short_result, short_ticket, pathfinder, units, tick)


func _apply_pending_short_path_same_tick(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	tick: int
) -> void:
	if unit.pending_short_ticket <= 0:
		return
	var requested_ticket := unit.pending_short_ticket
	pathfinder.process_path_budget(units, 1)
	var single_unit: Array[ZeroAdRtsLabUnit] = [unit]
	apply_path_results(single_unit, pathfinder, tick)
	if unit.pending_short_ticket == requested_ticket:
		return
	_record_path_decision(unit, "same_tick_short_takeover_applied", tick, {
		"ticket": requested_ticket,
		"short_path_size": unit.short_path.size() if unit.short_path != null else 0,
	})


func step_unit(
	unit: ZeroAdRtsLabUnit,
	delta: float,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	tick: int = 0
) -> void:
	if not unit.mobile or not unit.has_move_order:
		return
	unit.short_repath_cooldown = maxf(0.0, unit.short_repath_cooldown - delta)
	unit.follow_known_imperfect_path_countdown = maxi(0, unit.follow_known_imperfect_path_countdown - 1)
	# Mirror 0 A.D. CCmpUnitMotion::OnTurnStart -> PossiblyAtDestination
	# (CCmpUnitMotion.h:1050-1053). Arrive must not depend on the path queue
	# being empty: when long pathfinder canonicalizes two formation members'
	# user goals into the same nearby passable cell (e.g. both formation
	# slots fall inside an obstacle's inflated rect), every blocked_recovery
	# tick re-requests a long path that lands on the same canonical goal.
	# `unit.has_path()` therefore never empties, and motion+push oscillate
	# around the canonical goal at ~0.005 px/tick without ever crossing
	# ARRIVE_EPSILON of the path queue's terminal waypoint. Detect arrival
	# directly from position vs path_target, mirroring the obstructed-branch
	# check below (line ~204).
	if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON:
		unit.long_path = SimNavWaypointPath.new()
		unit.short_path = SimNavWaypointPath.new()
		unit.failed_movements = 0
		_cancel_pending_path_requests(unit, pathfinder)
		_emit_clear_update_if_needed(unit, tick)
		_emit_motion_update(unit, MotionUpdateScript.TYPE_REACHED_GOAL, "", tick)
		return

	var went_straight := false
	# Keep an existing planned path. Near rasterized corners, replacing it with
	# a borderline direct target line can drop an executable long path.
	if not unit.has_path():
		went_straight = _try_going_straight_to_target(unit, pathfinder, units, true)
	var short_takeover_requested := false
	if not went_straight:
		short_takeover_requested = _maybe_request_short_path_for_long_segment(unit, pathfinder, units, tick)
	if short_takeover_requested:
		_apply_pending_short_path_same_tick(unit, pathfinder, units, tick)
		if unit.pending_short_ticket > 0 and (unit.short_path == null or unit.short_path.is_empty()):
			_record_path_decision(unit, "defer_stale_long_move_after_short_takeover", tick, {
				"pending_short_ticket": unit.pending_short_ticket,
				"long_path_size": unit.long_path.size() if unit.long_path != null else 0,
			})
			return
	if not unit.has_path():
		if unit.pending_long_ticket == 0 and unit.pending_short_ticket == 0:
			_handle_blocked_move(unit, pathfinder, units, false, tick)
		return

	var move_result := _perform_move(unit, delta, pathfinder, units, tick)
	if bool(move_result.get("obstructed", false)):
		if String(move_result.get("failure_reason", "")) == "push_pressure_pair_blocked":
			unit.was_obstructed = true
			return
		# If we're physically close to the move-order target and the only
		# thing stopping us is a static/idle unit at the goal (or a goal that
		# fell inside an obstruction's collision ring), treat the order as
		# fulfilled. Mirrors 0 A.D. CCmpUnitMotion::PossiblyAtDestination's
		# tolerance — without this the unit spins blocked_recovery forever
		# at distance < ARRIVE_EPSILON because the long-path final waypoint
		# remains technically unreachable.
		if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON:
			unit.long_path = SimNavWaypointPath.new()
			unit.short_path = SimNavWaypointPath.new()
			unit.failed_movements = 0
			_emit_clear_update_if_needed(unit, tick)
			_emit_motion_update(unit, MotionUpdateScript.TYPE_REACHED_GOAL, "", tick)
			return
		_handle_blocked_move(
			unit,
			pathfinder,
			units,
			bool(move_result.get("moved", false)),
			tick,
			String(move_result.get("failure_reason", ""))
		)
		return
	if bool(move_result.get("moved", false)):
		unit.failed_movements = 0
		_emit_clear_update_if_needed(unit, tick)
		if unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON and not unit.has_path():
			_emit_motion_update(unit, MotionUpdateScript.TYPE_REACHED_GOAL, "", tick)
		elif went_straight:
			unit.short_path = SimNavWaypointPath.new()
		return
	_handle_blocked_move(unit, pathfinder, units, false, tick)


func apply_push_adjust(
	units: Array[ZeroAdRtsLabUnit],
	pathfinder: ZeroAdRtsLabPathfinder,
	previous_positions: Dictionary = {},
	previous_move_orders: Dictionary = {},
	tick: int = 0,
	delta: float = 1.0 / 60.0
) -> void:
	var pushes: Dictionary = {}
	for unit in units:
		pushes[unit.id] = Vector2.ZERO
	_decay_push_pressure(units, delta)
	var pressure_deltas: Dictionary = {}
	for unit in units:
		pressure_deltas[unit.id] = 0
	push_pair_checks = 0
	var buckets := _build_push_buckets(units)
	push_grid_cells = buckets.size()
	for unit in units:
		for other in _nearby_push_units(unit, buckets):
			if unit.id >= other.id:
				continue
			push_pair_checks += 1
			_accumulate_pair_push(
				unit,
				other,
				pushes,
				pressure_deltas,
				previous_positions,
				previous_move_orders,
				delta
			)
	_apply_push_pressure_deltas(units, pressure_deltas)
	var pressure_obstructed_units: Array[ZeroAdRtsLabUnit] = []
	var push_blocked_units: Array[ZeroAdRtsLabUnit] = []
	for unit in units:
		var push_vec: Vector2 = pushes.get(unit.id, Vector2.ZERO)
		if push_vec.length() <= MIN_PUSH:
			continue
		if _push_opposes_attempted_motion(unit, push_vec, previous_positions):
			_mark_push_pressure_obstructed(unit, pressure_obstructed_units)
		push_vec = _dampen_pressure_push(unit, push_vec)
		if push_vec.length() <= MIN_PUSH:
			continue
		if push_vec.length() > PUSH_MAX_PER_FRAME:
			push_vec = push_vec.normalized() * PUSH_MAX_PER_FRAME
		var candidate: Vector2 = unit.position + push_vec
		var line_result := pathfinder.validate_movement_line(unit, unit.position, candidate, units, false)
		if line_result.is_success():
			unit.position = candidate
			unit.remember_position()
			applied_pushes += 1
		else:
			unit.was_obstructed = true
			unit.pushing_pressure = maxi(MIN_PRESSURE_IF_OBSTRUCTED, unit.pushing_pressure)
			rejected_pushes += 1
			if unit.has_move_order and not push_blocked_units.has(unit):
				push_blocked_units.append(unit)
	for unit in push_blocked_units:
		if pressure_obstructed_units.has(unit):
			continue
		var previous_position: Vector2 = previous_positions.get(unit.id, unit.position) as Vector2
		_handle_blocked_move(
			unit,
			pathfinder,
			units,
			unit.position.distance_squared_to(previous_position) > 0.0001,
			tick,
			"push_static_blocked"
		)
	for unit in pressure_obstructed_units:
		var previous_position: Vector2 = previous_positions.get(unit.id, unit.position) as Vector2
		_handle_blocked_move(
			unit,
			pathfinder,
			units,
			unit.position.distance_squared_to(previous_position) > 0.0001,
			tick,
			"push_pressure_obstructed"
		)


func _perform_move(
	unit: ZeroAdRtsLabUnit,
	delta: float,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	tick: int
) -> Dictionary:
	var remaining_distance := _effective_speed(unit) * delta
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
		# Validate the FULL segment to the waypoint, not the per-frame candidate.
		# Mirrors 0 A.D. CCmpUnitMotion::PerformMove (CCmpUnitMotion.h:1334) which
		# CheckMovement(pos, target=waypoint). With per-candidate validation only,
		# a segment heading toward a waypoint that lies inside an obstacle's
		# collision ring slips past the EDGE_EXPAND_DELTA tolerance every frame
		# (0.4 px advance < 0.5 px tolerance) and accumulates into a full
		# pass-through over multiple ticks. Validating against the waypoint
		# anchors the LOS target to the path's intended end point so a
		# fundamentally bad target gets caught immediately.
		var validation_target := waypoint
		var line_result := pathfinder.validate_movement_line(unit, unit.position, validation_target, units, false)
		if not line_result.is_success():
			var snap := _line_result_snapshot(line_result, units)
			# Geometry diagnostics: how far is candidate / waypoint / start from
			# the blocker? Lets log readers immediately see "off by 0.5 px /
			# blocker is genuinely in the way / blocker is far but along path".
			_annotate_distance_to_blocker(snap, unit.position, candidate, waypoint, line_result.blocked_obstruction_entity_id, units)
			_record_path_decision(unit, "movement_line_blocked", tick, {
				"from": unit.position,
				"candidate": candidate,
				"waypoint": waypoint,
				"line": snap,
			})
			return {
				"obstructed": true,
				"moved": moved,
				"failure_reason": line_result.failure_reason,
			}
		var pressure_blocker := _pressure_pair_blocker(unit, candidate, units)
		if pressure_blocker != null:
			_record_path_decision(unit, "movement_pressure_pair_blocked", tick, {
				"from": unit.position,
				"candidate": candidate,
				"waypoint": waypoint,
				"blocking_unit_id": pressure_blocker.id,
				"blocking_unit_position": pressure_blocker.position,
				"pushing_pressure": unit.pushing_pressure,
				"blocking_unit_pushing_pressure": pressure_blocker.pushing_pressure,
			})
			return {
				"obstructed": true,
				"moved": moved,
				"failure_reason": "push_pressure_pair_blocked",
			}
		unit.position = candidate
		unit.remember_position()
		moved = true
		remaining_distance -= move_distance
		if reaches_waypoint:
			unit.consume_current_waypoint()
	return {
		"obstructed": false,
		"moved": moved,
	}


func _effective_speed(unit: ZeroAdRtsLabUnit) -> float:
	if unit.pushing_pressure <= PUSH_PRESSURE_SPEED_THRESHOLD:
		return unit.speed
	var max_pressure := maxi(1, MAX_PUSH_PRESSURE - PUSH_PRESSURE_SPEED_THRESHOLD - MIN_PRESSURE_IF_OBSTRUCTED)
	var pressure_over_threshold := maxi(0, unit.pushing_pressure - PUSH_PRESSURE_SPEED_THRESHOLD)
	var slowdown := max_pressure - mini(max_pressure, pressure_over_threshold)
	var pressure_factor := float(slowdown) / float(max_pressure)
	return maxf(unit.speed * pressure_factor, unit.speed * PUSH_PRESSURE_SPEED_FLOOR_RATIO)


func _pressure_pair_blocker(
	unit: ZeroAdRtsLabUnit,
	candidate: Vector2,
	units: Array[ZeroAdRtsLabUnit]
) -> ZeroAdRtsLabUnit:
	if unit.control_group_id != "":
		return null
	for other in units:
		if other == unit:
			continue
		if not other.mobile or not other.blocks_pathfinding:
			continue
		if not other.has_move_order:
			continue
		if _same_control_group(unit, other):
			continue
		if maxi(unit.pushing_pressure, other.pushing_pressure) < MIN_PRESSURE_IF_OBSTRUCTED:
			continue
		var current_distance := unit.position.distance_to(other.position)
		var candidate_distance := candidate.distance_to(other.position)
		var max_distance := _push_max_distance(unit, other, 2, false)
		var pressure_distance := max_distance * MOVING_PUSH_SPREAD
		if candidate_distance <= pressure_distance and candidate_distance < current_distance - 0.0001:
			return other
	return null


func _request_long_path(
	unit: ZeroAdRtsLabUnit,
	goal: Vector2,
	pathfinder: ZeroAdRtsLabPathfinder,
	tick: int
) -> void:
	if unit.pending_short_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_short_ticket)
		_pending_short_path_contexts.erase(unit.pending_short_ticket)
		unit.pending_short_ticket = 0
		obsolete_path_requests += 1
		unit.note_order_metric("obsolete_path_requests")
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
		obsolete_path_requests += 1
		unit.note_order_metric("obsolete_path_requests")
	long_path_requests += 1
	unit.note_order_metric("long_path_requests")
	unit.pending_long_ticket = pathfinder.enqueue_long_path(unit, goal)
	_record_path_decision(unit, "long_path_requested", tick, {
		"goal": goal,
		"ticket": unit.pending_long_ticket,
	})


func _apply_long_path_result(unit: ZeroAdRtsLabUnit, result: SimNavLongPathResult, tick: int) -> void:
	path_results_applied += 1
	unit.note_order_metric("path_results_applied")
	if result.is_success():
		unit.long_path = result.path
		unit.short_path = SimNavWaypointPath.new()
		unit.path_target = result.canonical_goal.center if result.canonical_goal != null else unit.target
		_record_path_decision(unit, "long_path_result", tick, {
			"status": result.status,
			"failure_reason": result.failure_reason,
			"path_size": result.path.size(),
			"canonicalized": result.canonicalized,
			"canonical_goal": unit.path_target,
			"path": _path_snapshot(result.path),
		})
		_note_known_imperfect_path_if_needed(unit, true, tick)
	else:
		path_result_failures += 1
		unit.note_order_metric("path_result_failures")
		unit.long_path = SimNavWaypointPath.new()
		unit.path_target = unit.target
		_record_path_decision(unit, "long_path_result", tick, {
			"status": result.status,
			"failure_reason": result.failure_reason,
			"path_size": result.path.size(),
			"canonicalized": result.canonicalized,
			"canonical_goal": unit.path_target,
		})


func _request_short_path(
	unit: ZeroAdRtsLabUnit,
	goal: SimNavPathGoal,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	search_range: float = SHORT_PATH_MIN_SEARCH_RANGE,
	tick: int = 0,
	reason: String = "",
	request_context: Dictionary = {}
) -> bool:
	if unit.pending_short_ticket > 0:
		repath_suppressed += 1
		unit.note_order_metric("repath_suppressed")
		_record_path_decision(unit, "short_path_suppressed", tick, {
			"reason": "pending_short_ticket",
			"pending_short_ticket": unit.pending_short_ticket,
		})
		return false
	if unit.short_repath_cooldown > 0.0:
		repath_suppressed += 1
		unit.note_order_metric("repath_suppressed")
		_record_path_decision(unit, "short_path_suppressed", tick, {
			"reason": "short_repath_cooldown",
			"cooldown": unit.short_repath_cooldown,
		})
		return false
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
		obsolete_path_requests += 1
		unit.note_order_metric("obsolete_path_requests")
	short_path_requests += 1
	unit.note_order_metric("short_path_requests")
	unit.pending_short_ticket = pathfinder.enqueue_short_path(unit, goal, units, search_range)
	var context := request_context.duplicate(true)
	context["reason"] = reason
	context["requested_short_path_goal"] = goal.center if goal != null else Vector2.ZERO
	context["final_goal"] = unit.path_target
	context["ticket"] = unit.pending_short_ticket
	_pending_short_path_contexts[unit.pending_short_ticket] = context
	unit.short_repath_cooldown = SHORT_REPATH_COOLDOWN_SEC
	_record_path_decision(unit, "short_path_requested", tick, {
		"reason": reason,
		"goal": goal.center if goal != null else Vector2.ZERO,
		"requested_short_path_goal": goal.center if goal != null else Vector2.ZERO,
		"search_range": search_range,
		"ticket": unit.pending_short_ticket,
	})
	return true


func _apply_short_path_result(
	unit: ZeroAdRtsLabUnit,
	result: SimNavShortPathResult,
	ticket: int,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	tick: int
) -> void:
	path_results_applied += 1
	unit.note_order_metric("path_results_applied")
	var request_context: Dictionary = _pending_short_path_contexts.get(ticket, {}) as Dictionary
	_pending_short_path_contexts.erase(ticket)
	if result.is_success():
		unit.short_path = result.path
		_trim_regressive_short_waypoint(unit, pathfinder, units, tick)
		var details := {
			"status": result.status,
			"failure_reason": result.failure_reason,
			"path_size": result.path.size(),
			"path_length": result.path_length,
			"short_path_length": result.path_length,
			"path": _path_snapshot(result.path),
			# Surface vertex graph health so log readers can spot dense-cluster
			# scenarios (high covered_vertex_count) and best-effort fallback
			# paths (used_best_vertex_fallback=true → goal was unreachable).
			"covered_vertex_count": result.covered_vertex_count,
			"used_best_vertex_fallback": result.used_best_vertex_fallback,
		}
		_add_short_path_result_diagnostics(details, unit, request_context)
		_record_path_decision(unit, "short_path_result", tick, details)
		_note_known_imperfect_path_if_needed(unit, unit.long_path == null or unit.long_path.is_empty(), tick)
	else:
		path_result_failures += 1
		unit.note_order_metric("path_result_failures")
		var failure_details := {
			"status": result.status,
			"failure_reason": result.failure_reason,
			"path_size": result.path.size(),
			"path_length": result.path_length,
			"short_path_length": result.path_length,
		}
		_add_short_path_result_diagnostics(failure_details, unit, request_context)
		_record_path_decision(unit, "short_path_result", tick, failure_details)


func _trim_regressive_short_waypoint(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	tick: int
) -> void:
	if unit.short_path == null or unit.short_path.size() < 2:
		return
	var current_waypoint := unit.short_path.back()
	var next_index := unit.short_path.size() - 2
	var next_waypoint := unit.short_path.waypoints[next_index]
	var goal := SimNavPathGoal.point(unit.path_target)
	var current_goal_distance := goal.distance_to_point(unit.position)
	var first_goal_distance := goal.distance_to_point(current_waypoint)
	var second_goal_distance := goal.distance_to_point(next_waypoint)
	if first_goal_distance <= current_goal_distance + unit.radius:
		return
	if second_goal_distance >= first_goal_distance:
		return
	var line_result := pathfinder.validate_movement_line(unit, unit.position, next_waypoint, units, false)
	if not line_result.is_success():
		return
	unit.short_path.pop_back()
	_record_path_decision(unit, "skip_short_waypoint", tick, {
		"skipped_waypoint": current_waypoint,
		"next_waypoint": next_waypoint,
		"current_goal_distance": current_goal_distance,
		"skipped_goal_distance": first_goal_distance,
		"next_goal_distance": second_goal_distance,
	})


func _add_short_path_result_diagnostics(
	details: Dictionary,
	unit: ZeroAdRtsLabUnit,
	request_context: Dictionary
) -> void:
	var request_reason := String(request_context.get("reason", ""))
	if request_reason != "":
		details["request_reason"] = request_reason
	for key in [
		"takeover_policy",
		"blocked_waypoint",
		"skipped_waypoint",
		"skipped_blocked_waypoint",
		"requested_short_path_goal",
	]:
		if request_context.has(key):
			details[key] = request_context[key]
	var has_first_waypoint := unit.short_path != null and not unit.short_path.is_empty()
	var first_waypoint := Vector2.ZERO
	if has_first_waypoint:
		first_waypoint = unit.short_path.back()
	var current_goal_distance := unit.position.distance_to(unit.path_target)
	var first_goal_distance := first_waypoint.distance_to(unit.path_target)
	details["has_first_consumed_short_waypoint"] = has_first_waypoint
	details["first_consumed_short_waypoint"] = first_waypoint
	details["current_final_goal_distance"] = current_goal_distance
	details["first_short_waypoint_final_goal_distance"] = first_goal_distance
	details["first_short_waypoint_farther_from_final_goal"] = (
		has_first_waypoint
		and first_goal_distance > current_goal_distance + 0.01
	)


func _maybe_request_short_path_for_long_segment(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	tick: int
) -> bool:
	if unit.short_path != null and not unit.short_path.is_empty():
		return false
	if unit.pending_short_ticket > 0:
		return false
	if unit.long_path == null or unit.long_path.is_empty():
		return false
	if unit.follow_known_imperfect_path_countdown > 0:
		known_imperfect_suppressed += 1
		unit.note_order_metric("known_imperfect_suppressed")
		return false
	var blocked_waypoint: Vector2 = unit.long_path.back()
	var skipped_waypoint := _next_long_waypoint_after_blocked(unit)
	var unit_line := pathfinder.validate_unit_line(unit, unit.position, blocked_waypoint, units, false)
	if unit_line.is_success():
		return false
	var requested_goal := SimNavPathGoal.point(unit.path_target)
	var skipped_blocked_waypoint := false
	if unit.long_path.size() > 1:
		if long_segment_takeover_policy == LONG_SEGMENT_TAKEOVER_POLICY_0AD_SKIP_BLOCKED_WAYPOINT:
			unit.long_path.pop_back()
			requested_goal = SimNavPathGoal.circle(unit.long_path.back(), LONG_PATH_UNIT_LINE_SUBGOAL_RADIUS)
			skipped_blocked_waypoint = true
		else:
			requested_goal = SimNavPathGoal.circle(blocked_waypoint, LONG_PATH_UNIT_LINE_SUBGOAL_RADIUS)
	var requested_short_path_goal: Vector2 = requested_goal.center if requested_goal != null else Vector2.ZERO
	var takeover_context := {
		"takeover_policy": long_segment_takeover_policy,
		"blocked_waypoint": blocked_waypoint,
		"skipped_waypoint": skipped_waypoint,
		"skipped_blocked_waypoint": skipped_blocked_waypoint,
		"requested_short_path_goal": requested_short_path_goal,
	}
	_record_path_decision(unit, "long_segment_unit_line_blocked", tick, {
		"from": unit.position,
		"next_long": blocked_waypoint,
		"blocked_waypoint": blocked_waypoint,
		"skipped_waypoint": skipped_waypoint,
		"takeover_policy": long_segment_takeover_policy,
		"skipped_blocked_waypoint": skipped_blocked_waypoint,
		"requested_short_path_goal": requested_short_path_goal,
		"line": _line_result_snapshot(unit_line, units),
	})
	return _request_short_path(
		unit,
		requested_goal,
		pathfinder,
		units,
		_short_path_search_range(unit, false),
		tick,
		"long_segment_unit_line_blocked",
		takeover_context
	)


func _next_long_waypoint_after_blocked(unit: ZeroAdRtsLabUnit) -> Vector2:
	if unit.long_path == null or unit.long_path.size() < 2:
		return Vector2.ZERO
	return unit.long_path.waypoints[unit.long_path.size() - 2]


func _handle_blocked_move(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	moved: bool,
	tick: int,
	failure_reason: String = ""
) -> void:
	blocked_moves += 1
	unit.note_order_metric("blocked_moves")
	if not moved or unit.failed_movements < 2:
		if _increment_failed_movements_and_maybe_fail(unit, pathfinder, tick):
			return
		_note_obstructed(unit, tick)

	_record_path_decision(unit, "blocked_recovery", tick, {
		"moved_before_block": moved,
		"failed_movements": unit.failed_movements,
		"failure_reason": failure_reason,
	})
	var goal := SimNavPathGoal.point(unit.path_target)
	# Mirror 0 A.D. CCmpUnitMotion.h:1429-1430 — when the goal is in short
	# path range, fall through to ComputePathToGoal(POINT goal). Push-pressure
	# blockages must NOT divert into a circle subgoal around long_path.back():
	# the unit is typically already inside that radius, which makes
	# vertex_pathfinder's contains_point(start) fast-path return [start].
	# Motion then executes a 0-progress step while push pushes the unit back,
	# producing a 60 Hz oscillation and permanent overlap (log
	# zero_ad_rts_lab_2026-05-10T23-35-41). Static drift
	# (`passability_blocked`) keeps the long-route subgoal because a static
	# obstacle on the direct line still requires routing around it.
	var has_salvageable_long_path := unit.long_path != null and not unit.long_path.is_empty()
	var route_drift := (
		has_salvageable_long_path
		and failure_reason == SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED
	)
	if _in_short_path_range(goal, unit.position) and not route_drift:
		_compute_path_to_goal(unit, pathfinder, units, goal, tick)
		return
	if unit.short_path != null and not unit.short_path.is_empty() and unit.failed_movements == BACKUP_HACK_DELAY:
		var next := unit.short_path.back()
		var back_up := unit.position - next
		if back_up.length_squared() > 0.0001:
			unit.short_path.push_back(unit.position + back_up.normalized() * BACKUP_HACK_DISTANCE)
			return

	var skip_beyond := maxf(_short_path_search_range(unit, false) / 3.0, NAVCELL_SIZE * 8.0)
	if unit.long_path != null and unit.long_path.size() > 1 and unit.position.distance_to(unit.long_path.back()) < skip_beyond:
		_record_path_decision(unit, "skip_long_waypoint", tick, {
			"skip_distance": skip_beyond,
			"skipped_waypoint": unit.long_path.back(),
		})
		unit.long_path.pop_back()
	elif _should_alternate_pathfinder(unit):
		_request_long_path(unit, unit.path_target, pathfinder, tick)
		return

	if unit.long_path == null or unit.long_path.is_empty():
		_compute_path_to_goal(unit, pathfinder, units, goal, tick)
		return

	var radius := clampf(skip_beyond / 3.0, NAVCELL_SIZE * 4.0, NAVCELL_SIZE * 12.0)
	var subgoal := SimNavPathGoal.circle(unit.long_path.back(), radius)
	_request_short_path(
		unit,
		subgoal,
		pathfinder,
		units,
		_short_path_search_range(unit, false),
		tick,
		"blocked_recovery_subgoal"
	)


func _compute_path_to_goal(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	goal: SimNavPathGoal,
	tick: int
) -> void:
	if goal == null:
		return
	if unit.follow_known_imperfect_path_countdown > 0 and unit.has_path():
		known_imperfect_suppressed += 1
		unit.note_order_metric("known_imperfect_suppressed")
		_record_path_decision(unit, "path_to_goal_suppressed", tick, {
			"reason": "known_imperfect_path_countdown",
			"countdown": unit.follow_known_imperfect_path_countdown,
		})
		return
	if not _should_alternate_pathfinder(unit) and _try_going_straight_to_target(unit, pathfinder, units, false):
		unit.short_path = SimNavWaypointPath.new()
		_request_long_path(unit, goal.center, pathfinder, tick)
		return
	var use_short_path := _in_short_path_range(goal, unit.position)
	if _should_alternate_pathfinder(unit):
		use_short_path = not use_short_path
	if use_short_path:
		unit.long_path = SimNavWaypointPath.new()
		_request_short_path(
			unit,
			goal,
			pathfinder,
			units,
			_short_path_search_range(unit, true, goal),
			tick,
			"path_to_goal"
		)
	else:
		unit.short_path = SimNavWaypointPath.new()
		_request_long_path(unit, goal.center, pathfinder, tick)


func _increment_failed_movements_and_maybe_fail(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	tick: int
) -> bool:
	unit.failed_movements += 1
	if unit.failed_movements < MAX_FAILED_MOVEMENTS:
		return false
	_cancel_pending_path_requests(unit, pathfinder)
	move_failures += 1
	unit.note_order_metric("move_failures")
	_record_path_decision(unit, "move_failed", tick, {
		"reason": "max_failed_movements",
		"max_failed_movements": MAX_FAILED_MOVEMENTS,
	})
	_emit_motion_update(unit, MotionUpdateScript.TYPE_LIKELY_FAILURE, "max_failed_movements", tick)
	return true


func _try_going_straight_to_target(
	unit: ZeroAdRtsLabUnit,
	pathfinder: ZeroAdRtsLabPathfinder,
	units: Array[ZeroAdRtsLabUnit],
	update_paths: bool
) -> bool:
	if unit.short_path != null and not unit.short_path.is_empty():
		return false
	if unit.position.distance_to(unit.path_target) > DIRECT_PATH_RANGE:
		return false
	var line_result := pathfinder.validate_movement_line(unit, unit.position, unit.path_target, units, false)
	if not line_result.is_success():
		return false
	if not update_paths:
		return true
	unit.long_path = SimNavWaypointPath.new()
	unit.short_path = SimNavWaypointPath.new()
	unit.short_path.push_back(unit.path_target)
	return true


func _note_obstructed(unit: ZeroAdRtsLabUnit, tick: int) -> void:
	if unit.failed_movements < 2:
		_emit_clear_update_if_needed(unit, tick)
		return
	if unit.failed_movements >= VERY_OBSTRUCTED_THRESHOLD:
		_emit_obstruction_update_if_needed(
			unit,
			MotionUpdateScript.TYPE_VERY_OBSTRUCTED,
			"very_obstructed",
			tick
		)
	else:
		_emit_obstruction_update_if_needed(
			unit,
			MotionUpdateScript.TYPE_OBSTRUCTED,
			"obstructed",
			tick
		)


func _note_known_imperfect_path_if_needed(
	unit: ZeroAdRtsLabUnit,
	pathed_towards_goal: bool,
	tick: int
) -> void:
	if not pathed_towards_goal:
		return
	if not _pathing_update_needed(unit):
		return
	unit.follow_known_imperfect_path_countdown = KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN
	_emit_obstruction_update_if_needed(
		unit,
		MotionUpdateScript.TYPE_KNOWN_IMPERFECT,
		"known_imperfect_path",
		tick
	)


func _pathing_update_needed(unit: ZeroAdRtsLabUnit) -> bool:
	if not unit.has_move_order:
		return false
	if unit.follow_known_imperfect_path_countdown > 0 and unit.has_path():
		return false
	var goal := SimNavPathGoal.point(unit.path_target)
	if not unit.has_path():
		return true
	if _in_short_path_range(goal, unit.position) and unit.position.distance_to(unit.path_target) <= ARRIVE_EPSILON:
		return false
	var final_waypoint := _final_waypoint(unit.active_path())
	return goal.distance_to_point(final_waypoint) > ARRIVE_EPSILON


func _final_waypoint(path: SimNavWaypointPath) -> Vector2:
	if path == null or path.is_empty():
		return Vector2.ZERO
	return path.waypoints[0]


func _in_short_path_range(goal: SimNavPathGoal, position: Vector2) -> bool:
	if goal == null:
		return false
	return goal.distance_to_point(position) < LONG_PATH_MIN_DIST


func _short_path_search_range(
	unit: ZeroAdRtsLabUnit,
	extend_range: bool,
	goal: SimNavPathGoal = null
) -> float:
	var multiple := maxi(0, unit.failed_movements - SHORT_PATH_SEARCH_RANGE_INCREASE_DELAY)
	var search_range := SHORT_PATH_MIN_SEARCH_RANGE + SHORT_PATH_SEARCH_RANGE_INCREMENT * float(multiple)
	search_range = minf(search_range, SHORT_PATH_MAX_SEARCH_RANGE)
	if extend_range and goal != null:
		var goal_distance := unit.position.distance_to(goal.center)
		if goal_distance >= search_range - 1.0:
			search_range = minf(goal_distance + 1.0, SHORT_PATH_MAX_SEARCH_RANGE)
	return search_range


func _should_alternate_pathfinder(unit: ZeroAdRtsLabUnit) -> bool:
	if unit.failed_movements == ALTERNATE_PATH_TYPE_DELAY:
		return true
	return (
		unit.failed_movements > ALTERNATE_PATH_TYPE_DELAY
		and (unit.failed_movements - ALTERNATE_PATH_TYPE_DELAY) % ALTERNATE_PATH_TYPE_EVERY == 0
	)


func _emit_motion_update(
	unit: ZeroAdRtsLabUnit,
	update_type: String,
	reason: String,
	tick: int
) -> void:
	_motion_updates.append(MotionUpdateScript.new(
		unit.id,
		unit.active_order_id(),
		update_type,
		tick,
		unit.position,
		reason
	))


func _emit_clear_update_if_needed(unit: ZeroAdRtsLabUnit, tick: int) -> void:
	if not unit.was_obstructed and unit.obstruction_state == "":
		return
	_emit_motion_update(unit, MotionUpdateScript.TYPE_CLEAR, "", tick)


func _emit_obstruction_update_if_needed(
	unit: ZeroAdRtsLabUnit,
	update_type: String,
	next_state: String,
	tick: int
) -> void:
	if unit.obstruction_state == next_state:
		return
	match update_type:
		MotionUpdateScript.TYPE_OBSTRUCTED:
			obstructed_notifications += 1
			unit.note_order_metric("obstructed_notifications")
		MotionUpdateScript.TYPE_VERY_OBSTRUCTED:
			very_obstructed_notifications += 1
			unit.note_order_metric("very_obstructed_notifications")
		MotionUpdateScript.TYPE_KNOWN_IMPERFECT:
			known_imperfect_paths += 1
			unit.note_order_metric("known_imperfect_paths")
	_emit_motion_update(unit, update_type, "", tick)


func _record_path_decision(
	unit: ZeroAdRtsLabUnit,
	kind: String,
	tick: int,
	details: Dictionary = {}
) -> void:
	var active_path := unit.active_path()
	var entry := {
		"tick": tick,
		"kind": kind,
		"unit_id": unit.id,
		"order_id": unit.active_order_id(),
		"control_group_id": unit.control_group_id,
		"position": unit.position,
		"target": unit.target,
		"path_target": unit.path_target,
		"has_move_order": unit.has_move_order,
		"failed_movements": unit.failed_movements,
		"pushing_pressure": unit.pushing_pressure,
		"pending_long_ticket": unit.pending_long_ticket,
		"pending_short_ticket": unit.pending_short_ticket,
		"long_path_size": unit.long_path.size() if unit.long_path != null else 0,
		"short_path_size": unit.short_path.size() if unit.short_path != null else 0,
		"active_path_size": active_path.size() if active_path != null else 0,
	}
	for key in details.keys():
		entry[key] = details[key]
	_path_decisions.append(entry)
	while _path_decisions.size() > MAX_PATH_DECISION_LOG_ENTRIES:
		_path_decisions.pop_front()


func _line_result_snapshot(result: SimNavMovementLineResult, units: Array[ZeroAdRtsLabUnit]) -> Dictionary:
	if result == null:
		return {}
	var snapshot := {
		"status": result.status,
		"failure_reason": result.failure_reason,
		"blocked_obstruction_entity_id": result.blocked_obstruction_entity_id,
		"blocked_navcell": result.blocked_navcell,
	}
	var blocker := _find_unit(units, result.blocked_obstruction_entity_id)
	if blocker != null:
		snapshot["blocking_unit"] = {
			"id": blocker.id,
			"position": blocker.position,
			"radius": blocker.radius,
			"mobile": blocker.mobile,
			"has_move_order": blocker.has_move_order,
			"blocks_pathfinding": blocker.blocks_pathfinding,
			"obstruction_state": blocker.obstruction_state,
		}
	return snapshot


func _annotate_distance_to_blocker(
	snapshot: Dictionary,
	from: Vector2,
	candidate: Vector2,
	waypoint: Vector2,
	blocker_id: String,
	units: Array[ZeroAdRtsLabUnit]
) -> void:
	if blocker_id == "":
		return
	var blocker := _find_unit(units, blocker_id)
	if blocker == null:
		return
	var center := blocker.position
	snapshot["start_dist_to_blocker"] = from.distance_to(center)
	snapshot["candidate_dist_to_blocker"] = candidate.distance_to(center)
	snapshot["waypoint_dist_to_blocker"] = waypoint.distance_to(center)


func _path_snapshot(path: SimNavWaypointPath) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if path == null:
		return points
	for point in path.waypoints:
		points.append(point)
	return points


func _find_unit(units: Array[ZeroAdRtsLabUnit], unit_id: String) -> ZeroAdRtsLabUnit:
	if unit_id == "":
		return null
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func _cancel_pending_path_requests(unit: ZeroAdRtsLabUnit, pathfinder: ZeroAdRtsLabPathfinder) -> void:
	if unit.pending_long_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
	if unit.pending_short_ticket > 0:
		pathfinder.cancel_path_request(unit.pending_short_ticket)
		_pending_short_path_contexts.erase(unit.pending_short_ticket)
		unit.pending_short_ticket = 0


func _accumulate_pair_push(
	a: ZeroAdRtsLabUnit,
	b: ZeroAdRtsLabUnit,
	pushes: Dictionary,
	pressure_deltas: Dictionary,
	previous_positions: Dictionary,
	previous_move_orders: Dictionary,
	delta: float
) -> void:
	if not a.blocks_pathfinding or not b.blocks_pathfinding:
		return
	if not a.mobile or not b.mobile:
		return
	var a_was_moving := bool(previous_move_orders.get(a.id, a.has_move_order))
	var b_was_moving := bool(previous_move_orders.get(b.id, b.has_move_order))
	var moving_count := (1 if a_was_moving else 0) + (1 if b_was_moving else 0)
	var same_control_group := _same_control_group(a, b)
	if same_control_group:
		moving_count = 0
	if moving_count == 1:
		return
	var previous_a: Vector2 = previous_positions.get(a.id, a.position) as Vector2
	var previous_b: Vector2 = previous_positions.get(b.id, b.position) as Vector2
	var current_delta := a.position - b.position
	var previous_delta := previous_a - previous_b
	var average_delta := ((a.position + previous_a) - (b.position + previous_b)) * 0.5
	var distance := current_delta.length()
	var average_distance := average_delta.length()
	var max_distance := _push_max_distance(a, b, moving_count, same_control_group)
	var crossed_paths := (
		not same_control_group and
		moving_count == 2
		and previous_delta.dot(current_delta) < CROSSING_NUDGE_DOT_THRESHOLD
		and average_distance < max_distance
	)
	if average_distance >= max_distance and not crossed_paths:
		return
	var direction := Vector2.RIGHT
	if crossed_paths:
		var position_delta := current_delta - previous_delta
		var perpendicular := Vector2(-position_delta.y, position_delta.x)
		if perpendicular.length_squared() > 0.000001:
			direction = perpendicular.normalized()
			if average_delta.length_squared() > 0.000001 and average_delta.dot(direction) < 0.0:
				direction = -direction
		else:
			direction = _stable_pair_direction(a, b)
		crossing_nudges += 1
	elif average_distance > 0.001:
		direction = average_delta / average_distance
	elif distance > 0.001:
		direction = current_delta / distance
	else:
		direction = _stable_pair_direction(a, b)
	var push_strength := _push_distance_factor(average_distance, max_distance, moving_count)
	if crossed_paths:
		push_strength = maxf(push_strength, CROSSING_NUDGE_DISTANCE * MAX_DISTANCE_FACTOR)
	var time_factor := _push_time_factor(a, b, delta)
	var amount := minf(push_strength * time_factor, time_factor * MAX_PUSHING_MULTIPLIER)
	if amount > 0.0:
		pushes[a.id] = (pushes.get(a.id, Vector2.ZERO) as Vector2) + direction * amount
		pushes[b.id] = (pushes.get(b.id, Vector2.ZERO) as Vector2) - direction * amount
	var pressure_delta := _push_pressure_delta(average_distance, max_distance, moving_count)
	if asymmetric_push_pressure_enabled:
		if _unit_motion_faces(a, b, previous_positions):
			pressure_deltas[a.id] = int(pressure_deltas.get(a.id, 0)) + pressure_delta
		if _unit_motion_faces(b, a, previous_positions):
			pressure_deltas[b.id] = int(pressure_deltas.get(b.id, 0)) + pressure_delta
	else:
		pressure_deltas[a.id] = int(pressure_deltas.get(a.id, 0)) + pressure_delta
		pressure_deltas[b.id] = int(pressure_deltas.get(b.id, 0)) + pressure_delta


func _push_max_distance(
	a: ZeroAdRtsLabUnit,
	b: ZeroAdRtsLabUnit,
	moving_count: int,
	_same_control_group: bool
) -> float:
	# Mirror 0 A.D. CCmpUnitMotionManager::Push() max_dist formula. The
	# same-control-group exception is enforced upstream by zeroing
	# `moving_count` (see _accumulate_pair_push line ~1105), which routes
	# same-group pairs through the stopped-stopped extension. Returning
	# combined_radius here was a lab-only short-circuit that produced
	# weak push amounts (~0.29 px/tick at dist=19) and let arrived
	# formation members stay overlapping indefinitely. See
	# docs/0ad-unit-motion-policy-parity-audit.md "2026-05-11" entry.
	var combined_radius := a.radius + b.radius
	var combined_clearance := combined_radius * PUSHING_CORRECTION
	var extension := MOVING_PUSH_EXTENSION if moving_count > 0 else STATIC_PUSH_EXTENSION
	return combined_clearance * PUSHING_RADIUS_MULTIPLIER + extension


func _decay_push_pressure(units: Array[ZeroAdRtsLabUnit], delta: float) -> void:
	var decay := pow(PUSH_PRESSURE_DECAY, delta / PUSH_PRESSURE_DECAY_TURN_SEC)
	for unit in units:
		unit.pushing_pressure = int(floor(float(unit.pushing_pressure) * decay))


func _apply_push_pressure_deltas(units: Array[ZeroAdRtsLabUnit], pressure_deltas: Dictionary) -> void:
	for unit in units:
		var pressure_delta := int(pressure_deltas.get(unit.id, 0))
		if pressure_delta <= 0:
			continue
		unit.pushing_pressure = mini(MAX_PUSH_PRESSURE, unit.pushing_pressure + pressure_delta)


func _push_pressure_delta(distance: float, max_distance: float, moving_count: int) -> int:
	var distance_factor := _push_distance_factor(distance, max_distance, moving_count)
	var added_pressure := PRESSURE_STATIC_FACTOR + (distance_factor - (2.0 / 3.0)) * PRESSURE_DISTANCE_FACTOR
	return maxi(0, int(round(added_pressure)))


func _push_distance_factor(distance: float, max_distance: float, moving_count: int) -> float:
	var spread := MOVING_PUSH_SPREAD if moving_count > 0 else STATIC_PUSH_SPREAD
	var full_pressure_distance := max_distance * spread
	var distance_factor := max_distance - full_pressure_distance
	if distance_factor <= 0.0001 or distance < full_pressure_distance * 0.5:
		return MAX_DISTANCE_FACTOR
	return clampf((max_distance - distance) / distance_factor, 0.0, MAX_DISTANCE_FACTOR)


func _push_time_factor(a: ZeroAdRtsLabUnit, b: ZeroAdRtsLabUnit, delta: float) -> float:
	var reference_speed := maxf(maxf(a.speed, b.speed), PUSH_REFERENCE_SPEED)
	return reference_speed * delta / PUSHING_REDUCTION_FACTOR


func _unit_motion_faces(
	unit: ZeroAdRtsLabUnit,
	other: ZeroAdRtsLabUnit,
	previous_positions: Dictionary
) -> bool:
	var motion := _unit_motion_intent(unit, previous_positions)
	var motion_len_sq := motion.length_squared()
	if motion_len_sq <= MOTION_DEAD_ZONE_SQ:
		return false
	var to_other := other.position - unit.position
	var to_other_len_sq := to_other.length_squared()
	if to_other_len_sq <= MOTION_DEAD_ZONE_SQ:
		return false
	var dot := motion.dot(to_other)
	if dot <= 0.0:
		return false
	# cos(angle) = dot / (|motion| * |to_other|). Compare squared to avoid sqrt.
	return dot * dot > MOTION_FACING_COSINE_MIN * MOTION_FACING_COSINE_MIN * motion_len_sq * to_other_len_sq


func _unit_motion_intent(
	unit: ZeroAdRtsLabUnit,
	previous_positions: Dictionary
) -> Vector2:
	if unit.has_path():
		var wp := unit.current_waypoint()
		return wp - unit.position
	var prev: Vector2 = previous_positions.get(unit.id, unit.position) as Vector2
	return unit.position - prev


func _push_opposes_attempted_motion(
	unit: ZeroAdRtsLabUnit,
	push_vec: Vector2,
	previous_positions: Dictionary
) -> bool:
	if not unit.has_move_order:
		return false
	# 0 A.D. baseline check (CCmpUnitMotion_System.cpp:610-616): length-
	# dependent threshold. Acts as an implicit speed gate — fast units have
	# |attempted|² >> 0.5 and rarely trip; pressure-dampened slow units
	# trip easily, becoming "obstructed" and getting force-elevated to
	# pressure 80. See docs/custom-features/asymmetric-push-pressure.md
	# "Follow-up" for the leader-self-reinforcement failure mode.
	var previous_position: Vector2 = previous_positions.get(unit.id, unit.position) as Vector2
	var attempted_move := unit.position - previous_position
	if attempted_move.length_squared() <= 0.0001:
		return false
	var attempted_threshold_met := attempted_move.dot(attempted_move + push_vec) < 0.5
	if not asymmetric_push_pressure_enabled:
		return attempted_threshold_met
	# Asymmetric mode: keep the speed gate but additionally require
	# geometric opposition (motion intent points opposite to net push).
	# This filters out leaders whose attempted_move shrunk due to past
	# pressure-damping but whose motion intent is co-directional with
	# push (push pushing them forward, not blocking them).
	if not attempted_threshold_met:
		return false
	var motion := _unit_motion_intent(unit, previous_positions)
	if motion.length_squared() <= MOTION_DEAD_ZONE_SQ:
		return false
	return motion.dot(push_vec) < 0.0


func _mark_push_pressure_obstructed(
	unit: ZeroAdRtsLabUnit,
	pressure_obstructed_units: Array[ZeroAdRtsLabUnit]
) -> void:
	if unit.pushing_pressure <= PUSH_PRESSURE_OBSTRUCTED_THRESHOLD:
		return
	if pressure_obstructed_units.has(unit):
		return
	unit.was_obstructed = true
	unit.pushing_pressure = maxi(MIN_PRESSURE_IF_OBSTRUCTED, unit.pushing_pressure)
	push_pressure_obstructions += 1
	pressure_obstructed_units.append(unit)


func _dampen_pressure_push(unit: ZeroAdRtsLabUnit, push_vec: Vector2) -> Vector2:
	if unit.pushing_pressure <= 0:
		return push_vec
	var damped_pressure := mini(MAX_PUSH_DAMPING_PRESSURE, unit.pushing_pressure)
	var pressure_factor := float(MAX_PUSH_PRESSURE - damped_pressure) / float(MAX_PUSH_PRESSURE)
	return push_vec * pressure_factor


func _dampen_goal_opposing_push(unit: ZeroAdRtsLabUnit, push_vec: Vector2) -> Vector2:
	if not unit.has_move_order:
		return push_vec
	if unit.control_group_id != "":
		return push_vec
	var desired := unit.path_target - unit.position
	if desired.length_squared() <= 0.0001:
		return push_vec
	if desired.dot(push_vec) >= 0.0:
		return push_vec
	goal_opposing_push_dampens += 1
	return push_vec * GOAL_OPPOSING_PUSH_DAMPING


func _stable_pair_direction(a: ZeroAdRtsLabUnit, b: ZeroAdRtsLabUnit) -> Vector2:
	if a.id < b.id:
		return Vector2.RIGHT
	return Vector2.LEFT


func _same_control_group(a: ZeroAdRtsLabUnit, b: ZeroAdRtsLabUnit) -> bool:
	return a.control_group_id != "" and a.control_group_id == b.control_group_id


func _build_push_buckets(units: Array[ZeroAdRtsLabUnit]) -> Dictionary:
	var buckets := {}
	for unit in units:
		if not unit.blocks_pathfinding:
			continue
		var coord := _push_bucket_coord(unit.position)
		if not buckets.has(coord):
			buckets[coord] = []
		var bucket_units: Array = buckets[coord]
		bucket_units.append(unit)
	return buckets


func _nearby_push_units(unit: ZeroAdRtsLabUnit, buckets: Dictionary) -> Array[ZeroAdRtsLabUnit]:
	var result: Array[ZeroAdRtsLabUnit] = []
	var origin := _push_bucket_coord(unit.position)
	for offset in _push_bucket_neighbor_offsets():
		var coord := origin + offset
		if not buckets.has(coord):
			continue
		var bucket_units: Array = buckets[coord]
		for other in bucket_units:
			result.append(other)
	return result


func _push_bucket_coord(point: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(point.x / PUSH_BUCKET_SIZE)),
		int(floor(point.y / PUSH_BUCKET_SIZE))
	)


func _push_bucket_neighbor_offsets() -> Array[Vector2i]:
	return [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
