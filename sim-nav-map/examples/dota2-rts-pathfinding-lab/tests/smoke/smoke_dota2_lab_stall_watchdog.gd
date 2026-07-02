extends Node

# Fable motion — stall watchdog: every order terminates in bounded time.
#
# Near a crowded goal the unit settles (arrived_crowded). Far from the goal
# behind a physically sealed passage (blockers the planner can't see) the
# unit gets one replan, then the order fails as stalled. No holding loop,
# no forever-retry.

const TICK_DELTA := 1.0 / 60.0


var _failures: Array[String] = []


func _ready() -> void:
	_test_crowded_goal_settles_near()
	_test_sealed_passage_fails_stalled()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab stall watchdog")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _open_world(units: Array[Dota2LabUnit], obstacles: Array[Dota2LabObstacle] = []) -> Dota2LabWorld:
	var world := Dota2LabWorld.new()
	world.obstacles = obstacles
	world.units = units
	world.rebuild_navigation()
	world.clear_traces()
	return world


func _test_crowded_goal_settles_near() -> void:
	# Goal point sealed by a ring of unpushable blockers. The mover walks up,
	# stalls inside NEAR_GOAL_RADIUS, and settles as arrived_crowded.
	var goal := Vector2(700.0, 450.0)
	var units: Array[Dota2LabUnit] = []
	var ring_count := 8
	for i in range(ring_count):
		var angle := TAU * float(i) / float(ring_count)
		units.append(Dota2LabUnit.new(
			"ring_%d" % i, "red", goal + Vector2.from_angle(angle) * 26.0, 13.0, 0.0, false
		))
	var mover := Dota2LabUnit.new("mover", "blue", Vector2(300.0, 450.0), 11.0, 110.0, true)
	units.append(mover)
	var world := _open_world(units)
	world.issue_move("mover", goal)
	var ticks := _run_until_idle(world, [mover], 600, "crowded")
	_assert_eq(
		Dota2LabMoveOrder.STATUS_COMPLETED,
		str(mover.last_order_snapshot().get("status", "")),
		"crowded: order status"
	)
	_assert_eq(
		Dota2LabMoveOrder.REASON_ARRIVED_CROWDED,
		str(mover.last_order_snapshot().get("reason", "")),
		"crowded: order reason"
	)
	_assert_true(
		mover.position.distance_to(goal) < 80.0,
		"crowded: settled near the goal, got %s" % str(mover.position)
	)
	print("WATCHDOG crowded: ticks=%d final=%s" % [ticks, str(mover.position)])


func _test_sealed_passage_fails_stalled() -> void:
	# Two walls leave a single 60 px passage; a column of unpushable blockers
	# seals it. The planner (statics only) still routes through, the mover
	# grinds at the plug, gets one replan, then fails as stalled — bounded.
	var walls: Array[Dota2LabObstacle] = [
		Dota2LabObstacle.new("wall_n", Vector2(650.0, 210.0), Vector2(100.0, 420.0)),
		Dota2LabObstacle.new("wall_s", Vector2(650.0, 690.0), Vector2(100.0, 420.0)),
	]
	var units: Array[Dota2LabUnit] = [
		Dota2LabUnit.new("plug_0", "red", Vector2(650.0, 426.0), 13.0, 0.0, false),
		Dota2LabUnit.new("plug_1", "red", Vector2(650.0, 450.0), 13.0, 0.0, false),
		Dota2LabUnit.new("plug_2", "red", Vector2(650.0, 474.0), 13.0, 0.0, false),
	]
	var mover := Dota2LabUnit.new("mover", "blue", Vector2(200.0, 450.0), 11.0, 110.0, true)
	units.append(mover)
	var world := _open_world(units, walls)
	world.issue_move("mover", Vector2(1100.0, 450.0))
	var ticks := _run_until_idle(world, [mover], 1100, "sealed")
	_assert_eq(
		Dota2LabMoveOrder.STATUS_FAILED,
		str(mover.last_order_snapshot().get("status", "")),
		"sealed: order status"
	)
	_assert_eq(
		Dota2LabMoveOrder.REASON_STALLED,
		str(mover.last_order_snapshot().get("reason", "")),
		"sealed: order reason"
	)
	_assert_true(mover.repath_count >= 1, "sealed: one replan attempted before failing")
	_assert_true(
		mover.position.x < 640.0,
		"sealed: mover must not pass the plug, got %s" % str(mover.position)
	)
	print("WATCHDOG sealed: ticks=%d final=%s repaths=%d" % [
		ticks, str(mover.position), mover.repath_count
	])


func _run_until_idle(
	world: Dota2LabWorld,
	watched: Array[Dota2LabUnit],
	max_ticks: int,
	label: String
) -> int:
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		var all_idle := true
		for unit in watched:
			if unit.state == Dota2LabUnit.STATE_MOVING:
				all_idle = false
				break
		if all_idle:
			return i + 1
	_failures.append("%s: units did not settle within %d ticks" % [label, max_ticks])
	return max_ticks


func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
