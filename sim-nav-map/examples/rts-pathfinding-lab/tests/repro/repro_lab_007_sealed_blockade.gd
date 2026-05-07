extends Node

# LAB-007: Sealed-blockade separation budget burn
#
# Replays the user export
#   ..._tick_716.json (custom_obstacle_3 just placed):
#   - Default scene (stone_block + north_wall + south_wall) plus three
#     custom obstacles at (423,155), (421,284), (434,395) with default
#     74x74 size.
#   - Six blue mobiles trapped between stone_block and the new east
#     wall; group target (610, 210) is in a different global region.
#   - last_step_usec = 13860, max_step_usec = 15358 (target ≤ 4 000).
#
# Hypothesis (see docs/issues/lab-007-sealed-blockade-frame-burn.md):
#   - dominant cost is _resolve_separation hitting the 16 ms budget
#     ceiling because the inner `changed` flag flips on micro-jitter
#     and never early-exits.
#
# Threshold: ≤ 4 000 µs single-step wall time (consistent with LAB-002).
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_007_sealed_blockade.tscn

const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-007 sealed-blockade frame burn (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-007 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()

	# Place the three custom obstacles from the user export, which seal
	# every passable route from blue's enclave to the (610, 210) target.
	world.add_static_obstacle(Vector2(423.0, 155.0))
	world.add_static_obstacle(Vector2(421.0, 284.0))
	world.add_static_obstacle(Vector2(434.0, 395.0))

	# Teleport blue to the trapped positions captured in the export log
	# so the smoke does not depend on motion-pathing timing landing the
	# cluster in exactly the same enclave.
	var trapped: Array[Vector2] = [
		Vector2(374.93, 126.07),  # blue_0
		Vector2(363.16, 143.70),  # blue_1
		Vector2(350.01, 126.50),  # blue_2
		Vector2(372.83, 293.99),  # blue_3
		Vector2(360.89, 276.12),  # blue_4
		Vector2(347.89, 293.80),  # blue_5
	]
	for i in range(trapped.size()):
		var unit := world.get_unit_by_id("blue_%d" % i)
		if unit == null:
			_failures.append("expected blue_%d after setup_default" % i)
			return
		unit.position = trapped[i]

	# Re-issue the group target so replan timers fire under the sealed
	# map (setup_default already targeted (610, 210), but the trapped
	# teleport invalidates any in-flight plan).
	world.set_group_target(Vector2(610.0, 210.0))

	var dt := 1.0 / 60.0
	# Warm up so first-tick replan + initial separation do not dominate
	# the measured peak.
	for _i in range(5):
		world.step(dt)

	var num_steps := 200
	var max_step_usec := 0
	var max_step_at := -1
	var max_separation_usec := 0
	for i in range(num_steps):
		var t0 := Time.get_ticks_usec()
		world.step(dt)
		var step_usec := Time.get_ticks_usec() - t0
		var separation_usec := int(world.last_step_profile.get("separation_usec", 0))
		if step_usec > max_step_usec:
			max_step_usec = step_usec
			max_step_at = i
		if separation_usec > max_separation_usec:
			max_separation_usec = separation_usec

	var target_usec := 4000
	print(
		"LAB-007 sealed-blockade max_step_usec = %d µs at step %d (separation peak %d µs, target ≤ %d µs, BASELINE ~13000-15000 µs)"
		% [max_step_usec, max_step_at, max_separation_usec, target_usec]
	)
	if max_step_usec > target_usec:
		_failures.append(
			"max single-step wall time = %d µs at step %d, exceeds target ≤ %d µs (separation peak %d µs)"
			% [max_step_usec, max_step_at, target_usec, max_separation_usec]
		)
