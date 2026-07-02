extends Node

# Fable motion — separation solve contract.
#
# The hard invariant of the fable model: after every world step, no two units
# overlap beyond the solver's residual tolerance. Covers head-on pair pass,
# two opposing squads crossing, coincident-spawn split, and static projection
# (a unit dropped inside an obstacle is pushed out).

const TICK_DELTA := 1.0 / 60.0
# Solver residual tolerance per tick. Iterations cap at 6; dense transient
# crossings may keep a hair of overlap for a tick or two.
const OVERLAP_TOLERANCE := 0.9


var _failures: Array[String] = []


func _ready() -> void:
	_test_head_on_pair_passes()
	_test_opposing_squads_cross()
	_test_coincident_spawn_splits()
	_test_unit_inside_static_is_pushed_out()
	_test_zero_pushability_is_rigid_not_ghost()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab separation")
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


func _test_head_on_pair_passes() -> void:
	var a := Dota2LabUnit.new("a", "blue", Vector2(200.0, 450.0), 11.0, 110.0, true)
	var b := Dota2LabUnit.new("b", "red", Vector2(600.0, 450.0), 11.0, 110.0, true, PI)
	var world := _open_world([a, b])
	world.issue_move("a", Vector2(600.0, 450.0))
	world.issue_move("b", Vector2(200.0, 450.0))
	var ticks := _run_until_idle_with_invariant(world, 600, "head-on")
	_assert_completed(a, "head-on a")
	_assert_completed(b, "head-on b")
	_assert_true(
		a.position.distance_to(Vector2(600.0, 450.0)) <= 12.0,
		"head-on: a reaches swap point, got %s" % str(a.position)
	)
	_assert_true(
		b.position.distance_to(Vector2(200.0, 450.0)) <= 12.0,
		"head-on: b reaches swap point, got %s" % str(b.position)
	)
	print("SEPARATION head-on: ticks=%d a=%s b=%s" % [ticks, str(a.position), str(b.position)])


func _test_opposing_squads_cross() -> void:
	var units: Array[Dota2LabUnit] = []
	for i in range(4):
		units.append(Dota2LabUnit.new(
			"west_%d" % i, "blue", Vector2(220.0, 380.0 + 45.0 * float(i)), 11.0, 110.0, true
		))
	for i in range(4):
		units.append(Dota2LabUnit.new(
			"east_%d" % i, "red", Vector2(760.0, 380.0 + 45.0 * float(i)), 11.0, 110.0, true, PI
		))
	var world := _open_world(units)
	var west_ids: Array[String] = ["west_0", "west_1", "west_2", "west_3"]
	var east_ids: Array[String] = ["east_0", "east_1", "east_2", "east_3"]
	world.issue_move_ids(west_ids, Vector2(760.0, 470.0))
	world.issue_move_ids(east_ids, Vector2(220.0, 470.0))
	var ticks := _run_until_idle_with_invariant(world, 900, "squads")
	for unit in units:
		_assert_completed(unit, "squads %s" % unit.id)
		var target_x := 760.0 if unit.group_id == "blue" else 220.0
		_assert_true(
			absf(unit.position.x - target_x) < 130.0,
			"squads: %s should end on the far side, got %s" % [unit.id, str(unit.position)]
		)
	print("SEPARATION squads: ticks=%d" % ticks)


func _test_coincident_spawn_splits() -> void:
	var a := Dota2LabUnit.new("a", "blue", Vector2(400.0, 450.0), 11.0, 110.0, true)
	var b := Dota2LabUnit.new("b", "blue", Vector2(400.0, 450.0), 11.0, 110.0, true)
	var world := _open_world([a, b])
	world.step(TICK_DELTA)
	_assert_true(
		a.position.distance_to(b.position) >= (a.radius + b.radius) - OVERLAP_TOLERANCE,
		"coincident: split apart after one tick, distance %.2f" % a.position.distance_to(b.position)
	)
	world.issue_move("a", Vector2(700.0, 450.0))
	var ticks := _run_until_idle_with_invariant(world, 400, "coincident")
	_assert_completed(a, "coincident a")
	print("SEPARATION coincident: ticks=%d a=%s b=%s" % [ticks, str(a.position), str(b.position)])


func _test_unit_inside_static_is_pushed_out() -> void:
	var obstacle := Dota2LabObstacle.new("block", Vector2(500.0, 450.0), Vector2(100.0, 100.0))
	# Dropped dead center of the obstacle (illegal spawn).
	var unit := Dota2LabUnit.new("stuck", "blue", Vector2(505.0, 452.0), 11.0, 110.0, true)
	var world := _open_world([unit], [obstacle])
	world.step(TICK_DELTA)
	_assert_true(
		not obstacle.contains_point_with_clearance(unit.position, unit.radius - 0.5),
		"static-project: unit pushed out of obstacle body, got %s" % str(unit.position)
	)
	print("SEPARATION static-project: final=%s" % str(unit.position))


# pushability 0 means rigid, never ghost: with BOTH sliders at zero a head-on
# pair must still resolve overlap (forced even split) and pass — regression
# anchor for the total==0 skip that used to let movers clip through.
func _test_zero_pushability_is_rigid_not_ghost() -> void:
	var a := Dota2LabUnit.new("a", "blue", Vector2(200.0, 450.0), 11.0, 110.0, true)
	var b := Dota2LabUnit.new("b", "red", Vector2(600.0, 450.0), 11.0, 110.0, true, PI)
	var world := _open_world([a, b])
	world.motion.pushability_moving = 0.0
	world.motion.pushability_idle = 0.0
	world.issue_move("a", Vector2(600.0, 450.0))
	world.issue_move("b", Vector2(200.0, 450.0))
	var ticks := _run_until_idle_with_invariant(world, 600, "rigid-zero")
	_assert_completed(a, "rigid-zero a")
	_assert_completed(b, "rigid-zero b")
	print("SEPARATION rigid-zero: ticks=%d a=%s b=%s" % [ticks, str(a.position), str(b.position)])


func _run_until_idle_with_invariant(world: Dota2LabWorld, max_ticks: int, label: String) -> int:
	for i in range(max_ticks):
		world.step(TICK_DELTA)
		var overlap: float = world.motion.max_overlap_depth(world.units)
		if overlap > OVERLAP_TOLERANCE:
			_failures.append(
				"%s: overlap invariant broken at tick %d (depth %.2f)" % [label, i, overlap]
			)
			return i
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
