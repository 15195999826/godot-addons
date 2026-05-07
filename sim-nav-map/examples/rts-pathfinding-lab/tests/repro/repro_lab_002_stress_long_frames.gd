extends Node

# LAB-002: Stress scenarios still produce 10-15 ms peak frames
#
# Bug reproduced here:
#   - In the default scenario the avg step is ~300-450 µs, but stress
#     scenarios spike a single step to 10-15 ms (BASELINE).
#   - Stress = many synchronous expensive operations land in one tick,
#     typically rapid obstacle edits while units are mid-move.
#
# Repro: setup_default, then drive step() for 360 ticks while injecting
# rapid obstacle edits (drop a blocker every 6 ticks, remove the nearest
# every 9 ticks, re-issue the group target every 30 ticks). Track max
# single-step wall time.
#
# Threshold: ≤ 4 000 µs (4 ms). Generous compared to BASELINE 10-15 ms.
#
# At HEAD (commit 6335f32): peak step exceeds 4 ms. FAIL.
# After LAB-002 fix (per-call request budget / cached canonical targets /
# obstacle-revision keys): peak step stays under threshold. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_002_stress_long_frames.tscn


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-002 stress long frames (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-002 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()

	var dt := 1.0 / 60.0
	# Warm up so first-tick replan does not dominate.
	for _i in range(5):
		world.step(dt)

	var num_steps := 360
	var max_step_usec := 0
	var max_step_at := -1
	var blocker_x := 180.0

	for i in range(num_steps):
		# Aggressive rapid obstacle edits: every 6 ticks add a blocker (alternating
		# rows above/below the path), every 9 ticks remove the nearest. Also force
		# a re-issue of the group target every 30 ticks to thrash the replan
		# pipeline.
		if i % 6 == 0:
			var y_band: float = 195.0 if (i / 6) % 2 == 0 else 225.0
			world.add_blocker(Vector2(blocker_x, y_band), 14.0)
			blocker_x += 18.0
			if blocker_x > 580.0:
				blocker_x = 180.0
		if i % 9 == 0 and i > 0:
			world.remove_nearest_editable(Vector2(blocker_x - 24.0, 210.0))
		if i % 30 == 0 and i > 0:
			world.set_group_target(Vector2(610.0, 210.0))

		var t0 := Time.get_ticks_usec()
		world.step(dt)
		var step_usec := Time.get_ticks_usec() - t0
		if step_usec > max_step_usec:
			max_step_usec = step_usec
			max_step_at = i

	var target_usec := 4000
	print(
		"LAB-002 stress max_step_usec = %d µs at step %d (target ≤ %d µs, BASELINE ~10000-15000 µs)"
		% [max_step_usec, max_step_at, target_usec]
	)
	if max_step_usec > target_usec:
		_failures.append(
			"max single-step wall time = %d µs at step %d, exceeds target ≤ %d µs"
			% [max_step_usec, max_step_at, target_usec]
		)
