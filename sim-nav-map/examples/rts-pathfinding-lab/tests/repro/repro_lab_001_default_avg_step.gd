extends Node

# LAB-001: Default scenario avg step time too high
#
# Bug reproduced here:
#   - Default rtslab scenario logs avg_step_usec ~450-480 µs (BASELINE).
#   - Earlier remembered baseline was ~100 µs. Current state is ~4-5× slower.
#
# Repro: instantiate RtsPathfindingLabWorld with setup_default(). Drive
# step(1/60) for 60 ticks (1 sim second). Measure per-step wall time and
# compute the average. Assert the average is at or below the target.
#
# Threshold: ≤ 200 µs (chosen as a generous upper bound; the issue's stretch
# target is ~100 µs, but ~200 µs is enough to catch the current regression
# without being so tight that minor lab-side polish blocks merges).
#
# At HEAD (commit 6335f32): avg ~450-480 µs. FAIL.
# After fix (lab caching / per-call budget per LAB-001 backlog): avg drops
# below threshold. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_001_default_avg_step.tscn


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-001 default avg step (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-001 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()

	var dt := 1.0 / 60.0
	# Warm-up step to amortize first-tick replan costs.
	world.step(dt)

	var num_steps := 60
	var total_usec := 0
	for i in range(num_steps):
		var t0 := Time.get_ticks_usec()
		world.step(dt)
		total_usec += Time.get_ticks_usec() - t0
	var avg_usec := float(total_usec) / float(num_steps)

	var target_usec := 200.0
	print("LAB-001 default avg_step_usec = %.1f µs (target ≤ %.1f µs)" % [avg_usec, target_usec])
	if avg_usec > target_usec:
		_failures.append(
			"default avg_step_usec = %.1f exceeds target ≤ %.1f (BASELINE notes ~450-480 at HEAD)"
			% [avg_usec, target_usec]
		)
