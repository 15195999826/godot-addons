extends Node

# CORE-020: KNOWN LIMITATION — push system brushes a unit sub-pixel into a
# static obstacle's clearance ring when (a) unit center sits on the ring
# boundary, (b) the unit's active path is empty (path queue still
# processing post-retarget), and (c) crowd density produces high
# pushing_pressure.
#
# This is NOT a bug introduced by lab — it mirrors a 0 A.D. directional
# LOS edge case (Geometry.cpp:308 TestRayAASquare boundary inclusive
# semantics) that 0 A.D. avoids in practice via fixed-point coordinates,
# CCmpFormation slot selection, and pixel-snap rendering. Lab uses
# GDScript floats and has no formation controller, so the artifact is
# observable. See docs/issues/core-020-motion-brushes-clearance-under-push.md.
#
# Bug reproduced here (from stress_playthrough.tscn -- --swarm, seed=42):
#   At tick 362, swarm_3 enters north_block's clearance ring at
#   (430.3, 114.2), depth 0.77 px on the y axis. long_path and short_path
#   are both empty. pushing_pressure=76. nearest_neighbour swarm_8 at
#   d=20.4 (in contact, combined radius=22). Unit was oscillating along
#   ring boundary y≈115 for 7 ticks before push amplitude pushed y past
#   the boundary.
#
# Self-recovery: the unit is naturally back outside the ring within
# 5-8 ticks once oscillation moves it away from the boundary.
#
# 0 A.D. expected (Geometry.cpp:308):
#   Same TestRayAASquare directional rule. Same boundary semantics. The
#   visible symptom is suppressed by surrounding systems (fixed-point
#   snap, formation controller, pixel-snap render) that lab does not have
#   yet. See the issue doc for fix options A-E.
#
# Fix attempted: NONE. Deferred to a future motion / push hardening
# milestone.
#
# This repro replicates stress swarm setup verbatim and asserts the
# deterministic violation tick + position.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/repro/repro_core_020_motion_brushes_clearance_under_push_known_limit.tscn


const DT := 1.0 / 60.0
const SEED := 42
const UNITS := 50
const RETARGET_EVERY := 120
const TICK_BUDGET := 380  # violation occurs at tick 362; budget covers it
const RADIUS := 11.0
const SPEED := 96.0
const SPAWN_MAX_ATTEMPTS_PER_UNIT := 80
const RETARGET_MAX_ATTEMPTS := 20

const EXPECTED_TICK := 362
const EXPECTED_UNIT := "swarm_3"
const EXPECTED_OBSTACLE := "north_block"
const EXPECTED_POS := Vector2(430.33, 114.23)
const EXPECTED_POS_TOLERANCE := 0.5  # px
const EXPECTED_DEPTH_MAX := 1.0  # px — sub-pixel brush, not deep penetration


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-020 push-brushes-clearance behavior locked (known limitation)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-020 behavior changed: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var world := _setup_world(rng)
	var actually_spawned := world.get_mobile_unit_ids().size()
	if actually_spawned < UNITS:
		_failures.append("setup: spawned %d / %d units (rejected by obstacles or other units)" % [actually_spawned, UNITS])
		return

	var violation_tick := -1
	var violation_unit := ""
	var violation_pos := Vector2.ZERO
	var violation_obstacle := ""
	var violation_depth := 0.0
	for tick in range(TICK_BUDGET):
		if tick % RETARGET_EVERY == 0:
			_random_retarget(world, rng)
		world.step(DT)
		var hit := _first_violation(world)
		if not hit.is_empty():
			violation_tick = tick
			violation_unit = String(hit["unit_id"])
			violation_pos = hit["pos"]
			violation_obstacle = String(hit["obstacle_id"])
			violation_depth = float(hit["depth"])
			break

	if violation_tick < 0:
		_failures.append("expected violation never occurred within %d ticks; CORE-020 may have been silently fixed (or precondition changed)" % TICK_BUDGET)
		return

	if violation_tick != EXPECTED_TICK:
		_failures.append("violation tick %d != expected %d" % [violation_tick, EXPECTED_TICK])
	if violation_unit != EXPECTED_UNIT:
		_failures.append("violation unit %s != expected %s" % [violation_unit, EXPECTED_UNIT])
	if violation_obstacle != EXPECTED_OBSTACLE:
		_failures.append("violation obstacle %s != expected %s" % [violation_obstacle, EXPECTED_OBSTACLE])
	if violation_pos.distance_to(EXPECTED_POS) > EXPECTED_POS_TOLERANCE:
		_failures.append("violation pos %s differs from expected %s by > %.2f px" % [str(violation_pos), str(EXPECTED_POS), EXPECTED_POS_TOLERANCE])
	if violation_depth > EXPECTED_DEPTH_MAX:
		_failures.append("violation depth %.3f px exceeds known sub-pixel brush threshold %.2f — penetration is no longer minor; investigate" % [violation_depth, EXPECTED_DEPTH_MAX])


# --- swarm setup mirrors stress_playthrough.gd::_swarm_setup_world ---


func _setup_world(rng: RandomNumberGenerator) -> ZeroAdRtsLabWorld:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	var keep_units: Array[ZeroAdRtsLabUnit] = []
	for unit in world.units:
		if not unit.mobile:
			keep_units.append(unit)
	world.units = keep_units
	var spawned := 0
	var attempts := 0
	var max_attempts := UNITS * SPAWN_MAX_ATTEMPTS_PER_UNIT
	while spawned < UNITS and attempts < max_attempts:
		attempts += 1
		var pos := Vector2(
			rng.randf_range(RADIUS + 5.0, world.map_size.x - RADIUS - 5.0),
			rng.randf_range(RADIUS + 5.0, world.map_size.y - RADIUS - 5.0)
		)
		if not _position_clear(world, pos, RADIUS):
			continue
		world.units.append(ZeroAdRtsLabUnit.new("swarm_%d" % spawned, "blue", pos, RADIUS, SPEED, true))
		spawned += 1
	world.pathfinder.refresh_dynamic_units(world.units)
	world.clear_traces()
	return world


func _position_clear(world: ZeroAdRtsLabWorld, pos: Vector2, radius: float) -> bool:
	for ob in world.obstacles:
		if ob.contains_point_with_clearance(pos, radius):
			return false
	for unit in world.units:
		if pos.distance_to(unit.position) < (radius + unit.radius + 4.0):
			return false
	return true


func _random_retarget(world: ZeroAdRtsLabWorld, rng: RandomNumberGenerator) -> void:
	for unit in world.get_mobile_units():
		var target := unit.position
		for _attempt in range(RETARGET_MAX_ATTEMPTS):
			var candidate := Vector2(
				rng.randf_range(RADIUS + 5.0, world.map_size.x - RADIUS - 5.0),
				rng.randf_range(RADIUS + 5.0, world.map_size.y - RADIUS - 5.0)
			)
			var clear := true
			for ob in world.obstacles:
				if ob.contains_point_with_clearance(candidate, RADIUS):
					clear = false
					break
			if clear:
				target = candidate
				break
		world.issue_move(unit.id, target)


func _first_violation(world: ZeroAdRtsLabWorld) -> Dictionary:
	for unit in world.get_mobile_units():
		for ob in world.obstacles:
			if not ob.contains_point_with_clearance(unit.position, unit.radius):
				continue
			var rect := Rect2(ob.center - ob.size * 0.5, ob.size).grow(unit.radius)
			var dx := minf(unit.position.x - rect.position.x, rect.position.x + rect.size.x - unit.position.x)
			var dy := minf(unit.position.y - rect.position.y, rect.position.y + rect.size.y - unit.position.y)
			return {
				"unit_id": unit.id,
				"pos": unit.position,
				"obstacle_id": ob.id,
				"depth": minf(dx, dy),
			}
	return {}
