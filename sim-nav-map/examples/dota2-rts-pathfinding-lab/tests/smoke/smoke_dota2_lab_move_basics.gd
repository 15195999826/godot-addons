extends Node

# Fable motion — basic move-order contract.
#
# Covers: straight-line arrival, routing around statics, canonicalized goals
# (inside an obstacle / inside a sealed box), out-of-map goal clamping,
# cancel semantics, and the no-sideways-motion pipeline guard (displacement
# must follow facing — the v1/v2 ice-drift regression).

const TICK_DELTA := 1.0 / 60.0


var _failures: Array[String] = []


func _ready() -> void:
	_test_straight_line_arrival()
	_test_route_around_obstacles()
	_test_goal_inside_obstacle_completes_partial()
	_test_goal_outside_map_is_clamped()
	_test_cancel_mid_move()
	_test_sealed_box_goal_completes_inside()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab move basics")
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


func _test_straight_line_arrival() -> void:
	var unit := Dota2LabUnit.new("solo", "blue", Vector2(150.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([unit])
	var goal := Vector2(650.0, 450.0)
	world.issue_move("solo", goal)
	_assert_true(unit.state == Dota2LabUnit.STATE_MOVING, "straight: MOVING immediately after issue")

	var ticks := _run_until_idle(world, [unit], 420, "straight", true)
	_assert_order_completed(unit, Dota2LabMoveOrder.REASON_ARRIVED, "straight")
	_assert_true(
		unit.position.distance_to(goal) <= 9.0,
		"straight: final position near goal, got %.1f px away" % unit.position.distance_to(goal)
	)
	# 500 px at 110 px/s is ~273 ticks; generous but bounded.
	_assert_true(ticks < 420, "straight: bounded ticks, ran %d" % ticks)
	print("MOVE_BASICS straight: ticks=%d final=%s" % [ticks, str(unit.position)])


func _test_route_around_obstacles() -> void:
	var world := Dota2LabWorld.new()  # default corridor scene
	var unit_id := world.get_mobile_unit_ids()[0]
	var unit := world.get_unit(unit_id)
	var goal := Vector2(1160.0, 450.0)
	world.issue_move(unit_id, goal)
	var ticks := _run_until_idle(world, [unit], 1500, "route", false)
	_assert_order_completed(unit, Dota2LabMoveOrder.REASON_ARRIVED, "route")
	_assert_true(
		unit.position.distance_to(goal) <= 9.0,
		"route: final position near goal, got %.1f px away" % unit.position.distance_to(goal)
	)
	_assert_true(ticks < 1500, "route: bounded ticks, ran %d" % ticks)
	print("MOVE_BASICS route: ticks=%d final=%s" % [ticks, str(unit.position)])


func _test_goal_inside_obstacle_completes_partial() -> void:
	var obstacle := Dota2LabObstacle.new("block", Vector2(650.0, 450.0), Vector2(120.0, 120.0))
	var unit := Dota2LabUnit.new("solo", "blue", Vector2(300.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([unit], [obstacle])
	world.issue_move("solo", Vector2(650.0, 450.0))  # dead center of the block
	var ticks := _run_until_idle(world, [unit], 600, "partial", false)
	_assert_order_completed(unit, Dota2LabMoveOrder.REASON_ARRIVED_PARTIAL, "partial")
	_assert_true(
		not obstacle.contains_point_with_clearance(unit.position, 0.0),
		"partial: unit must stop outside the obstacle body"
	)
	print("MOVE_BASICS partial: ticks=%d final=%s reason=%s" % [
		ticks, str(unit.position), str(unit.last_order_snapshot().get("reason", ""))
	])


func _test_goal_outside_map_is_clamped() -> void:
	var unit := Dota2LabUnit.new("solo", "blue", Vector2(1100.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([unit])
	world.issue_move("solo", Vector2(5000.0, 450.0))  # far outside the map
	_assert_true(
		unit.move_target.x <= world.map_size.x,
		"clamp: goal must be clamped into the map, got %s" % str(unit.move_target)
	)
	var ticks := _run_until_idle(world, [unit], 400, "clamp", false)
	_assert_true(
		unit.last_order != null and unit.last_order.status == Dota2LabMoveOrder.STATUS_COMPLETED,
		"clamp: clamped order should complete"
	)
	print("MOVE_BASICS clamp: ticks=%d final=%s" % [ticks, str(unit.position)])


func _test_cancel_mid_move() -> void:
	var unit := Dota2LabUnit.new("solo", "blue", Vector2(150.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([unit])
	world.issue_move("solo", Vector2(900.0, 450.0))
	for i in range(30):
		world.step(TICK_DELTA)
	var mid_position := unit.position
	_assert_true(unit.state == Dota2LabUnit.STATE_MOVING, "cancel: still moving before cancel")
	world.cancel_move("solo")
	_assert_true(unit.state == Dota2LabUnit.STATE_IDLE, "cancel: IDLE right after cancel")
	_assert_true(unit.last_order_failed(), "cancel: last order recorded as failed")
	_assert_eq(
		Dota2LabMoveOrder.REASON_CANCELLED,
		str(unit.last_order_snapshot().get("reason", "")),
		"cancel: reason"
	)
	for i in range(20):
		world.step(TICK_DELTA)
	_assert_true(
		unit.position.distance_to(mid_position) < 1.0,
		"cancel: unit stays put after cancel"
	)


func _test_sealed_box_goal_completes_inside() -> void:
	# Unit sealed in a box; goal far outside. Canonicalization must pick a
	# reachable point (inside the box region) and the order completes partial —
	# never an endless retry.
	var walls: Array[Dota2LabObstacle] = [
		Dota2LabObstacle.new("wall_n", Vector2(300.0, 200.0), Vector2(300.0, 40.0)),
		Dota2LabObstacle.new("wall_s", Vector2(300.0, 600.0), Vector2(300.0, 40.0)),
		Dota2LabObstacle.new("wall_w", Vector2(170.0, 400.0), Vector2(40.0, 440.0)),
		Dota2LabObstacle.new("wall_e", Vector2(430.0, 400.0), Vector2(40.0, 440.0)),
	]
	var unit := Dota2LabUnit.new("boxed", "blue", Vector2(300.0, 400.0), 11.0, 110.0, true)
	var world := _open_world([unit], walls)
	world.issue_move("boxed", Vector2(1100.0, 400.0))
	var ticks := _run_until_idle(world, [unit], 600, "boxed", false)
	_assert_true(
		unit.last_order != null and unit.last_order.status == Dota2LabMoveOrder.STATUS_COMPLETED,
		"boxed: order must terminate as completed (canonical goal), got %s"
			% str(unit.last_order_snapshot())
	)
	_assert_true(
		unit.position.x > 190.0 and unit.position.x < 410.0,
		"boxed: unit must stay inside the box, got %s" % str(unit.position)
	)
	print("MOVE_BASICS boxed: ticks=%d final=%s reason=%s" % [
		ticks, str(unit.position), str(unit.last_order_snapshot().get("reason", ""))
	])


# Runs until every listed unit is IDLE. When `check_facing_locked` is set,
# asserts each tick that displacement direction matches facing (no sideways
# drift) — only valid for solo scenarios with no separation pushes.
func _run_until_idle(
	world: Dota2LabWorld,
	units: Array[Dota2LabUnit],
	max_ticks: int,
	label: String,
	check_facing_locked: bool
) -> int:
	for i in range(max_ticks):
		var before: Array[Vector2] = []
		for unit in units:
			before.append(unit.position)
		world.step(TICK_DELTA)
		if check_facing_locked:
			for k in range(units.size()):
				var unit := units[k]
				var moved := unit.position - before[k]
				if moved.length() < 0.05:
					continue
				var facing := Vector2.from_angle(unit.facing_angle_rad)
				if moved.normalized().dot(facing) < 0.995:
					_failures.append(
						"%s: sideways displacement at tick %d (dot=%.3f)"
							% [label, i, moved.normalized().dot(facing)]
					)
					return i
		var all_idle := true
		for unit in units:
			if unit.state != Dota2LabUnit.STATE_IDLE:
				all_idle = false
				break
		if all_idle:
			return i + 1
	_failures.append("%s: units did not settle within %d ticks" % [label, max_ticks])
	return max_ticks


func _assert_order_completed(unit: Dota2LabUnit, expected_reason: String, label: String) -> void:
	var snapshot := unit.last_order_snapshot()
	_assert_eq(Dota2LabMoveOrder.STATUS_COMPLETED, str(snapshot.get("status", "")), "%s: order status" % label)
	_assert_eq(expected_reason, str(snapshot.get("reason", "")), "%s: order reason" % label)


func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
