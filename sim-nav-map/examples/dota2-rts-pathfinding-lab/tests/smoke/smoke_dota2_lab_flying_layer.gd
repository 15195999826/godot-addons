extends Node

# Flying-layer contract: flyers plan on the obstacle-free air map and only
# separate against other flyers; the ground layer neither feels them nor
# changes its own behavior.
#
#   1. A flyer ordered straight through center_block (and over an unpushable
#      ground blocker + an idle ground unit) crosses in a straight line —
#      never deflected, provably inside the obstacle at some tick.
#   2. The same order on a ground unit detours around the block (contrast).
#   3. A flyer parked exactly on an idle ground unit exchanges no forces —
#      both positions stay bit-unchanged.
#   4. Two overlapping flyers DO separate (the air layer runs the same
#      contact solve within itself).

const TICK_DELTA := 1.0 / 60.0
const MAX_TICKS := 800

# center_block from Dota2LabWorld.setup_default(): center (690, 450),
# size (76, 280).
const CENTER_BLOCK_RECT := Rect2(652.0, 310.0, 76.0, 280.0)

const FLYER_GOAL := Vector2(980.0, 450.0)
const GROUND_GOAL := Vector2(980.0, 520.0)
const IDLE_OVERLAP_POS := Vector2(200.0, 780.0)


var _failures: Array[String] = []


func _ready() -> void:
	_test_flying_layer_contract()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab flying layer")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_flying_layer_contract() -> void:
	var world := Dota2LabWorld.new()
	# Default obstacles stay (center/north/south blocks); the unit cast is
	# replaced with layer fixtures. Units never enter the nav map, so no
	# rebuild is needed.
	world.units = [
		Dota2LabUnit.new_flying("flyer_cross", "air", Vector2(400.0, 450.0), 12.0, 150.0),
		Dota2LabUnit.new("ground_cross", "blue", Vector2(400.0, 520.0), 11.0, 110.0, true),
		Dota2LabUnit.new("under_path", "blue", Vector2(900.0, 450.0), 11.0, 110.0, true),
		Dota2LabUnit.new("block_under", "red", Vector2(760.0, 450.0), 13.0, 0.0, false),
		Dota2LabUnit.new("idle_g", "blue", IDLE_OVERLAP_POS, 11.0, 110.0, true),
		Dota2LabUnit.new_flying("idle_f", "air", IDLE_OVERLAP_POS, 12.0, 150.0),
		Dota2LabUnit.new_flying("pair_a", "air", Vector2(240.0, 760.0), 12.0, 150.0),
		Dota2LabUnit.new_flying("pair_b", "air", Vector2(252.0, 760.0), 12.0, 150.0),
	]

	_assert_eq(4, int(world.get_metrics().get("flying_count", -1)), "flying-layer: flying_count metric")

	world.issue_move("flyer_cross", FLYER_GOAL)
	world.issue_move("ground_cross", GROUND_GOAL)

	var flyer := world.get_unit("flyer_cross")
	var runner := world.get_unit("ground_cross")
	var crossed_block := false
	var max_flyer_dev := 0.0
	var max_runner_dev := 0.0
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if CENTER_BLOCK_RECT.has_point(flyer.position):
			crossed_block = true
		max_flyer_dev = maxf(max_flyer_dev, absf(flyer.position.y - 450.0))
		max_runner_dev = maxf(max_runner_dev, absf(runner.position.y - 520.0))
		if not flyer.is_moving() and not runner.is_moving() \
				and flyer.last_order != null and runner.last_order != null:
			break

	# 1. Straight overfly: through the block, never deflected by the block,
	# the unpushable blocker, or the idle ground unit sitting on the route.
	_assert_true(crossed_block, "flying-layer: flyer should cross the obstacle interior")
	_assert_true(max_flyer_dev < 4.0,
		"flying-layer: flyer deviated %.1f px off the straight line" % max_flyer_dev)
	if flyer.last_order == null:
		_failures.append("flying-layer: flyer order did not terminate")
	else:
		_assert_eq(Dota2LabMoveOrder.STATUS_COMPLETED, flyer.last_order.status, "flying-layer: flyer order status")
		_assert_eq(Dota2LabMoveOrder.REASON_ARRIVED, flyer.last_order.reason, "flying-layer: flyer order reason")

	# 2. Ground contrast: the same crossing forces a detour.
	if runner.last_order == null:
		_failures.append("flying-layer: ground runner order did not terminate")
	else:
		_assert_eq(Dota2LabMoveOrder.STATUS_COMPLETED, runner.last_order.status, "flying-layer: ground runner order status")
	_assert_true(max_runner_dev > 60.0,
		"flying-layer: ground runner should detour around the block (max dev %.1f px)" % max_runner_dev)

	# 3. Cross-layer stillness: exact co-location exchanges no forces, and the
	# idle ground unit under the flight path never moved either.
	_assert_eq_vec(IDLE_OVERLAP_POS, world.get_unit("idle_g").position, "flying-layer: idle ground unit under flyer moved")
	_assert_eq_vec(IDLE_OVERLAP_POS, world.get_unit("idle_f").position, "flying-layer: idle flyer over ground unit moved")
	_assert_eq_vec(Vector2(900.0, 450.0), world.get_unit("under_path").position, "flying-layer: idle unit under flight path moved")

	# 4. Flyer-vs-flyer separation still applies within the air layer.
	var pair_gap: float = world.get_unit("pair_a").position.distance_to(world.get_unit("pair_b").position)
	_assert_true(pair_gap >= 23.5,
		"flying-layer: overlapping flyers should separate (gap %.2f px)" % pair_gap)


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_eq(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _assert_eq_vec(expected: Vector2, actual: Vector2, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
