class_name Dota2LabMotionEngine
extends RefCounted

# Fable motion engine.
#
# Design stance (docs/design-notes/fable-motion-design.md): unit-vs-unit
# avoidance is NOT a pathfinding problem — it is a contact problem.
#
#   * Long paths only know the static world. Units never enter the nav map,
#     so there are no detour waypoints, no unit-aware line checks, and no
#     same-tick-staleness class of bugs.
#   * Every tick runs commit-then-resolve:
#       Phase A  intent step — each MOVING unit turns toward its tracking
#                point and steps along its own facing (never sideways).
#       Phase B  separation solve — iterative positional constraints split
#                overlapping unit pairs apart and project units out of static
#                shapes / map bounds. Facing is untouched: pushes move bodies,
#                not intentions, so crowd pressure cannot cause pirouettes.
#       Phase C  arrival + watchdog — reach the effective target, settle
#                near a crowded goal, or (after one replan) give up. Every
#                order terminates in bounded time; there is no holding loop.
#
# The engine keeps no per-unit state — everything lives on Dota2LabUnit — so
# one engine instance can drive any unit list (lab world, dota2-auto-battle
# adapter). Iteration follows array order everywhere: deterministic.

# ── Turn/step pipeline ───────────────────────────────────────────────────────
# Dota2's action cone: heading error below ~11.5° walks at full speed. Instead
# of a binary gate (the v1/v2 pirouette source), speed ramps linearly to zero
# as the error grows toward TURN_ALIGN_ZERO_RAD — continuous, so a small
# oscillation in desired heading cannot flip walk permission on and off.
const TURN_ALIGN_FULL_RAD := 0.20
const TURN_ALIGN_ZERO_RAD := 1.35

# ── Path following ───────────────────────────────────────────────────────────
const WAYPOINT_REACH := 6.0
const ARRIVE_RADIUS := 8.0
# Consuming a waypoint early when the next one is already in raster LOS turns
# corner chains into smooth arcs. Bounded pops per tick keep cost flat.
const SHORTCUT_MAX_POPS_PER_TICK := 2

# ── Separation solve ─────────────────────────────────────────────────────────
const SEPARATION_ITERATIONS := 6
const SEPARATION_SLACK := 0.01
# Relative pushability defaults. Soft (LoL-style): movers shove idle units
# aside. Hard (Dota2-style): idle pushability 0 — a stopped unit is a solid
# body (real creep-blocking blocks YOUR OWN creeps too). mobile == false is
# always pushability zero regardless of tuning.
const DEFAULT_PUSHABILITY_MOVING := 0.35
const DEFAULT_PUSHABILITY_IDLE := 1.0
const HARD_BLOCK_PUSHABILITY_IDLE := 0.0
# Head-on deadlock breaker: when a mover is pushing nearly nose-first into
# the other body (opposing mover, idle unit, or unpushable blocker), the pair
# correction gains a fixed-handedness lateral component. Opposing streams
# sort into lanes, idle units get shoved ASIDE instead of bulldozed forward,
# and a dead-center blocker contact gains the eccentricity sliding needs.
const HEAD_ON_ALIGN_DOT := 0.85
const HEAD_ON_LATERAL_BIAS := 0.6

# ── Watchdog ─────────────────────────────────────────────────────────────────
# "Stalled" = net displacement this tick under this fraction of a full step.
const STALL_MOVE_FRACTION := 0.25
# Near the goal, a stalled unit settles as arrived_crowded (Dota2: clicking
# into a crowd stops you at the crowd's edge).
const NEAR_GOAL_RADIUS := 60.0
const STALL_NEAR_COMPLETE_SEC := 0.7
# Far from the goal, one synchronous replan, then the order fails for good.
const STALL_REPATH_SEC := 1.5
const MAX_REPATHS := 1
# Pure turning-in-place is progress, not a stall.
const STALL_EXEMPT_SPEED_FACTOR := 0.05

const TRACE_SAMPLE_INTERVAL_TICKS := 4

const EVENT_ORDER_COMPLETED := "order_completed"
const EVENT_ORDER_FAILED := "order_failed"


# Read-only diagnostics from the most recent step() (frontend HUD / smokes).
var last_step_stats: Dictionary = {}

# Runtime push tuning — integrating projects set these to pick their contact
# flavor (lab UI drives them live). Keep pushability_moving > 0: two movers
# meeting head-on rely on it to resolve their overlap; at 0 they clip.
var pushability_moving: float = DEFAULT_PUSHABILITY_MOVING
var pushability_idle: float = DEFAULT_PUSHABILITY_IDLE


# ───────────────────────────── Command API ───────────────────────────────────

# Synchronous: the unit leaves this call either MOVING with a usable path or
# IDLE with a terminal order. A superseded active order fails as "cancelled".
func issue_move(
	unit: Dota2LabUnit,
	goal: Vector2,
	wrapper: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if unit == null or not unit.mobile or wrapper == null:
		return
	if unit.state == Dota2LabUnit.STATE_MOVING:
		unit.finish_order(tick, false, Dota2LabMoveOrder.REASON_CANCELLED)
	var clamped_goal := wrapper.clamp_to_playable(goal, unit.radius)
	unit.begin_order(clamped_goal, tick)
	_plan(unit, wrapper, tick)


func cancel_move(unit: Dota2LabUnit, tick: int) -> void:
	if unit == null or unit.state != Dota2LabUnit.STATE_MOVING:
		return
	unit.finish_order(tick, false, Dota2LabMoveOrder.REASON_CANCELLED)


# Re-plan an in-flight order after the static world changed. Resets the
# watchdog budget: the world is new, the order deserves a fresh chance.
func replan_active(
	unit: Dota2LabUnit,
	wrapper: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if unit == null or unit.state != Dota2LabUnit.STATE_MOVING:
		return
	unit.repath_count = 0
	unit.stall_seconds = 0.0
	_plan(unit, wrapper, tick)


# ───────────────────────────── Per-tick step ─────────────────────────────────

# Runs the full commit-then-resolve pipeline once. Returns terminal order
# events: {tick, unit_id, kind, order_id, reason, target: {x, y}}.
func step(
	units: Array[Dota2LabUnit],
	wrapper: Dota2LabPathfinderWrapper,
	delta: float,
	tick: int
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# Phase A: intent step.
	for unit in units:
		unit.prev_tick_position = unit.position
		if unit.state == Dota2LabUnit.STATE_MOVING:
			_advance_along_path(unit, wrapper, delta)

	# Phase B: separation solve.
	var stats := _resolve_overlaps(units, wrapper)

	# Phase C: arrival + watchdog.
	for unit in units:
		if unit.state == Dota2LabUnit.STATE_MOVING:
			_settle_or_watch(unit, wrapper, delta, tick, events)
		if unit.mobile and tick % TRACE_SAMPLE_INTERVAL_TICKS == 0:
			unit.remember_position()

	stats["events"] = events.size()
	last_step_stats = stats
	return events


# Largest remaining pair-overlap depth among mobile units (smoke invariant).
func max_overlap_depth(units: Array[Dota2LabUnit]) -> float:
	var deepest := 0.0
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			var a := units[i]
			var b := units[j]
			if not a.mobile and not b.mobile:
				continue
			var depth := (a.radius + b.radius) - a.position.distance_to(b.position)
			deepest = maxf(deepest, depth)
	return deepest


func diagnostics(units: Array[Dota2LabUnit]) -> Dictionary:
	var state_counts := {
		Dota2LabUnit.STATE_IDLE: 0,
		Dota2LabUnit.STATE_MOVING: 0,
	}
	for unit in units:
		state_counts[unit.state] = int(state_counts.get(unit.state, 0)) + 1
	return {
		"state_counts": state_counts,
		"last_step_stats": last_step_stats.duplicate(true),
	}


# ───────────────────────────── Planning ──────────────────────────────────────

func _plan(unit: Dota2LabUnit, wrapper: Dota2LabPathfinderWrapper, tick: int) -> void:
	var result := wrapper.plan_path(unit.position, unit.move_target)
	if not result.is_success():
		unit.finish_order(tick, false, Dota2LabMoveOrder.REASON_NO_PATH)
		return
	unit.path = result.path
	if result.has_path():
		unit.effective_target = result.path.waypoints[0]
	elif result.canonical_goal != null:
		unit.effective_target = result.canonical_goal.center
	else:
		unit.effective_target = unit.move_target
	if unit.current_order != null:
		unit.current_order.effective_target = unit.effective_target


# ───────────────────────────── Phase A ───────────────────────────────────────

func _advance_along_path(
	unit: Dota2LabUnit,
	wrapper: Dota2LabPathfinderWrapper,
	delta: float
) -> void:
	_shortcut_path(unit, wrapper)
	while unit.has_path() and unit.position.distance_to(unit.path.back()) <= WAYPOINT_REACH:
		unit.path.pop_back()

	var track := unit.current_waypoint()
	var to_track := track - unit.position
	var distance := to_track.length()
	if distance < 0.01:
		unit.last_speed_factor = 0.0
		unit.last_turn_delta_rad = 0.0
		return

	var desired := to_track.angle()
	unit.last_turn_delta_rad = angle_difference(unit.facing_angle_rad, desired)
	unit.facing_angle_rad = rotate_toward(
		unit.facing_angle_rad, desired, unit.turn_rate_rad_per_sec * delta
	)
	var remaining_error := absf(angle_difference(unit.facing_angle_rad, desired))
	var factor := _alignment_factor(remaining_error)
	unit.last_speed_factor = factor
	if factor <= 0.0:
		return
	var step_length := unit.speed * delta * factor
	if not unit.has_path():
		# Heading straight for the final point: never overshoot it (a step
		# past the goal reads as a wobble at 60 Hz).
		step_length = minf(step_length, distance)
	unit.position += Vector2.from_angle(unit.facing_angle_rad) * step_length


func _alignment_factor(heading_error: float) -> float:
	if heading_error <= TURN_ALIGN_FULL_RAD:
		return 1.0
	if heading_error >= TURN_ALIGN_ZERO_RAD:
		return 0.0
	return 1.0 - (heading_error - TURN_ALIGN_FULL_RAD) / (TURN_ALIGN_ZERO_RAD - TURN_ALIGN_FULL_RAD)


func _shortcut_path(unit: Dota2LabUnit, wrapper: Dota2LabPathfinderWrapper) -> void:
	var pops := 0
	while pops < SHORTCUT_MAX_POPS_PER_TICK and unit.path.size() >= 2:
		var next_waypoint: Vector2 = unit.path.waypoints[unit.path.size() - 2]
		if not wrapper.is_line_walkable(unit.position, next_waypoint):
			break
		unit.path.pop_back()
		pops += 1


# ───────────────────────────── Phase B ───────────────────────────────────────

func _resolve_overlaps(
	units: Array[Dota2LabUnit],
	wrapper: Dota2LabPathfinderWrapper
) -> Dictionary:
	var statics := wrapper.static_shapes()
	var rounds := 0
	for iteration in range(SEPARATION_ITERATIONS):
		rounds = iteration + 1
		var moved_any := false
		for i in range(units.size()):
			for j in range(i + 1, units.size()):
				if _separate_pair(units[i], units[j]):
					moved_any = true
		for unit in units:
			if unit.mobile and _project_out_of_world(unit, statics, wrapper):
				moved_any = true
		if not moved_any:
			break
	return {
		"separation_rounds": rounds,
		"max_residual_overlap": max_overlap_depth(units),
	}


func _separate_pair(a: Dota2LabUnit, b: Dota2LabUnit) -> bool:
	var min_distance := a.radius + b.radius
	var offset := b.position - a.position
	var distance := offset.length()
	if distance >= min_distance - SEPARATION_SLACK:
		return false
	var push_a := _pushability(a)
	var push_b := _pushability(b)
	var total := push_a + push_b
	if total <= 0.0:
		return false
	var direction: Vector2
	if distance > 0.001:
		direction = offset / distance
	else:
		# Perfectly coincident centers: deterministic split by id order.
		direction = Vector2.RIGHT if a.id < b.id else Vector2.LEFT
	direction = _head_on_biased(a, b, direction)
	var overlap := min_distance - distance
	var weight_a := push_a / total
	a.position -= direction * overlap * weight_a
	b.position += direction * overlap * (1.0 - weight_a)
	return true


func _pushability(unit: Dota2LabUnit) -> float:
	if not unit.mobile:
		return 0.0
	if unit.state == Dota2LabUnit.STATE_MOVING:
		return pushability_moving
	return pushability_idle


func _head_on_biased(a: Dota2LabUnit, b: Dota2LabUnit, direction: Vector2) -> Vector2:
	var head_on := false
	if a.state == Dota2LabUnit.STATE_MOVING \
			and absf(Vector2.from_angle(a.facing_angle_rad).dot(direction)) > HEAD_ON_ALIGN_DOT:
		head_on = true
	elif b.state == Dota2LabUnit.STATE_MOVING \
			and absf(Vector2.from_angle(b.facing_angle_rad).dot(direction)) > HEAD_ON_ALIGN_DOT:
		head_on = true
	if not head_on:
		return direction
	# Same-handed perpendicular for every pair: a and b get opposite lateral
	# nudges by construction (a -=, b +=), so both sidestep — never mirror-lock.
	var lateral := Vector2(-direction.y, direction.x)
	return (direction + lateral * HEAD_ON_LATERAL_BIAS).normalized()


func _project_out_of_world(
	unit: Dota2LabUnit,
	statics: Array[SimNavObstructionShapeStatic],
	wrapper: Dota2LabPathfinderWrapper
) -> bool:
	var moved := false
	for shape in statics:
		if _project_out_of_shape(unit, shape):
			moved = true
	var clamped := wrapper.clamp_to_playable(unit.position, unit.radius)
	if clamped != unit.position:
		unit.position = clamped
		moved = true
	return moved


# Circle-vs-OBB positional projection using exact geometry. Movement checks
# statics geometrically (paths keep the conservative raster band) — a pushed
# unit may legally brush closer to a wall than the planner would route it.
func _project_out_of_shape(unit: Dota2LabUnit, shape: SimNavObstructionShapeStatic) -> bool:
	var local := unit.position - shape.center
	if shape.rotation_rad != 0.0:
		local = local.rotated(-shape.rotation_rad)
	var half := Vector2(shape.width, shape.height) * 0.5
	var clamped := Vector2(
		clampf(local.x, -half.x, half.x),
		clampf(local.y, -half.y, half.y)
	)
	var delta := local - clamped
	var distance := delta.length()
	if clamped == local:
		# Center inside the rectangle: exit through the shallowest face.
		var exit_x := half.x - absf(local.x)
		var exit_y := half.y - absf(local.y)
		if exit_x <= exit_y:
			var sign_x := 1.0 if local.x >= 0.0 else -1.0
			local = Vector2((half.x + unit.radius) * sign_x, local.y)
		else:
			var sign_y := 1.0 if local.y >= 0.0 else -1.0
			local = Vector2(local.x, (half.y + unit.radius) * sign_y)
	elif distance < unit.radius:
		local = clamped + delta / distance * unit.radius
	else:
		return false
	if shape.rotation_rad != 0.0:
		local = local.rotated(shape.rotation_rad)
	unit.position = shape.center + local
	return true


# ───────────────────────────── Phase C ───────────────────────────────────────

func _settle_or_watch(
	unit: Dota2LabUnit,
	wrapper: Dota2LabPathfinderWrapper,
	delta: float,
	tick: int,
	events: Array[Dictionary]
) -> void:
	var goal_distance := unit.position.distance_to(unit.effective_target)
	if goal_distance <= ARRIVE_RADIUS:
		_complete(unit, tick, _arrival_reason(unit), events)
		return

	var progressed := goal_distance < unit.best_goal_distance - 0.5
	if progressed:
		unit.best_goal_distance = goal_distance
	var moved := unit.position.distance_to(unit.prev_tick_position)
	var moved_ok := moved >= unit.speed * delta * STALL_MOVE_FRACTION
	var turning_in_place := unit.last_speed_factor <= STALL_EXEMPT_SPEED_FACTOR \
		and absf(unit.last_turn_delta_rad) > 0.001
	if goal_distance <= NEAR_GOAL_RADIUS:
		# Near the goal, orbiting a crowd keeps displacement high while the
		# goal never gets closer — progress is the signal that matters.
		if turning_in_place or (moved_ok and progressed):
			unit.stall_seconds = 0.0
			return
		unit.stall_seconds += delta
		if unit.stall_seconds >= STALL_NEAR_COMPLETE_SEC:
			_complete(unit, tick, Dota2LabMoveOrder.REASON_ARRIVED_CROWDED, events)
		return

	if moved_ok or turning_in_place:
		unit.stall_seconds = 0.0
		return
	unit.stall_seconds += delta
	if unit.stall_seconds < STALL_REPATH_SEC:
		return
	if unit.repath_count < MAX_REPATHS:
		unit.repath_count += 1
		unit.stall_seconds = 0.0
		_plan(unit, wrapper, tick)
		if unit.state != Dota2LabUnit.STATE_MOVING:
			_append_terminal_event(unit, tick, events)
		return
	_fail(unit, tick, Dota2LabMoveOrder.REASON_STALLED, events)


func _arrival_reason(unit: Dota2LabUnit) -> String:
	if unit.current_order == null:
		return Dota2LabMoveOrder.REASON_ARRIVED
	var shortfall := unit.current_order.target.distance_to(unit.effective_target)
	if shortfall > ARRIVE_RADIUS * 1.5:
		return Dota2LabMoveOrder.REASON_ARRIVED_PARTIAL
	return Dota2LabMoveOrder.REASON_ARRIVED


func _complete(
	unit: Dota2LabUnit,
	tick: int,
	reason: String,
	events: Array[Dictionary]
) -> void:
	unit.finish_order(tick, true, reason)
	_append_terminal_event(unit, tick, events)


func _fail(
	unit: Dota2LabUnit,
	tick: int,
	reason: String,
	events: Array[Dictionary]
) -> void:
	unit.finish_order(tick, false, reason)
	_append_terminal_event(unit, tick, events)


func _append_terminal_event(unit: Dota2LabUnit, tick: int, events: Array[Dictionary]) -> void:
	if unit.last_order == null:
		return
	var kind := EVENT_ORDER_COMPLETED
	if unit.last_order.status == Dota2LabMoveOrder.STATUS_FAILED:
		kind = EVENT_ORDER_FAILED
	events.append({
		"tick": tick,
		"unit_id": unit.id,
		"kind": kind,
		"order_id": unit.last_order.order_id,
		"reason": unit.last_order.reason,
		"target": {"x": unit.last_order.target.x, "y": unit.last_order.target.y},
	})
