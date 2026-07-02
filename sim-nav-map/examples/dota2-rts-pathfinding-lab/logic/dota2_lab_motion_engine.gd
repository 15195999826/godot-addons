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

# ── Contact steering ─────────────────────────────────────────────────────────
# When a unit closes on a body that will NOT yield to it (equal or lower
# pushability, or an immobile blocker), its desired heading gains a smooth
# tangential bias — it walks around the contact instead of being ferried
# sideways by the separation solve. Heading, displacement, and visuals stay
# aligned (no "translation" look while squeezing past). The bias handedness
# matches the solve's head-on lateral bias exactly, so intent and push never
# fight. Phase B still resolves any residual overlap.
const CONTACT_STEER_GAP_RANGE := 8.0
const CONTACT_STEER_FRONT_DOT_MIN := 0.3
const CONTACT_STEER_WEIGHT := 0.9
# Go-around side is chosen by geometry (which side of the contact the unit's
# intended direction already leans toward), locked on the unit while contact
# persists so it cannot flip-flop mid-squeeze. Below the dead-zone (true
# dead-center) a fixed handedness breaks the tie deterministically.
const CONTACT_STEER_SIDE_DEADZONE := 0.05

# ── Deferred planning ────────────────────────────────────────────────────────
# Plans are queued and time-sliced (one JPS query per tick — a query costs
# 4-40 ms, so computing a whole group command in one frame froze it for
# ~250 ms). A freshly ordered unit starts walking a straight-line placeholder
# immediately (instant command response, Dota2 feel); the engine swaps in the
# real path the tick its result lands. Static projection covers the
# placeholder brushing a wall for those few ticks.

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
# flavor (lab UI drives them live). Any value in [0, 1] is safe: overlap
# between mobile bodies is always resolved, 0 just means "yields nothing in
# mixed contacts" (both-zero pairs split evenly — rigid, not ghost). Note
# mover-vs-mover contacts normalize to 50/50 regardless of the moving value;
# the sliders really tune WHO yields in mover-vs-idle contacts.
var pushability_moving: float = DEFAULT_PUSHABILITY_MOVING
var pushability_idle: float = DEFAULT_PUSHABILITY_IDLE
# Steer-around-contacts (see constants above). Off = pre-steering behavior:
# squeezing past a non-yielding body reads as sideways translation.
var contact_steering_enabled: bool = true
# Above this unit count the pair pass switches from the all-pairs loop to a
# uniform-grid neighbor query producing the SAME pairs in the SAME order
# (welded bitwise by smoke_dota2_lab_separation_hash). Public so the weld
# smoke can force either path; gameplay never needs to touch it.
var separation_brute_force_max: int = 16


# ───────────────────────────── Command API ───────────────────────────────────

# The unit starts walking immediately: a straight-line placeholder path
# toward the goal, replaced by the worker's real path when it lands. A
# superseded active order fails as "cancelled".
func issue_move(
	unit: Dota2LabUnit,
	goal: Vector2,
	wrapper: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if unit == null or not unit.mobile or wrapper == null:
		return
	if unit.state == Dota2LabUnit.STATE_MOVING:
		_drop_pending_plan(unit, wrapper)
		unit.finish_order(tick, false, Dota2LabMoveOrder.REASON_CANCELLED)
	var clamped_goal := wrapper.clamp_to_playable(goal, unit.radius)
	unit.begin_order(clamped_goal, tick)
	unit.path.push_back(clamped_goal)
	_request_plan(unit, wrapper)


func cancel_move(
	unit: Dota2LabUnit,
	wrapper: Dota2LabPathfinderWrapper,
	tick: int
) -> void:
	if unit == null or unit.state != Dota2LabUnit.STATE_MOVING:
		return
	if wrapper != null:
		_drop_pending_plan(unit, wrapper)
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
	_request_plan(unit, wrapper)


# After a nav rebuild the queue is fresh and old tickets are meaningless —
# clear them before replanning so no unit waits on a ghost ticket.
func invalidate_pending_plans(units: Array[Dota2LabUnit]) -> void:
	for unit in units:
		unit.pending_plan_ticket = 0


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

	# Phase 0: pump the plan worker and apply landed results.
	wrapper.pump_async()
	var plans_applied := 0
	for unit in units:
		if unit.pending_plan_ticket <= 0:
			continue
		var plan := wrapper.take_plan_result(unit.pending_plan_ticket)
		if plan == null:
			continue
		unit.pending_plan_ticket = 0
		if unit.state != Dota2LabUnit.STATE_MOVING:
			continue  # order ended while the plan was in flight
		_apply_plan_result(unit, plan, tick, events)
		plans_applied += 1

	# Phase A: intent step. Contact steering scans neighbors; above the
	# brute-force threshold it queries a position hash instead of every unit
	# (same others, same order — welded by the separation-hash smoke).
	var steer_cell := 0.0
	var steer_buckets: Dictionary = {}
	if contact_steering_enabled and units.size() > separation_brute_force_max:
		steer_cell = _steering_hash_cell_size(units, delta)
		steer_buckets = _build_position_buckets(units, steer_cell)
	for unit in units:
		unit.prev_tick_position = unit.position
		if unit.state == Dota2LabUnit.STATE_MOVING:
			_advance_along_path(unit, wrapper, delta, units, steer_buckets, steer_cell)

	# Phase B: separation solve.
	var stats := _resolve_overlaps(units, wrapper)

	# Phase C: arrival + watchdog.
	for unit in units:
		if unit.state == Dota2LabUnit.STATE_MOVING:
			_settle_or_watch(unit, wrapper, delta, tick, events)
		if unit.mobile and tick % TRACE_SAMPLE_INTERVAL_TICKS == 0:
			unit.remember_position()

	var plans_waiting := 0
	for unit in units:
		if unit.pending_plan_ticket > 0:
			plans_waiting += 1
	stats["events"] = events.size()
	stats["plans_applied"] = plans_applied
	stats["plans_waiting"] = plans_waiting
	last_step_stats = stats
	return events


# Largest remaining pair-overlap depth among mobile units (smoke invariant).
# Runs every tick as a step stat, so above the brute threshold it queries a
# position hash — exact, not approximate: any overlapping pair sits in
# adjacent buckets, and separated pairs only contribute negative depths that
# can never win the max.
func max_overlap_depth(units: Array[Dota2LabUnit]) -> float:
	if units.size() > separation_brute_force_max:
		return _max_overlap_depth_hashed(units)
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


func _max_overlap_depth_hashed(units: Array[Dota2LabUnit]) -> float:
	var cell_size := _separation_hash_cell_size(units)
	var buckets := _build_position_buckets(units, cell_size)
	var deepest := 0.0
	for i in range(units.size()):
		var a := units[i]
		var base_x := floori(a.position.x / cell_size)
		var base_y := floori(a.position.y / cell_size)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var bucket: Array = buckets.get(Vector2i(base_x + ox, base_y + oy), [])
				for j in bucket:
					if j <= i:
						continue
					var b: Dota2LabUnit = units[j]
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

func _request_plan(unit: Dota2LabUnit, wrapper: Dota2LabPathfinderWrapper) -> void:
	_drop_pending_plan(unit, wrapper)
	unit.pending_plan_ticket = wrapper.request_plan(unit.position, unit.move_target)


func _drop_pending_plan(unit: Dota2LabUnit, wrapper: Dota2LabPathfinderWrapper) -> void:
	if unit.pending_plan_ticket <= 0:
		return
	wrapper.cancel_plan(unit.pending_plan_ticket)
	unit.pending_plan_ticket = 0


func _apply_plan_result(
	unit: Dota2LabUnit,
	result: SimNavLongPathResult,
	tick: int,
	events: Array[Dictionary]
) -> void:
	if not result.is_success():
		unit.finish_order(tick, false, Dota2LabMoveOrder.REASON_NO_PATH)
		_append_terminal_event(unit, tick, events)
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
	delta: float,
	units: Array[Dota2LabUnit],
	steer_buckets: Dictionary = {},
	steer_cell: float = 0.0
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
	if contact_steering_enabled:
		desired = _contact_steered_heading(unit, to_track / distance, units, steer_buckets, steer_cell)
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


# Blend a tangential bias into the desired heading for every non-yielding
# body the unit is closing on nose-first. Continuous in all inputs (gap,
# frontness), so the heading cannot flip-flop; the shared handedness formula
# (-perp of the direction to the other body) is exactly the side Phase B's
# lateral bias pushes this unit toward — both pairs' members bias toward
# their own right, which is what makes opposing streams lane-sort.
func _contact_steered_heading(
	unit: Dota2LabUnit,
	toward_track: Vector2,
	units: Array[Dota2LabUnit],
	steer_buckets: Dictionary = {},
	steer_cell: float = 0.0
) -> float:
	var my_push := _pushability(unit)
	var steered := toward_track
	var any_contact := false
	if steer_cell <= 0.0:
		for other in units:
			var contribution := _steer_contribution(unit, other, toward_track, my_push)
			if contribution.z > 0.0:
				any_contact = true
				steered += Vector2(contribution.x, contribution.y)
	else:
		# Same others in the same array order (sorted indices): the steer
		# accumulation is float-order-sensitive, and pruned far bodies
		# contribute nothing in the full loop either.
		var base_x := floori(unit.position.x / steer_cell)
		var base_y := floori(unit.position.y / steer_cell)
		var candidates: Array[int] = []
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var bucket: Array = steer_buckets.get(Vector2i(base_x + ox, base_y + oy), [])
				for candidate in bucket:
					candidates.append(candidate)
		candidates.sort()
		for candidate in candidates:
			var contribution := _steer_contribution(unit, units[candidate], toward_track, my_push)
			if contribution.z > 0.0:
				any_contact = true
				steered += Vector2(contribution.x, contribution.y)
	if not any_contact:
		unit.steer_side = 0.0
	return steered.angle()


# One body's steering contribution: (x, y) = heading bias, z = 1 when this
# body counts as a contact (even at zero bias — contact keeps steer_side
# locked). Shared verbatim by the full loop and the hashed loop.
func _steer_contribution(
	unit: Dota2LabUnit,
	other: Dota2LabUnit,
	toward_track: Vector2,
	my_push: float
) -> Vector3:
	if other == unit:
		return Vector3.ZERO
	# Only steer around bodies that will not yield to this unit: an
	# immobile blocker, or anything at equal-or-lower pushability. Softer
	# bodies get shoved by the solve instead — no need to walk around.
	if other.mobile and _pushability(other) > my_push + 0.001:
		return Vector3.ZERO
	var offset := other.position - unit.position
	var gap := offset.length() - (unit.radius + other.radius)
	if gap > CONTACT_STEER_GAP_RANGE:
		return Vector3.ZERO
	var to_other := offset.normalized()
	var frontness_dot := toward_track.dot(to_other)
	if frontness_dot < CONTACT_STEER_FRONT_DOT_MIN:
		return Vector3.ZERO
	if unit.steer_side == 0.0:
		unit.steer_side = _pick_steer_side(to_other, toward_track)
	var proximity := clampf(1.0 - gap / CONTACT_STEER_GAP_RANGE, 0.0, 1.0)
	var frontness := (frontness_dot - CONTACT_STEER_FRONT_DOT_MIN) \
		/ (1.0 - CONTACT_STEER_FRONT_DOT_MIN)
	var around := Vector2(-to_other.y, to_other.x) * unit.steer_side
	var bias := around * (proximity * frontness * CONTACT_STEER_WEIGHT)
	return Vector3(bias.x, bias.y, 1.0)


# Which side to walk around: the side the intended direction already leans
# toward (nearest side). Dead-center falls back to a fixed handedness.
func _pick_steer_side(to_other: Vector2, intent_dir: Vector2) -> float:
	var lean := to_other.cross(intent_dir)
	if absf(lean) <= CONTACT_STEER_SIDE_DEADZONE:
		return -1.0
	return signf(lean)


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
	var static_bounds := _static_reach_bounds(statics, units)
	var rounds := 0
	var use_hash := units.size() > separation_brute_force_max
	var hash_cell := _separation_hash_cell_size(units) if use_hash else 0.0
	for iteration in range(SEPARATION_ITERATIONS):
		rounds = iteration + 1
		var moved_any := false
		if use_hash:
			moved_any = _separate_pairs_hashed(units, hash_cell)
		else:
			for i in range(units.size()):
				for j in range(i + 1, units.size()):
					if _separate_pair(units[i], units[j]):
						moved_any = true
		for unit in units:
			if unit.mobile and _project_out_of_world(unit, statics, static_bounds, wrapper.map_size):
				moved_any = true
		if not moved_any:
			break
	return {
		"separation_rounds": rounds,
		"max_residual_overlap": max_overlap_depth(units),
	}


# Conservative axis-aligned reach bounds per static: the OBB's AABB grown by
# the largest unit radius (+1 px float margin). _project_out_of_shape can
# only move a unit whose center is within its radius of the OBB, so a
# bounds-reject is exactly a "projection returns false" fast path.
func _static_reach_bounds(
	statics: Array[SimNavObstructionShapeStatic],
	units: Array[Dota2LabUnit]
) -> Array[Rect2]:
	var max_radius := 0.0
	for unit in units:
		max_radius = maxf(max_radius, unit.radius)
	var bounds: Array[Rect2] = []
	for shape in statics:
		var half_x := shape.width * 0.5
		var half_y := shape.height * 0.5
		if shape.rotation_rad != 0.0:
			var cos_abs: float = absf(cos(shape.rotation_rad))
			var sin_abs: float = absf(sin(shape.rotation_rad))
			var rotated_x := cos_abs * shape.width * 0.5 + sin_abs * shape.height * 0.5
			var rotated_y := sin_abs * shape.width * 0.5 + cos_abs * shape.height * 0.5
			half_x = rotated_x
			half_y = rotated_y
		var reach_x := half_x + max_radius + 1.0
		var reach_y := half_y + max_radius + 1.0
		bounds.append(Rect2(
			shape.center.x - reach_x, shape.center.y - reach_y,
			reach_x * 2.0, reach_y * 2.0
		))
	return bounds


# Flat-grid scratch for the hashed pair pass (heads/next intrusive chains +
# a candidate buffer). Engine-level transient buffers reused across calls to
# avoid per-iteration Dictionary and Array churn — not per-unit state.
var _grid_heads := PackedInt32Array()
var _grid_next := PackedInt32Array()
var _grid_candidates := PackedInt32Array()


# Uniform-grid neighbor pass over a flat linked-cell grid, rebuilt every
# iteration from current positions. Candidate order is the all-pairs loop's
# (i, ascending j) — corrections are order-sensitive (Gauss-Seidel): units
# are inserted in DESCENDING index order so every cell chain reads
# ascending, and cross-cell candidates are insertion-sorted.
#
# Contract vs the brute loop: bitwise-identical AS LONG AS no unit is
# displaced across a full hash cell (~one body diameter) within a single
# iteration — realistic crowds stay far under that, and the weld smoke
# pins it; a unit shoved further (adversarial stacked spawns) can drop a
# late-blooming pair for one iteration and is re-seen when the grid is
# rebuilt next round. Past that boundary the contract is convergence (all
# overlaps still resolve across iterations), not bit-equality.
func _separate_pairs_hashed(units: Array[Dota2LabUnit], cell_size: float) -> bool:
	var count := units.size()
	if count == 0:
		return false
	var min_x := units[0].position.x
	var min_y := units[0].position.y
	var max_x := min_x
	var max_y := min_y
	for unit in units:
		min_x = minf(min_x, unit.position.x)
		min_y = minf(min_y, unit.position.y)
		max_x = maxf(max_x, unit.position.x)
		max_y = maxf(max_y, unit.position.y)
	var grid_w := int((max_x - min_x) / cell_size) + 1
	var grid_h := int((max_y - min_y) / cell_size) + 1
	if _grid_heads.size() < grid_w * grid_h:
		_grid_heads.resize(grid_w * grid_h)
	for cell in range(grid_w * grid_h):
		_grid_heads[cell] = -1
	if _grid_next.size() < count:
		_grid_next.resize(count)
	if _grid_candidates.size() < count:
		_grid_candidates.resize(count)
	for rev in range(count):
		var insert_index := count - 1 - rev
		var insert_pos := units[insert_index].position
		var cell := int((insert_pos.y - min_y) / cell_size) * grid_w \
			+ int((insert_pos.x - min_x) / cell_size)
		_grid_next[insert_index] = _grid_heads[cell]
		_grid_heads[cell] = insert_index
	var moved_any := false
	for i in range(count):
		var unit := units[i]
		var cx := int((unit.position.x - min_x) / cell_size)
		var cy := int((unit.position.y - min_y) / cell_size)
		var candidate_count := 0
		for oy in range(maxi(cy - 1, 0), mini(cy + 2, grid_h)):
			var row := oy * grid_w
			for ox in range(maxi(cx - 1, 0), mini(cx + 2, grid_w)):
				var j := _grid_heads[row + ox]
				while j != -1:
					if j > i:
						var insert_at := candidate_count
						while insert_at > 0 and _grid_candidates[insert_at - 1] > j:
							_grid_candidates[insert_at] = _grid_candidates[insert_at - 1]
							insert_at -= 1
						_grid_candidates[insert_at] = j
						candidate_count += 1
					j = _grid_next[j]
		for k in range(candidate_count):
			var other: Dota2LabUnit = units[_grid_candidates[k]]
			# Squared-distance pre-reject at the raw radius sum — strictly
			# looser than _separate_pair's own reject (which subtracts
			# SEPARATION_SLACK), so the 0.01 px band absorbs any float noise
			# and a pre-rejected pair is always one the call would reject too.
			# Skips the call + sqrt for most near-but-not-overlapping pairs.
			var reach: float = unit.radius + other.radius
			if unit.position.distance_squared_to(other.position) >= reach * reach:
				continue
			if _separate_pair(unit, other):
				moved_any = true
	return moved_any


func _separation_hash_cell_size(units: Array[Dota2LabUnit]) -> float:
	var max_radius := 0.0
	for unit in units:
		max_radius = maxf(max_radius, unit.radius)
	# Cell = max possible pair reach (+1 px float margin): two bodies that can
	# overlap are never more than one cell apart at pass start.
	return maxf(1.0, max_radius * 2.0 + 1.0)


# Steering looks further than overlap (contact gap range) and runs while
# units advance one step per tick — earlier-in-array units have already
# moved when later units query — so pad the cell by the gap range plus the
# largest single-step displacement this tick can produce (derived from
# actual speeds and delta, not a hardcoded guess).
func _steering_hash_cell_size(units: Array[Dota2LabUnit], delta: float) -> float:
	var max_radius := 0.0
	var max_speed := 0.0
	for unit in units:
		max_radius = maxf(max_radius, unit.radius)
		max_speed = maxf(max_speed, unit.speed)
	return maxf(1.0, max_radius * 2.0 + CONTACT_STEER_GAP_RANGE + max_speed * delta + 1.0)


func _build_position_buckets(units: Array[Dota2LabUnit], cell_size: float) -> Dictionary:
	var buckets: Dictionary = {}
	for i in range(units.size()):
		var key := Vector2i(
			floori(units[i].position.x / cell_size),
			floori(units[i].position.y / cell_size)
		)
		if buckets.has(key):
			(buckets[key] as Array).append(i)
		else:
			buckets[key] = [i]
	return buckets


func _separate_pair(a: Dota2LabUnit, b: Dota2LabUnit) -> bool:
	var min_distance := a.radius + b.radius
	var offset := b.position - a.position
	var distance := offset.length()
	if distance >= min_distance - SEPARATION_SLACK:
		return false
	var weight_a := _separation_weight_a(a, b)
	if weight_a < 0.0:
		return false
	var direction: Vector2
	if distance > 0.001:
		direction = offset / distance
	else:
		# Perfectly coincident centers: deterministic split by id order.
		direction = Vector2.RIGHT if a.id < b.id else Vector2.LEFT
	direction = _head_on_biased(a, b, direction)
	var overlap := min_distance - distance
	a.position -= direction * overlap * weight_a
	b.position += direction * overlap * (1.0 - weight_a)
	return true


# a's share of the pair correction, or -1 to skip the pair. Overlap between
# mobile bodies is ALWAYS resolved — when both sides claim pushability 0
# ("rigid"), physics wins and the correction splits evenly. Only immobile
# blockers are truly immovable (both immobile: user-placed overlap, leave it).
func _separation_weight_a(a: Dota2LabUnit, b: Dota2LabUnit) -> float:
	if not a.mobile and not b.mobile:
		return -1.0
	if not a.mobile:
		return 0.0
	if not b.mobile:
		return 1.0
	var push_a := _pushability(a)
	var push_b := _pushability(b)
	var total := push_a + push_b
	if total <= 0.0:
		return 0.5
	return push_a / total


func _pushability(unit: Dota2LabUnit) -> float:
	if not unit.mobile:
		return 0.0
	if unit.state == Dota2LabUnit.STATE_MOVING:
		return pushability_moving
	return pushability_idle


func _head_on_biased(a: Dota2LabUnit, b: Dota2LabUnit, direction: Vector2) -> Vector2:
	var steer_unit: Dota2LabUnit = null
	if a.state == Dota2LabUnit.STATE_MOVING \
			and absf(Vector2.from_angle(a.facing_angle_rad).dot(direction)) > HEAD_ON_ALIGN_DOT:
		steer_unit = a
	elif b.state == Dota2LabUnit.STATE_MOVING \
			and absf(Vector2.from_angle(b.facing_angle_rad).dot(direction)) > HEAD_ON_ALIGN_DOT:
		steer_unit = b
	if steer_unit == null:
		return direction
	# Push toward the same side the head-on unit is steering around (its
	# contact-steering lock when present, else the same nearest-side geometry)
	# so intent and push never fight. `direction` runs a → b; the algebra
	# below yields the steer unit's chosen side for either member.
	var side := steer_unit.steer_side
	if side == 0.0:
		var to_other := direction if steer_unit == a else -direction
		side = _pick_steer_side(to_other, Vector2.from_angle(steer_unit.facing_angle_rad))
	var lateral := Vector2(direction.y, -direction.x) * side
	return (direction + lateral * HEAD_ON_LATERAL_BIAS).normalized()


func _project_out_of_world(
	unit: Dota2LabUnit,
	statics: Array[SimNavObstructionShapeStatic],
	static_bounds: Array[Rect2],
	map_size: Vector2
) -> bool:
	var moved := false
	var pos := unit.position
	for shape_index in range(statics.size()):
		# Inline bounds reject (this runs units x statics x iterations per
		# tick; Rect2.has_point costs a call per check).
		var bounds := static_bounds[shape_index]
		if pos.x < bounds.position.x or pos.y < bounds.position.y \
				or pos.x >= bounds.position.x + bounds.size.x \
				or pos.y >= bounds.position.y + bounds.size.y:
			continue
		if _project_out_of_shape(unit, statics[shape_index]):
			moved = true
			pos = unit.position
	# Inline twin of Dota2LabPathfinderWrapper.clamp_to_playable — keep the
	# formula in lockstep.
	var clamped := Vector2(
		clampf(pos.x, unit.radius, map_size.x - unit.radius),
		clampf(pos.y, unit.radius, map_size.y - unit.radius)
	)
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
		_drop_pending_plan(unit, wrapper)
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
			_drop_pending_plan(unit, wrapper)
			_complete(unit, tick, Dota2LabMoveOrder.REASON_ARRIVED_CROWDED, events)
		return

	if moved_ok or turning_in_place:
		unit.stall_seconds = 0.0
		return
	unit.stall_seconds += delta
	if unit.stall_seconds < STALL_REPATH_SEC:
		return
	if unit.repath_count < MAX_REPATHS:
		if unit.pending_plan_ticket > 0:
			return  # a replan is already in flight
		unit.repath_count += 1
		unit.stall_seconds = 0.0
		_request_plan(unit, wrapper)
		return
	_drop_pending_plan(unit, wrapper)
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
