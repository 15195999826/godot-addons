extends Node

# LAB-007: Sealed-blockade separation budget burn
#
# Replays the user's operation sequence from export
#   ..._tick_716.json (timeline: setup_default → progressive seal):
#   - Default scene (stone_block + north_wall + south_wall, blue mobiles
#     at x≈74-104, group target (610, 210)).
#   - Tick 41: place custom_obstacle_1 at (423, 155), default 74x74.
#   - Tick 89: place custom_obstacle_2 at (421, 284).
#   - Tick 140: place custom_obstacle_3 at (434, 395) — this completes
#     the seal: every passable route from blue's enclave to (610, 210)
#     is now blocked.
#   - Continue stepping to tick 716 (matches user's measured_step_count).
#   - Observed at HEAD: last_step_usec = 13860, max_step_usec = 15358.
#
# Hypothesis (see docs/issues/lab-007-sealed-blockade-frame-burn.md):
#   - dominant cost post-seal is _resolve_separation hitting the 16 ms
#     budget ceiling because the inner `changed` flag flips on
#     micro-jitter and never early-exits.
#
# Threshold: ≤ 4 000 µs single-step wall time over the full 716-tick run
# (consistent with LAB-002). The smoke does NOT teleport units — motion
# is fully driven by setup_default's group target plus the auto replan
# triggered by add_static_obstacle.
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
	# setup_default already issues the group target (610, 210); blue
	# starts moving toward it on the next step().

	var dt := 1.0 / 60.0
	var num_steps := 716   # matches user export's measured_step_count
	var max_step_usec := 0
	var max_step_at := -1
	var max_separation_usec := 0
	var max_separation_at := -1
	var pre_seal_max_usec := 0   # before tick 140 — should stay cheap
	var post_seal_max_usec := 0  # tick ≥ 140 — where the spike lives

	for i in range(num_steps):
		var upcoming_tick := i + 1
		# Place obstacles right before the step that the user's log
		# attributes the place_obstacle event to (world.tick_count is
		# incremented at the top of step(), so an obstacle placed here
		# becomes visible to that very step).
		if upcoming_tick == 41:
			world.add_static_obstacle(Vector2(423.0, 155.0))
		elif upcoming_tick == 89:
			world.add_static_obstacle(Vector2(421.0, 284.0))
		elif upcoming_tick == 140:
			world.add_static_obstacle(Vector2(434.0, 395.0))

		var t0 := Time.get_ticks_usec()
		world.step(dt)
		var step_usec := Time.get_ticks_usec() - t0
		var separation_usec := int(world.last_step_profile.get("separation_usec", 0))

		if step_usec > max_step_usec:
			max_step_usec = step_usec
			max_step_at = upcoming_tick
		if separation_usec > max_separation_usec:
			max_separation_usec = separation_usec
			max_separation_at = upcoming_tick
		if upcoming_tick < 140:
			pre_seal_max_usec = maxi(pre_seal_max_usec, step_usec)
		else:
			post_seal_max_usec = maxi(post_seal_max_usec, step_usec)

	var target_usec := 4000
	print(
		"LAB-007 sealed-blockade max_step_usec = %d µs at tick %d (pre-seal max %d µs, post-seal max %d µs, separation peak %d µs at tick %d, target ≤ %d µs, BASELINE ~13000-15000 µs)"
		% [
			max_step_usec,
			max_step_at,
			pre_seal_max_usec,
			post_seal_max_usec,
			max_separation_usec,
			max_separation_at,
			target_usec,
		]
	)
	if max_step_usec > target_usec:
		_failures.append(
			"max single-step wall time = %d µs at tick %d, exceeds target ≤ %d µs (post-seal max %d µs, separation peak %d µs at tick %d)"
			% [
				max_step_usec,
				max_step_at,
				target_usec,
				post_seal_max_usec,
				max_separation_usec,
				max_separation_at,
			]
		)
