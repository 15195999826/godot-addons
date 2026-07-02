extends Node


const TICK_DELTA := 1.0 / 60.0
const QUEUE_LATENCY_BOUND_TICKS := 8
const SOLO_MOVE_TICKS := 700
const STATIC_REPLAN_TICKS := 900
const ARRIVE_TOLERANCE := 8.0


var _failures: Array[String] = []


func _ready() -> void:
	_test_click_to_move_latency()
	_test_long_path_delivery_bound()
	_test_solo_no_false_failed()
	_test_static_blocker_midpath_replans()
	_test_walled_in_unit_holds_then_resumes()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab movement feel contract")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_click_to_move_latency() -> void:
	var world := _single_unit_world(Vector2(100.0, 450.0))
	var unit := world.get_unit("solo")
	var start_position := unit.position
	world.issue_move("solo", Vector2(360.0, 450.0))

	_assert_eq(Dota2LabUnit.STATE_WAITING_LONG, unit.state, "a1-latency: state")
	_assert_true(unit.pending_long_ticket > 0, "a1-latency: pending long ticket")
	_assert_eq(0, unit.pending_short_ticket, "a1-latency: no pending short ticket")
	_assert_true(unit.position.distance_to(start_position) <= 0.001, "a1-latency: command tick should not move unit")


func _test_long_path_delivery_bound() -> void:
	var world := _single_unit_world(Vector2(100.0, 450.0))
	var unit := world.get_unit("solo")
	world.issue_move("solo", Vector2(360.0, 450.0))

	var delivered := false
	for i in range(QUEUE_LATENCY_BOUND_TICKS):
		world.step(TICK_DELTA)
		if unit.state == Dota2LabUnit.STATE_FOLLOWING or unit.state == Dota2LabUnit.STATE_IDLE:
			delivered = true
			break
		if unit.state == Dota2LabUnit.STATE_FAILED:
			break

	_assert_true(delivered, "a2-delivery: reachable long path should deliver within bound")
	_assert_true(unit.state != Dota2LabUnit.STATE_FAILED, "a2-delivery: reachable long path should not fail")


func _test_solo_no_false_failed() -> void:
	var world := _single_unit_world(Vector2(100.0, 450.0))
	var unit_ids: Array[String] = ["solo"]
	world.issue_move("solo", Vector2(860.0, 450.0))

	var settled := _run_until_terminal(world, unit_ids, SOLO_MOVE_TICKS)
	var unit := world.get_unit("solo")
	_assert_true(settled, "a4-solo: should settle within %d ticks" % SOLO_MOVE_TICKS)
	_assert_eq(Dota2LabUnit.STATE_IDLE, unit.state, "a4-solo: reachable solo command should end IDLE")
	_assert_true(unit.position.distance_to(Vector2(860.0, 450.0)) <= 8.0, "a4-solo: final distance should be near goal")
	_assert_true(_queue_is_drained(world), "a4-solo: queue should drain")


func _test_static_blocker_midpath_replans() -> void:
	var world := _single_unit_world(Vector2(100.0, 450.0))
	var unit_ids: Array[String] = ["solo"]
	world.issue_move("solo", Vector2(900.0, 450.0))
	var unit := world.get_unit("solo")

	var moving := false
	for i in range(120):
		world.step(TICK_DELTA)
		if unit.state == Dota2LabUnit.STATE_FOLLOWING and unit.position.x >= 165.0:
			moving = true
			break
		if unit.state == Dota2LabUnit.STATE_FAILED:
			break
	_assert_true(moving, "a5-static: unit should be moving before blocker edit")
	if not moving:
		return

	world.add_static_obstacle(Vector2(430.0, 450.0), Vector2(96.0, 260.0))
	_assert_eq(Dota2LabUnit.STATE_WAITING_LONG, unit.state, "a5-static: edit should trigger WAITING_LONG replan")
	_assert_true(unit.pending_long_ticket > 0, "a5-static: replan should create pending long ticket")

	var saw_following_after_replan := false
	for i in range(STATIC_REPLAN_TICKS):
		world.step(TICK_DELTA)
		if unit.state == Dota2LabUnit.STATE_FOLLOWING:
			saw_following_after_replan = true
		if _units_are_terminal(world, unit_ids) and _queue_is_drained(world):
			break

	_assert_true(saw_following_after_replan, "a5-static: should resume FOLLOWING after blocker replan")
	_assert_eq(Dota2LabUnit.STATE_IDLE, unit.state, "a5-static: reachable route around blocker should reach IDLE")
	_assert_true(_queue_is_drained(world), "a5-static: queue should drain after terminal settle")


# movement-feel-policy v2 A9: a unit boxed in by idle units enters HOLDING
# (order retained, bounded request rate) instead of FAILED, and resumes to
# the goal on its own once a blocker is removed.
func _test_walled_in_unit_holds_then_resumes() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	var center := Vector2(400.0, 450.0)
	var wall_units: Array[Dota2LabUnit] = [
		Dota2LabUnit.new("walled", "blue", center, 11.0, 110.0, true),
	]
	# Six stationary blockers on a tight ring: adjacent-gap chord ≈ 26 px,
	# below the relaxed pass requirement (11 + 7 = 18 per side), so the
	# center unit cannot slide or detour out.
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		wall_units.append(Dota2LabUnit.new(
			"ring_%d" % i, "red", center + Vector2.RIGHT.rotated(angle) * 26.0, 11.0, 0.0, false
		))
	world.units = wall_units
	world._rebuild_navigation()
	world.clear_traces()
	var unit := world.get_unit("walled")
	world.issue_move("walled", Vector2(700.0, 450.0))

	var entered_holding := false
	var holding_ticks := 0
	for i in range(600):
		world.step(TICK_DELTA)
		if unit.state == Dota2LabUnit.STATE_HOLDING:
			entered_holding = true
			holding_ticks += 1
	_assert_true(entered_holding, "a9-hold: walled-in unit should enter HOLDING")
	_assert_eq(Dota2LabUnit.STATE_HOLDING, unit.state, "a9-hold: unit should still be HOLDING while walled in")
	var metrics := world.get_metrics()
	var request_total := int(metrics.get("long_path_requests", 0)) + int(metrics.get("short_path_requests", 0))
	_assert_true(
		request_total <= 600 / 30 + 12,
		"a9-hold: holding activity should stay bounded, requests=%d" % request_total
	)

	# Open the ring toward the goal; the held order must resume by itself.
	for i in range(world.units.size() - 1, -1, -1):
		if world.units[i].id == "ring_0":
			world.units.remove_at(i)
	var unit_ids: Array[String] = ["walled"]
	var settled := _run_until_terminal(world, unit_ids, 900)
	_assert_true(settled, "a9-hold: unit should settle after the ring opens")
	_assert_eq(Dota2LabUnit.STATE_IDLE, unit.state, "a9-hold: resumed order should reach IDLE")
	_assert_true(
		unit.position.distance_to(Vector2(700.0, 450.0)) <= ARRIVE_TOLERANCE,
		"a9-hold: unit should reach the goal after release, pos=%s" % str(unit.position)
	)


func _single_unit_world(start: Vector2) -> Dota2LabWorld:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("solo", "blue", start, 11.0, 110.0, true),
	]
	world._rebuild_navigation()
	world.clear_traces()
	return world


func _run_until_terminal(
	world: Dota2LabWorld,
	unit_ids: Array[String],
	max_ticks: int
) -> bool:
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		if _units_are_terminal(world, unit_ids) and _queue_is_drained(world):
			return true
	return false


func _units_are_terminal(world: Dota2LabWorld, unit_ids: Array[String]) -> bool:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			return false
		if unit.state != Dota2LabUnit.STATE_IDLE and unit.state != Dota2LabUnit.STATE_FAILED:
			return false
	return true


func _queue_is_drained(world: Dota2LabWorld) -> bool:
	var metrics := world.get_metrics()
	var pathfinder_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	return (
		int(pathfinder_metrics.get("pending_count", 0)) == 0
		and int(pathfinder_metrics.get("result_count", 0)) == 0
		and _result_ticket_count(pathfinder_metrics) == 0
	)


func _result_ticket_count(pathfinder_metrics: Dictionary) -> int:
	var tickets: Array = pathfinder_metrics.get("result_tickets", []) as Array
	return tickets.size()


func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
