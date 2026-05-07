extends Node

# LAB-004: Overlap / arrival policy is fragile (LOCK-IN at HEAD)
#
# Status: this is a LOCK-IN smoke. The codex Issue 4 stress scenario
# previously produced ~2 px arrived-idle overlap; the latest fix narrowed
# the idle-idle skip so the default scenario no longer reproduces the
# problem. This smoke runs the default arrival case and asserts no
# arrived-idle pair exceeds 1 px overlap, locking the win in.
#
# Future work: a true adversarial repro for codex Issue 4 needs a stress
# setup (rapid obstacle edits during arrival, edge-adjacent target,
# blocker-near-target packing). When that adversarial scenario is
# constructed, replace this smoke or add a sibling repro_lab_004b_*.
#
# Repro: setup_default (6 mobile blue + 2 red blockers). Command all blue
# to the default target (610, 210). Step until arrival. Inspect every
# pair of mobile blue units; assert pairwise overlap ≤ 1 px.
#
# At HEAD (commit 6335f32): PASS (codex Issue 4 default-case fix held).
# Regression: any change that brings back > 1 px arrived overlap on the
# default scenario flips this to FAIL.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_004_overlap_policy.tscn


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-004 default arrival overlap stays bounded")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-004 regression: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Default target lives at (610, 210). 6 blue units pack toward it.
	world.set_group_target(Vector2(610.0, 210.0))

	var dt := 1.0 / 60.0
	var arrived_at := -1
	for i in range(600):
		world.step(dt)
		if world.all_mobile_arrived():
			arrived_at = i
			break

	# Allow a few extra ticks to settle separation after arrival.
	for _i in range(30):
		world.step(dt)

	var mobile := world.get_mobile_units()
	var max_overlap := 0.0
	var max_overlap_pair := ""
	for i in range(mobile.size()):
		for j in range(i + 1, mobile.size()):
			var ui := mobile[i]
			var uj := mobile[j]
			var dist: float = ui.position.distance_to(uj.position)
			var sum_radii: float = ui.radius + uj.radius
			var overlap: float = maxf(0.0, sum_radii - dist)
			if overlap > max_overlap:
				max_overlap = overlap
				max_overlap_pair = "%s↔%s" % [ui.id, uj.id]

	var target_overlap := 1.0
	print(
		"LAB-004 overlap: arrived_at_step=%d, max_pair_overlap=%.2f px on %s (target ≤ %.1f px)"
		% [arrived_at, max_overlap, max_overlap_pair, target_overlap]
	)
	if arrived_at < 0:
		_failures.append("units did not arrive within 600 ticks")
	if max_overlap > target_overlap:
		_failures.append(
			"max pairwise overlap = %.2f px on %s, exceeds target ≤ %.1f px"
			% [max_overlap, max_overlap_pair, target_overlap]
		)
