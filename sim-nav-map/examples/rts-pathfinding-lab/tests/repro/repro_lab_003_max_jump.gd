extends Node

# LAB-003: Active position jump can hit ~55 px in a single step
#
# Bug reproduced here:
#   - When the lab's static-escape system extricates a unit that ended up
#     inside (or under) a static obstacle, the per-frame displacement can
#     be much larger than a normal movement step. BASELINE: ~55 px.
#   - The default scenario does not naturally produce this — running the
#     default world for hundreds of ticks shows max_any_jump < 5 px.
#   - The provoking situation is a static obstacle landing on top of a
#     mobile unit, forcing the unit to escape on the next step. We script
#     that scenario explicitly so the repro is deterministic.
#
# Repro: setup_default. Step a few ticks to let blue_0 enter motion. Drop
# a 60×60 static obstacle centered on blue_0's current position. Continue
# stepping. Track per-tick world-space delta for blue_0; report the max.
#
# Threshold: ≤ 16 px (2 navcells, generous).
#
# At HEAD (commit 6335f32): max jump exceeds 16 px (escape teleport). FAIL.
# After LAB-003 fix (jump-attribution + capped escape per step, or
# replan-rather-than-teleport): max jump stays bounded. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_003_max_jump.tscn


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-003 max position jump (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-003 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()

	var dt := 1.0 / 60.0
	# Let units enter motion before we drop the obstacle on top of one of them.
	for _i in range(20):
		world.step(dt)

	var victim := world.get_unit_by_id("blue_0")
	if victim == null:
		_failures.append("setup error: blue_0 missing after setup_default()")
		return
	var drop_pos: Vector2 = victim.position
	# Drop a static obstacle centered on blue_0's current world position.
	# After this step, blue_0 is INSIDE a static obstacle's inflated footprint
	# and the lab must extricate it.
	world.add_static_obstacle(drop_pos, Vector2(60.0, 60.0))

	var max_jump := 0.0
	var max_jump_unit := ""
	var max_jump_step := -1
	var prev_positions: Dictionary = {}
	for unit in world.get_mobile_units():
		prev_positions[unit.id] = unit.position

	var num_steps := 120
	for step_idx in range(num_steps):
		world.step(dt)
		for unit in world.get_mobile_units():
			var prev: Vector2 = prev_positions.get(unit.id, unit.position)
			var jump := unit.position.distance_to(prev)
			if jump > max_jump:
				max_jump = jump
				max_jump_unit = unit.id
				max_jump_step = step_idx
			prev_positions[unit.id] = unit.position

	var target_jump := 16.0
	print(
		"LAB-003 static-escape max_any_jump_px = %.2f (unit=%s, step=%d, target ≤ %.1f)"
		% [max_jump, max_jump_unit, max_jump_step, target_jump]
	)
	if max_jump > target_jump:
		_failures.append(
			"max single-step displacement = %.2f px on unit %s at step %d, exceeds target ≤ %.1f"
			% [max_jump, max_jump_unit, max_jump_step, target_jump]
		)
