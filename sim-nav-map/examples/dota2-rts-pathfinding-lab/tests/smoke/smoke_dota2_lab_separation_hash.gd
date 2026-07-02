extends Node

# Weld for the spatial-hash separation pass.
#
# Scenario A (realistic crowd, 41 units, group moves + mid-run re-command):
# the hashed pass must be BITWISE identical to the all-pairs loop every tick
# — it produces the same pairs in the same order whenever per-pass
# displacement stays under one hash cell, which realistic crowds do.
#
# Scenario B (adversarial near-coincident stack, stress-class): bitwise
# identity is not the contract past the one-cell-per-pass boundary; assert
# hard invariants instead (finite in-bounds positions, overlap convergence)
# plus run-to-run determinism of the hashed path itself.


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab separation hash weld")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures.slice(0, 5)))
	get_tree().quit(1)


func _run() -> void:
	_test_realistic_crowd_bitwise()
	_test_dense_stack_invariants_and_determinism()


func _test_realistic_crowd_bitwise() -> void:
	var world_brute := _build_crowd_world()
	var world_hash := _build_crowd_world()
	world_brute.motion.separation_brute_force_max = 1000000
	world_hash.motion.separation_brute_force_max = 0

	var delta := 1.0 / 60.0
	world_brute.issue_move_all_mobile(Vector2(1160.0, 450.0))
	world_hash.issue_move_all_mobile(Vector2(1160.0, 450.0))
	for tick in range(240):
		if tick == 120:
			world_brute.issue_move_all_mobile(Vector2(200.0, 700.0))
			world_hash.issue_move_all_mobile(Vector2(200.0, 700.0))
		world_brute.step(delta)
		world_hash.step(delta)
		if not _worlds_equal(world_brute, world_hash):
			_failures.append("realistic crowd diverged at tick %d" % tick)
			return


func _test_dense_stack_invariants_and_determinism() -> void:
	var first_positions := _run_dense_stack()
	var second_positions := _run_dense_stack()
	if first_positions != second_positions:
		_failures.append("dense stack hashed path is not deterministic across runs")


func _run_dense_stack() -> PackedVector2Array:
	var world := Dota2LabWorld.new()
	world.motion.separation_brute_force_max = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in range(30):
		world.units.append(Dota2LabUnit.new(
			"stack_%d" % i, "mid",
			Vector2(400.0 + rng.randf_range(-2.0, 2.0), 450.0 + rng.randf_range(-2.0, 2.0)),
			11.0, 110.0, true
		))
	var delta := 1.0 / 60.0
	world.issue_move_all_mobile(Vector2(900.0, 450.0))
	for tick in range(240):
		world.step(delta)
	var positions := PackedVector2Array()
	for unit in world.units:
		positions.append(unit.position)
		if not (is_finite(unit.position.x) and is_finite(unit.position.y)):
			_failures.append("dense stack produced non-finite position for %s" % unit.id)
		if unit.position.x < -1.0 or unit.position.y < -1.0 \
				or unit.position.x > world.map_size.x + 1.0 or unit.position.y > world.map_size.y + 1.0:
			_failures.append("dense stack pushed %s out of the map" % unit.id)
	var residual: float = world.motion.max_overlap_depth(world.units)
	if residual > 1.0:
		_failures.append("dense stack failed to converge (residual overlap %.2f px)" % residual)
	return positions


func _build_crowd_world() -> Dota2LabWorld:
	var world := Dota2LabWorld.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260702
	for i in range(32):
		var col := i % 8
		@warning_ignore("integer_division")
		var row: int = i / 8
		world.units.append(Dota2LabUnit.new(
			"extra_%d" % i, "mid",
			Vector2(
				90.0 + 34.0 * col + rng.randf_range(-6.0, 6.0),
				260.0 + 34.0 * row + rng.randf_range(-6.0, 6.0)
			),
			11.0, 110.0, true
		))
	return world


func _worlds_equal(a: Dota2LabWorld, b: Dota2LabWorld) -> bool:
	if a.units.size() != b.units.size():
		return false
	for i in range(a.units.size()):
		var unit_a: Dota2LabUnit = a.units[i]
		var unit_b: Dota2LabUnit = b.units[i]
		if unit_a.position != unit_b.position or unit_a.facing_angle_rad != unit_b.facing_angle_rad:
			return false
	return true
