class_name Dota2LabMotionController
extends RefCounted

# Dota2 RTS Pathfinding Lab — motion controller.
#
# Implements the explicit state machine of
# docs/design-notes/movement-feel-policy.md (v2) over the skeleton fixed in
# motion-controller-design.md: six states per unit, fixed per-tick phase
# order, no magic-number-driven implicit transitions.
#
# v2 feel mechanisms (all lab policy, sim-nav-map core untouched):
#   M1 micro-detour waypoint — a step blocked by a PARKED unit inserts a
#      validated detour waypoint beside the blocker and walks to it through
#      the normal facing/step pipeline (waypoints inside the blocker's body
#      are popped first, 0 A.D. PostMove rule). Short path is the escalation
#      when no detour side validates, not the first response.
#   M2 two collision tiers — units WITH an active order phase past each
#      other (Dota2 crossing waves); units WITHOUT an order are solid at the
#      ½-raster-cell-relaxed radius (0 A.D. relaxClearanceForUnits). All
#      unit blocking runs against LIVE positions, never the per-tick
#      dynamic-shape snapshot.
#   M3 crowded arrive — a blocked unit already within a crowd ring of its
#      goal completes; the ring widens to a second ring once the recovery
#      budget is spent (concentric-ring group arrivals).
#   M4 HOLDING — recovery budget exhausted: keep the order, hold position,
#      retry a long path every HOLD_RETRY_INTERVAL_TICKS. FAILED is reachable
#      only from a statically unreachable long-path result.
#
# Critical invariant (NO_SAME_TICK_TAKEOVER): when step_unit() enqueues a
# short or long detour because of a block, it must NOT take a result, mutate
# the path, or move in the same tick. The unit transitions to a WAITING_*
# state and the function returns. (Walking a detour leg is movement along
# the unit's own path, not a takeover.)

const MotionUpdateScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_motion_update.gd")

const MAX_RETRY := 5
const ARRIVE_EPSILON := 4.0
const DOTA2_MOVE_START_ANGLE_RAD := 0.200712864  # 11.5 degrees
const FACING_DIRECTION_EPSILON_SQ := 0.000001
# Short-path search range. Conservative single value; 0AD scales by failure
# count, dota2 lab does not (recovery escalates to HOLDING instead).
const SHORT_PATH_SEARCH_RANGE := 12.0 * 16.0  # 12 navcells (world-scale)
const SHORT_PATH_SUBGOAL_RADIUS := 2.0 * 16.0
# M2: unit-vs-unit clearance relax as a fraction of the raster cell
# (0 A.D. relaxes by ½ navcell — Pathfinding "makes movement smoother").
# Applies against stationary blockers. Two units that are BOTH walking do
# not block each other at all: geometry proves a frontal meeting cannot
# route around a same-size blocker at any clearance the corridor allows
# (the approach chord is always shorter than both endpoints), which is why
# 0 A.D. resolves it with push and Dota 2 lets crossing creep waves press
# straight through each other. Movers therefore phase past movers; a unit
# that stops becomes solid again before anyone can stack on it.
const UNIT_CLEARANCE_RELAX_CELL_FACTOR := 0.5
# M1: detours inserted without real progress before escalating (a unit that
# keeps detouring is circling a crowd, not getting anywhere).
const DETOUR_STREAK_ESCALATE := 6
# M1: how far outside the combined radius the detour waypoint sits. Large
# enough that the approach line to the detour keeps ≥ the relaxed clearance
# from the blocker (chord math: 22·34/√(22²+34²) ≈ 18.5 > 18).
const DETOUR_MARGIN := 12.0
# M3: complete when blocked within ARRIVE_EPSILON + radius * this factor.
# The base factor covers a unit parked directly beside the goal occupant
# (first ring); the hold factor covers second-ring positions once the
# recovery budget is spent — a crowd ordered to one point settles as
# concentric rings, Dota2-style.
const CROWDED_ARRIVE_RADIUS_FACTOR := 2.0
const CROWDED_HOLD_RADIUS_FACTOR := 4.0
# M4: ticks between HOLDING long-path retries (BOUNDED_HOLDING_ACTIVITY).
const HOLD_RETRY_INTERVAL_TICKS := 30

# Counters surfaced via diagnostics(). Reset only by callers (typically once
# per test); the controller does not reset on its own.
var long_path_requests: int = 0
var short_path_requests: int = 0
var blocked_by_unit_count: int = 0
var blocked_by_static_count: int = 0
var move_failed_count: int = 0
var reached_goal_count: int = 0
var pending_count_peak: int = 0
var detour_count: int = 0
var crowded_arrive_count: int = 0
var holding_entered_count: int = 0

var _motion_updates: Array[Dota2LabMotionUpdate] = []


# ─────────────────────────── External entry points ───────────────────────────

# Called from world.issue_move(). Cancels any prior state, writes the new
# order data, and starts fresh.
func begin_new_move_order(
	unit: Dota2LabUnit,
	goal: Vector2,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	_cancel_pending(unit, pathfinder)
	unit.apply_move_order_data(goal, tick)
	_enqueue_long(unit, pathfinder, tick)


func cancel_move_order(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int,
	reason: String
) -> void:
	_cancel_pending(unit, pathfinder)
	unit.fail_order(tick, reason)
	unit.state = Dota2LabUnit.STATE_IDLE


# Called when world deletes/edits obstacles and any active mover needs a new
# long path. Equivalent to begin_new_move_order with the existing move_target
# but without replacing the current order.
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
	if unit.state == Dota2LabUnit.STATE_HOLDING:
		_step_holding(unit, pathfinder, tick)
		return
	if unit.state != Dota2LabUnit.STATE_FOLLOWING:
		return

	# Arrive check before walking. Exact-arrive only here; the crowded-arrive
	# tolerance (M3) applies when recovery finds the goal area occupied.
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
		if not _face_unit_toward(unit, to_waypoint, delta):
			return
		var reaches_waypoint := waypoint_distance <= remaining_distance
		var move_distance := waypoint_distance if reaches_waypoint else remaining_distance
		var candidate := waypoint if reaches_waypoint else unit.position + to_waypoint / waypoint_distance * move_distance

		# Statics/raster validate anchors on the waypoint (0AD PerformMove:
		# catching a fundamentally unreachable waypoint immediately beats
		# per-candidate slippage). Units are NOT in this filter — unit
		# blocking runs below against LIVE positions with mover/idle tiers,
		# which the once-per-tick dynamic snapshot cannot express.
		# A detour leg skips the raster DDA: its endpoint was geometry-
		# validated at insertion and may legally sit inside the raster band
		# (walking it through the DDA would reject the leg and loop the unit
		# forever); exact static geometry still applies.
		var walking_to_detour := (
			unit.active_detour_point != Vector2.INF
			and waypoint.distance_to(unit.active_detour_point) <= 0.01
		)
		if walking_to_detour:
			if not pathfinder.validate_slide_statics(unit, unit.position, waypoint):
				blocked_by_static_count += 1
				_handle_static_block(unit, pathfinder, tick)
				return
		else:
			var line_result := pathfinder.validate_movement_line(unit, unit.position, waypoint, units, false)
			if not line_result.is_success():
				blocked_by_static_count += 1
				_handle_static_block(unit, pathfinder, tick)
				return

		# Unit blocking, live positions, checked on the actual step segment.
		# A detour leg ignores the unit being rounded — the leg necessarily
		# hugs it and its endpoint clearance was proven at insertion.
		var leg_ignored_id := unit.active_detour_blocker_id if walking_to_detour else ""
		var live_blocker := _live_unit_violator(unit, unit.position, candidate, units, pathfinder, leg_ignored_id)
		if live_blocker != null:
			blocked_by_unit_count += 1
			# 0 A.D. PostMove pop rule: a waypoint sitting inside the
			# blocker's body is physically unreachable — skip it and aim for
			# the next one instead of orbiting the blocker forever.
			if (
				unit.path.size() > 1
				and waypoint.distance_to(live_blocker.position) < unit.radius + live_blocker.radius
			):
				unit.consume_current_waypoint()
				continue
			# M1: insert a micro-detour waypoint beside the blocker and let
			# the NORMAL facing/step pipeline walk to it (turn, then arc
			# around). Never displace sideways — that reads as ice-drift and
			# fights the turn gate into pirouettes.
			if _try_insert_detour(unit, live_blocker, waypoint, pathfinder, units):
				detour_count += 1
				continue
			_escalate_unit_block(unit, waypoint, pathfinder, tick)
			return

		unit.position = candidate
		unit.remember_position()
		unit.waiting_for_facing = false
		moved = true
		remaining_distance -= move_distance
		if reaches_waypoint:
			# Reaching the detour clears its marker; reaching a REAL waypoint
			# is progress and resets the detour streak entirely.
			if unit.active_detour_point != Vector2.INF and waypoint.distance_to(unit.active_detour_point) <= 0.01:
				unit.active_detour_point = Vector2.INF
				unit.active_detour_blocker_id = ""
			else:
				unit.clear_detour()
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
	# Accept only paths to the ORIGINAL goal. STATUS_CANONICALIZED (goal
	# rewritten to a reachable substitute) stays rejected — accepting it would
	# loop a caged unit toward an in-cage point forever. STATUS_START_RECOVERED
	# is accepted since v2: a slide may legally park the unit inside the static
	# raster band (geometry-clear), so a start recovered to the adjacent
	# passable navcell is normal; the first waypoint is at most a cell away
	# and the impassable-escape rule covers walking to it.
	var accepted := (
		result.status == SimNavLongPathResult.STATUS_SUCCESS
		or result.status == SimNavLongPathResult.STATUS_DIRECT_GOAL
		or result.status == SimNavLongPathResult.STATUS_START_RECOVERED
	)
	if accepted and result.path != null and not result.path.is_empty():
		unit.path = result.path
		unit.path_source = Dota2LabUnit.PATH_SOURCE_LONG
		unit.last_path_result_kind = Dota2LabUnit.PATH_SOURCE_LONG
		unit.last_path_result_status = result.status
		unit.last_path_failure_reason = ""
		unit.state = Dota2LabUnit.STATE_FOLLOWING
		return
	unit.last_path_result_kind = Dota2LabUnit.PATH_SOURCE_LONG
	unit.last_path_result_status = result.status
	unit.last_path_failure_reason = str(result.status)
	_terminal_failed(unit, "long_path_unreachable:" + str(result.status), tick)


func _handle_short_result(
	unit: Dota2LabUnit,
	result: SimNavShortPathResult,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if result.is_success() and result.path != null and not result.path.is_empty():
		unit.path = result.path
		unit.path_source = Dota2LabUnit.PATH_SOURCE_SHORT
		unit.last_path_result_kind = Dota2LabUnit.PATH_SOURCE_SHORT
		unit.last_path_result_status = result.status
		unit.last_path_failure_reason = ""
		unit.state = Dota2LabUnit.STATE_FOLLOWING
		return
	unit.last_path_result_kind = Dota2LabUnit.PATH_SOURCE_SHORT
	unit.last_path_result_status = result.status
	unit.last_path_failure_reason = result.failure_reason
	# Short detour failed. Crowded arrive (M3) first, then budget check:
	# exhausted budgets hold (M4) instead of terminally failing — other units
	# being in the way is never a terminal outcome (NEVER_FAILED_BY_UNITS).
	if _crowded_arrive(unit, tick):
		return
	unit.retry_count += 1
	if unit.retry_count > MAX_RETRY:
		_enter_holding(unit, tick)
		return
	_enqueue_long(unit, pathfinder, tick)


# Unit-blocked step whose relax + slide options are spent: crowded arrive,
# then short detour, then HOLDING once the recovery budget runs out.
func _escalate_unit_block(
	unit: Dota2LabUnit,
	blocked_waypoint: Vector2,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if _crowded_arrive(unit, tick):
		return
	if unit.last_short_range > 0.0:
		unit.retry_count += 1
		if unit.retry_count > MAX_RETRY:
			_enter_holding(unit, tick)
			return
	_enqueue_short(unit, blocked_waypoint, pathfinder, tick)


# Static block (PASSABILITY_BLOCKED / STATIC_OBSTRUCTION_BLOCKED /
# out-of-bounds): re-enqueue long. Statics don't move, so exhausted budgets
# drop to HOLDING's low-frequency retry; a retry whose long result is
# unreachable still terminates in FAILED via _handle_long_result.
func _handle_static_block(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	unit.retry_count += 1
	if unit.retry_count > MAX_RETRY:
		_enter_holding(unit, tick)
		return
	_enqueue_long(unit, pathfinder, tick)


# Unit-vs-unit clearance against LIVE positions (all unit blocking runs
# here — the movement-line filter excludes units, because the per-tick
# dynamic snapshot goes stale as soon as one unit moves and stale data lets
# pairs converge into overlap, after which the LOS inside-escape rule stops
# constraining them).
# Two tiers (M2): another MOVER only blocks at a half-body squeeze distance
# — opposing lane units press past each other, the Dota2 crossing feel; an
# IDLE unit blocks at the ½-cell-relaxed radius, so parked units are real
# obstacles. If an overlap somehow exists, movement that strictly increases
# separation is still allowed.
# Returns the first violating unit, or null when the segment is clear.
func _live_unit_violator(
	unit: Dota2LabUnit,
	from_pos: Vector2,
	to_pos: Vector2,
	units: Array[Dota2LabUnit],
	pathfinder: Dota2LabPathfinderWrapper,
	ignored_id: String = ""
) -> Dota2LabUnit:
	var idle_relax := pathfinder.cell_size * UNIT_CLEARANCE_RELAX_CELL_FACTOR
	for other in units:
		if other.id == unit.id or other.id == ignored_id or not other.blocks_pathfinding:
			continue
		# Units WITH an active move order phase past each other (see
		# UNIT_CLEARANCE_RELAX_CELL_FACTOR note). Order-based, not
		# FOLLOWING-based: a crowd squeezing through a chokepoint cycles
		# through WAITING/HOLDING states, and treating those as solid turns
		# three units at a doorway into a mutual-blocking carousel.
		if other.current_order != null:
			continue
		var combined := maxf(unit.radius + other.radius - idle_relax, 1.0)
		var current_distance := from_pos.distance_to(other.position)
		if current_distance < combined:
			if to_pos.distance_to(other.position) <= current_distance:
				return other
			continue
		if _segment_point_distance(from_pos, to_pos, other.position) < combined:
			return other
	return null


func _segment_point_distance(a: Vector2, b: Vector2, point: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq <= 0.000001:
		return a.distance_to(point)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(point)


# M1: insert a micro-detour waypoint beside the blocking unit. The detour
# sits on the tangent side that makes progress toward the blocked waypoint;
# head-on meetings resolve symmetrically (both movers pick opposite sides),
# so opposing units arc past each other deterministically. The unit then
# WALKS to the detour through the normal facing/step pipeline — never a
# sideways displacement.
# The approach line is validated against LIVE unit positions plus exact
# static geometry (no static raster DDA — the band steals legal side-step
# room in narrow gaps; a detour may legally sit inside the band and the core
# impassable-escape rule walks the unit back out).
func _try_insert_detour(
	unit: Dota2LabUnit,
	blocker: Dota2LabUnit,
	blocked_waypoint: Vector2,
	pathfinder: Dota2LabPathfinderWrapper,
	units: Array[Dota2LabUnit]
) -> bool:
	if blocker == null:
		return false
	# Blocked again while already walking toward a detour, or detouring
	# without progress for too long: stop stacking detours and escalate.
	if unit.active_detour_point != Vector2.INF:
		return false
	if unit.detour_streak >= DETOUR_STREAK_ESCALATE:
		return false
	var radial := unit.position - blocker.position
	if radial.length_squared() <= 0.000001:
		return false
	radial = radial.normalized()
	var side := Vector2(-radial.y, radial.x)
	if side.dot(blocked_waypoint - unit.position) < 0.0:
		side = -side
	# Only stationary units reach here (movers phase past movers), so the
	# detour always gets the full walk-around offset.
	var offset := unit.radius + blocker.radius + DETOUR_MARGIN
	var sides: Array[Vector2] = [side, -side]
	for side_dir in sides:
		var detour := blocker.position + side_dir * offset
		# The approach line to the detour is validated ignoring the blocker
		# being rounded: a walk-around necessarily hugs it (the approach chord
		# is always shorter than both endpoints — checking it against the
		# blocker would reject every close-range detour), and the endpoint at
		# combined + DETOUR_MARGIN guarantees no overlap on arrival.
		if _live_unit_violator(unit, unit.position, detour, units, pathfinder, blocker.id) != null:
			continue
		if not pathfinder.validate_slide_statics(unit, unit.position, detour):
			continue
		unit.path.push_back(detour)
		unit.active_detour_point = detour
		unit.active_detour_blocker_id = blocker.id
		unit.detour_streak += 1
		return true
	return false


# M3: a blocked unit already within a crowd ring of its goal treats the goal
# area as occupied and completes.
func _crowded_arrive(unit: Dota2LabUnit, tick: int, radius_factor: float = CROWDED_ARRIVE_RADIUS_FACTOR) -> bool:
	var crowd_radius := ARRIVE_EPSILON + unit.radius * radius_factor
	if unit.position.distance_to(unit.move_target) > crowd_radius:
		return false
	crowded_arrive_count += 1
	_finish_arrived(unit, tick)
	return true


# M4: enter HOLDING — order retained, position held, periodic long retries.
# The budget being spent means the first ring is full; accept a second-ring
# stop before parking.
func _enter_holding(unit: Dota2LabUnit, tick: int) -> void:
	if _crowded_arrive(unit, tick, CROWDED_HOLD_RADIUS_FACTOR):
		return
	_emit_motion_update(unit, Dota2LabMotionUpdate.TYPE_MOVE_HOLDING, "unit_blocked_hold", tick)
	unit.hold_position(HOLD_RETRY_INTERVAL_TICKS)
	holding_entered_count += 1


func _step_holding(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if _crowded_arrive(unit, tick, CROWDED_HOLD_RADIUS_FACTOR):
		return
	unit.hold_retry_countdown -= 1
	if unit.hold_retry_countdown > 0:
		return
	_enqueue_long(unit, pathfinder, tick)


func _enqueue_long(
	unit: Dota2LabUnit,
	pathfinder: Dota2LabPathfinderWrapper,
	_tick: int
) -> void:
	_cancel_pending(unit, pathfinder)
	unit.path = SimNavWaypointPath.new()
	unit.path_source = Dota2LabUnit.PATH_SOURCE_NONE
	unit.last_path_request_kind = Dota2LabUnit.PATH_SOURCE_LONG
	unit.pending_long_ticket = pathfinder.enqueue_long_path(unit, unit.move_target)
	unit.state = Dota2LabUnit.STATE_WAITING_LONG
	long_path_requests += 1
	_track_pending_peak(pathfinder)


# CRITICAL: enqueues short request and freezes the current path. Must NOT
# take the result, mutate path, or move this tick. Caller (step_unit on
# block) returns immediately after calling this.
func _enqueue_short(
	unit: Dota2LabUnit,
	blocked_waypoint: Vector2,
	pathfinder: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	# Cancel any prior pending long (target switch case is handled by
	# begin_new_move_order; this branch only fires from step_unit when a block
	# is detected mid-FOLLOWING, in which case pending_long is 0).
	if unit.pending_long_ticket > 0:
		pathfinder.cancel(unit.pending_long_ticket)
		unit.pending_long_ticket = 0
	# Path is intentionally NOT cleared — the next tick's apply_path_results
	# may install a short detour that replaces it. If the short fails, the
	# long re-enqueue clears it. Keeping it here is harmless because state
	# is WAITING_SHORT, not FOLLOWING, and step_unit short-circuits.
	var short_goal_center := _short_path_subgoal(unit, blocked_waypoint)
	var goal := SimNavPathGoal.circle(short_goal_center, SHORT_PATH_SUBGOAL_RADIUS)
	unit.last_path_request_kind = Dota2LabUnit.PATH_SOURCE_SHORT
	unit.last_short_goal = short_goal_center
	unit.last_short_range = SHORT_PATH_SEARCH_RANGE
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


func _short_path_subgoal(unit: Dota2LabUnit, blocked_waypoint: Vector2) -> Vector2:
	var to_waypoint := blocked_waypoint - unit.position
	var waypoint_distance := to_waypoint.length()
	if waypoint_distance <= 0.001:
		return blocked_waypoint
	var max_center_distance := maxf(SHORT_PATH_SEARCH_RANGE, unit.radius + 1.0)
	if waypoint_distance <= max_center_distance:
		return blocked_waypoint
	return unit.position + to_waypoint / waypoint_distance * max_center_distance


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


func _face_unit_toward(unit: Dota2LabUnit, direction: Vector2, delta: float) -> bool:
	if direction.length_squared() <= FACING_DIRECTION_EPSILON_SQ:
		unit.last_turn_delta_rad = 0.0
		unit.waiting_for_facing = false
		return true
	var desired_angle := direction.angle()
	unit.desired_facing_angle_rad = desired_angle
	var max_turn := maxf(unit.turn_rate_rad_per_sec, 0.0) * maxf(delta, 0.0)
	var turn_delta := _angle_delta(unit.facing_angle_rad, desired_angle)
	if max_turn <= 0.0:
		unit.last_turn_delta_rad = 0.0
		unit.waiting_for_facing = absf(turn_delta) > DOTA2_MOVE_START_ANGLE_RAD
		return not unit.waiting_for_facing
	var applied_turn := clampf(turn_delta, -max_turn, max_turn)
	unit.facing_angle_rad = _normalize_angle(unit.facing_angle_rad + applied_turn)
	unit.last_turn_delta_rad = applied_turn
	var remaining_delta := absf(_angle_delta(unit.facing_angle_rad, desired_angle))
	unit.waiting_for_facing = remaining_delta > DOTA2_MOVE_START_ANGLE_RAD
	return not unit.waiting_for_facing


func _angle_delta(from_angle_rad: float, to_angle_rad: float) -> float:
	return _normalize_angle(to_angle_rad - from_angle_rad)


func _normalize_angle(angle_rad: float) -> float:
	return fposmod(angle_rad + PI, TAU) - PI


# ─────────────────────────── Diagnostics ─────────────────────────────────────

func diagnostics(units: Array[Dota2LabUnit]) -> Dictionary:
	var state_counts := {
		Dota2LabUnit.STATE_IDLE: 0,
		Dota2LabUnit.STATE_WAITING_LONG: 0,
		Dota2LabUnit.STATE_FOLLOWING: 0,
		Dota2LabUnit.STATE_WAITING_SHORT: 0,
		Dota2LabUnit.STATE_HOLDING: 0,
		Dota2LabUnit.STATE_FAILED: 0,
	}
	var retry_count_max := 0
	var waiting_for_facing_count := 0
	for unit in units:
		state_counts[unit.state] = int(state_counts.get(unit.state, 0)) + 1
		if unit.retry_count > retry_count_max:
			retry_count_max = unit.retry_count
		if unit.waiting_for_facing:
			waiting_for_facing_count += 1
	return {
		"long_path_requests": long_path_requests,
		"short_path_requests": short_path_requests,
		"blocked_by_unit_count": blocked_by_unit_count,
		"blocked_by_static_count": blocked_by_static_count,
		"move_failed_count": move_failed_count,
		"reached_goal_count": reached_goal_count,
		"pending_count_peak": pending_count_peak,
		"detour_count": detour_count,
		"crowded_arrive_count": crowded_arrive_count,
		"holding_entered_count": holding_entered_count,
		"state_counts": state_counts,
		"retry_count_max": retry_count_max,
		"waiting_for_facing_count": waiting_for_facing_count,
	}


func _unused(_v) -> void:
	pass
