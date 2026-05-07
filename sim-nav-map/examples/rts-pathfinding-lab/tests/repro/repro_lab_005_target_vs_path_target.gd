extends Node

# LAB-005: Command target vs path target separation must hold
#
# This is a LOCK-IN smoke, not a bug-exposure. The current behavior is
# correct per the codex discussion in rts-lab-open-issues.md Issue 5:
#   - unit.target = the user click (or formation slot derived from it)
#   - unit.path_target = the canonical reachable stop point
# A future regression that merges these meanings should turn this smoke red.
#
# Repro: setup_default. Command all blue units to a point INSIDE the
# default stone_block obstacle at (340, 210) with size (110, 110), so the
# click is unreachable. Step a few ticks to let canonicalization run.
# Inspect each blue unit's target vs path_target.
#
# Expected (HEAD, post-fix from codex Issue 5):
#   - unit.target stays near the original click + formation offset.
#   - unit.path_target sits OUTSIDE the obstacle (canonicalized).
#   - target ≠ path_target for at least one unit.
#
# At HEAD: PASS. The smoke locks in this property.
# Regression: if a future change merges target/path_target back into one,
# the smoke flips to FAIL.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_005_target_vs_path_target.tscn


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-005 target vs path_target separation locked in")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-005 regression: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()

	# stone_block sits at center (340, 210) with size (110, 110), so the
	# rectangle is x ∈ [285, 395], y ∈ [155, 265]. Pick a point strictly
	# inside as the unreachable command target.
	var unreachable_click := Vector2(340.0, 210.0)
	world.set_group_target(unreachable_click)

	# Step several ticks so the per-unit replan budget can canonicalize.
	var dt := 1.0 / 60.0
	for _i in range(20):
		world.step(dt)

	var separated_count := 0
	var checked_count := 0
	for unit in world.get_mobile_units():
		checked_count += 1
		var t: Vector2 = unit.target
		var pt: Vector2 = unit.path_target
		if t.distance_to(pt) > 0.5:
			separated_count += 1
		# unit.target should still be near the original click + formation offset,
		# not snapped onto the canonical reachable point.
		if t.distance_to(unreachable_click) > 60.0:
			_failures.append(
				"unit %s: target %s drifted > 60 px from original click %s — should track command, not canonical"
				% [unit.id, str(t), str(unreachable_click)]
			)

	print(
		"LAB-005 separation: checked %d units, %d had target ≠ path_target (>0.5 px apart)"
		% [checked_count, separated_count]
	)
	if separated_count == 0:
		_failures.append(
			"no unit has target ≠ path_target after commanding inside an obstacle — separation property is broken"
		)
