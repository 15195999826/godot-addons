extends Node

# Fable motion — crowds and blockers.
#
# Group move onto one point (fanout spread) settles everyone with no residual
# overlap; an unpushable blocker on the straight line is flowed around; an
# idle mobile unit in the way is shoved aside (Dota2 lane courtesy).

const TICK_DELTA := 1.0 / 60.0
const OVERLAP_TOLERANCE := 0.9


var _failures: Array[String] = []


func _ready() -> void:
	_test_group_move_settles_without_overlap()
	_test_unpushable_blocker_is_rounded()
	_test_idle_unit_is_shoved_aside()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab crowd blockers")
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


func _test_group_move_settles_without_overlap() -> void:
	# Default corridor scene: all 8 blues through the corridor to one point.
	var world := Dota2LabWorld.new()
	world.issue_move_all_mobile(world.current_target)
	var ticks := _run_until_idle(world, 1400, "group")
	var completed := 0
	var failed := 0
	for unit in world.get_mobile_units():
		var status := str(unit.last_order_snapshot().get("status", ""))
		if status == Dota2LabMoveOrder.STATUS_COMPLETED:
			completed += 1
		elif status == Dota2LabMoveOrder.STATUS_FAILED:
			failed += 1
	_assert_true(completed == 8, "group: all 8 orders complete, got %d (failed %d)" % [completed, failed])
	var overlap: float = world.motion.max_overlap_depth(world.units)
	_assert_true(
		overlap <= OVERLAP_TOLERANCE,
		"group: settled with residual overlap %.2f" % overlap
	)
	print("CROWD group: ticks=%d completed=%d overlap=%.3f" % [ticks, completed, overlap])


func _test_unpushable_blocker_is_rounded() -> void:
	var blocker := Dota2LabUnit.new("wall", "red", Vector2(500.0, 450.0), 13.0, 0.0, false)
	var mover := Dota2LabUnit.new("mover", "blue", Vector2(200.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([mover, blocker])
	world.issue_move("mover", Vector2(800.0, 450.0))
	var ticks := _run_until_idle(world, 600, "blocker")
	_assert_completed(mover, "blocker mover")
	_assert_true(
		mover.position.distance_to(Vector2(800.0, 450.0)) <= 12.0,
		"blocker: mover reaches far side, got %s" % str(mover.position)
	)
	_assert_true(
		blocker.position.distance_to(Vector2(500.0, 450.0)) < 0.5,
		"blocker: unpushable blocker must not move, got %s" % str(blocker.position)
	)
	print("CROWD blocker: ticks=%d mover=%s" % [ticks, str(mover.position)])


func _test_idle_unit_is_shoved_aside() -> void:
	var idler := Dota2LabUnit.new("idler", "blue", Vector2(500.0, 450.0), 11.0, 110.0, true)
	var mover := Dota2LabUnit.new("mover", "blue", Vector2(200.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([mover, idler])
	world.issue_move("mover", Vector2(800.0, 450.0))
	var ticks := _run_until_idle(world, 600, "idler")
	_assert_completed(mover, "idler mover")
	_assert_true(
		mover.position.distance_to(Vector2(800.0, 450.0)) <= 12.0,
		"idler: mover reaches far side, got %s" % str(mover.position)
	)
	_assert_true(
		idler.position.distance_to(Vector2(500.0, 450.0)) > 2.0,
		"idler: idle unit should have been shoved aside, got %s" % str(idler.position)
	)
	print("CROWD idler: ticks=%d idler_moved=%.1f" % [
		ticks, idler.position.distance_to(Vector2(500.0, 450.0))
	])


func _run_until_idle(world: Dota2LabWorld, max_ticks: int, label: String) -> int:
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		var all_idle := true
		for unit in world.units:
			if unit.state == Dota2LabUnit.STATE_MOVING:
				all_idle = false
				break
		if all_idle:
			return i + 1
	_failures.append("%s: units did not settle within %d ticks" % [label, max_ticks])
	return max_ticks


func _assert_completed(unit: Dota2LabUnit, label: String) -> void:
	var snapshot := unit.last_order_snapshot()
	if str(snapshot.get("status", "")) != Dota2LabMoveOrder.STATUS_COMPLETED:
		_failures.append("%s: expected completed order, got %s" % [label, str(snapshot)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
