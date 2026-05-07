extends Node

# LAB-005: Command target vs path target separation must hold
#
# This is a LOCK-IN smoke, not a bug-exposure. The current behavior is
# correct per LAB-005:
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
#   - arrival/completion is judged against path_target, not the command target.
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
	var stone_block_rect := Rect2(Vector2(285.0, 155.0), Vector2(110.0, 110.0))
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
		if stone_block_rect.has_point(pt):
			_failures.append(
				"unit %s: path_target %s stayed inside stone_block — should canonicalize outside the obstacle"
				% [unit.id, str(pt)]
			)
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

	var arrived_at := -1
	for i in range(600):
		world.step(dt)
		if world.all_mobile_arrived():
			arrived_at = i
			break
	if arrived_at < 0:
		_failures.append("units did not arrive at canonical path targets within 600 ticks")
		return

	var arrival_tolerance := 8.0
	var arrived_by_path_target_count := 0
	var still_far_from_command_count := 0
	for unit in world.get_mobile_units():
		var path_target_error := unit.position.distance_to(unit.path_target)
		var command_target_error := unit.position.distance_to(unit.target)
		if path_target_error <= arrival_tolerance:
			arrived_by_path_target_count += 1
		if command_target_error > arrival_tolerance:
			still_far_from_command_count += 1
		if unit.arrived and path_target_error > arrival_tolerance:
			_failures.append(
				"unit %s arrived=true but is %.2f px from path_target %s"
				% [unit.id, path_target_error, str(unit.path_target)]
			)
	print(
		"LAB-005 arrival: arrived_at_step=%d, %d/%d arrived within %.1f px of path_target, %d/%d still far from command target"
		% [
			arrived_at,
			arrived_by_path_target_count,
			checked_count,
			arrival_tolerance,
			still_far_from_command_count,
			checked_count,
		]
	)
	if arrived_by_path_target_count != checked_count:
		_failures.append(
			"only %d/%d units arrived within %.1f px of path_target"
			% [arrived_by_path_target_count, checked_count, arrival_tolerance]
		)
	if still_far_from_command_count == 0:
		_failures.append("arrival did not prove path_target semantics because every unit ended near the command target")
