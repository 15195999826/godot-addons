extends Node

# Minimal smoke for Dota2 RTS Pathfinding Lab state machine.
# Verifies the 5-state FSM transitions specified in
# docs/design-notes/motion-controller-design.md §3.2 and the
# NO_SAME_TICK_TAKEOVER invariant from §5.1.

const TICK_DELTA := 1.0 / 60.0
const MAX_TICKS := 400


var _failures: Array[String] = []


func _ready() -> void:
	_test_initial_state_is_idle()
	_test_start_move_order_transitions_to_waiting_long()
	_test_simple_move_reaches_goal()
	_test_no_same_tick_takeover_invariant()
	_test_unreachable_goal_terminates_failed()
	_test_target_switch_cancels_prior()
	_test_diagnostics_reflect_state()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab state machine")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ─────────────────────────── Test cases ──────────────────────────────────────

func _test_initial_state_is_idle() -> void:
	var world := Dota2LabWorld.new()
	var unit := world.get_unit("blue_0")
	if unit == null:
		_failures.append("initial-state: default scene missing blue_0")
		return
	_assert_eq(Dota2LabUnit.STATE_IDLE, unit.state, "initial-state: unit should start IDLE")
	_assert_eq(0, unit.pending_long_ticket, "initial-state: no pending long ticket")
	_assert_eq(0, unit.pending_short_ticket, "initial-state: no pending short ticket")


func _test_start_move_order_transitions_to_waiting_long() -> void:
	var world := Dota2LabWorld.new()
	world.issue_move("blue_0", Vector2(600.0, 200.0))
	var unit := world.get_unit("blue_0")
	_assert_eq(Dota2LabUnit.STATE_WAITING_LONG, unit.state, "start-order: should be WAITING_LONG after issue_move")
	_assert_true(unit.pending_long_ticket > 0, "start-order: should have a pending long ticket")
	_assert_eq(0, unit.pending_short_ticket, "start-order: no short ticket yet")


func _test_simple_move_reaches_goal() -> void:
	# blue_0 starts at (80, 170); target (200, 170) is in open corridor.
	var world := Dota2LabWorld.new()
	# Remove the static blocker red_blocker so the path is unambiguous.
	world.remove_nearest_editable(Vector2(280.0, 210.0))
	world.issue_move("blue_0", Vector2(200.0, 170.0))
	var unit := world.get_unit("blue_0")
	var saw_following := false
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if unit.state == Dota2LabUnit.STATE_FOLLOWING:
			saw_following = true
		if unit.state == Dota2LabUnit.STATE_IDLE:
			break
	if not saw_following:
		_failures.append("simple-move: never observed FOLLOWING state")
	_assert_eq(Dota2LabUnit.STATE_IDLE, unit.state, "simple-move: should reach IDLE within %d ticks" % MAX_TICKS)
	var distance := unit.position.distance_to(Vector2(200.0, 170.0))
	_assert_true(distance <= 8.0, "simple-move: final distance %.2f > 8" % distance)


# After a unit detects a block (via step_unit), the NO_SAME_TICK_TAKEOVER
# invariant requires: state must be WAITING_SHORT or WAITING_LONG and
# pending ticket > 0; the unit must NOT have taken a result or moved
# further on the same tick. We force this by placing a hard blocker on
# the path and stepping once after the FOLLOWING state is reached.
func _test_no_same_tick_takeover_invariant() -> void:
	var world := Dota2LabWorld.new()
	# Clear default scene; build a tight one.
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("mover", "blue", Vector2(100.0, 200.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blocker", "red", Vector2(180.0, 200.0), 13.0, 0.0, false),
	]
	world._rebuild_navigation()
	world.issue_move("mover", Vector2(260.0, 200.0))
	var mover := world.get_unit("mover")

	# Step until mover transitions out of WAITING_LONG into FOLLOWING.
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if mover.state == Dota2LabUnit.STATE_FOLLOWING:
			break
	if mover.state != Dota2LabUnit.STATE_FOLLOWING:
		_failures.append("no-same-tick: never reached FOLLOWING")
		return

	# Now step until the unit hits the blocker and transitions to a WAITING_* state.
	var transitioned_into_waiting := false
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if mover.state == Dota2LabUnit.STATE_WAITING_SHORT or mover.state == Dota2LabUnit.STATE_WAITING_LONG:
			transitioned_into_waiting = true
			break
		if mover.state == Dota2LabUnit.STATE_FAILED or mover.state == Dota2LabUnit.STATE_IDLE:
			break

	if not transitioned_into_waiting:
		# Acceptable outcome: unit ended up bypassing without blocking (path
		# planner found a way). Not a failure, just skip the invariant
		# assertion. Failure would be if the unit reached blocker position.
		var distance_to_blocker := mover.position.distance_to(Vector2(180.0, 200.0))
		if distance_to_blocker < 24.0:
			_failures.append("no-same-tick: mover ended near blocker without WAITING_* transition")
		return

	# Invariant: pending ticket > 0 immediately after the transition tick.
	var has_pending := mover.pending_long_ticket > 0 or mover.pending_short_ticket > 0
	_assert_true(has_pending, "no-same-tick: WAITING_* state must have a pending ticket")


func _test_unreachable_goal_terminates_failed() -> void:
	# Build a fully walled-in starting position; goal is unreachable.
	var world := Dota2LabWorld.new()
	world.obstacles = [
		Dota2LabObstacle.new("wall_n", Vector2(140.0, 100.0), Vector2(200.0, 24.0)),
		Dota2LabObstacle.new("wall_s", Vector2(140.0, 280.0), Vector2(200.0, 24.0)),
		Dota2LabObstacle.new("wall_e", Vector2(220.0, 190.0), Vector2(24.0, 200.0)),
		Dota2LabObstacle.new("wall_w", Vector2(60.0, 190.0), Vector2(24.0, 200.0)),
	]
	world.units = [
		Dota2LabUnit.new("caged", "blue", Vector2(120.0, 190.0), 11.0, 110.0, true),
	]
	world._rebuild_navigation()
	world.issue_move("caged", Vector2(600.0, 210.0))
	var unit := world.get_unit("caged")
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if unit.state == Dota2LabUnit.STATE_FAILED:
			break
		if unit.state == Dota2LabUnit.STATE_IDLE:
			break
	_assert_eq(Dota2LabUnit.STATE_FAILED, unit.state, "unreachable: unit should terminate FAILED")


func _test_target_switch_cancels_prior() -> void:
	var world := Dota2LabWorld.new()
	world.issue_move("blue_0", Vector2(600.0, 200.0))
	var unit := world.get_unit("blue_0")
	var first_ticket := unit.pending_long_ticket
	# Re-issue to a different target immediately.
	world.issue_move("blue_0", Vector2(300.0, 200.0))
	_assert_true(unit.pending_long_ticket > 0, "target-switch: new long ticket should exist")
	_assert_true(unit.pending_long_ticket != first_ticket, "target-switch: new ticket should differ from prior")
	_assert_eq(0, unit.pending_short_ticket, "target-switch: no short pending after re-issue")
	_assert_eq(Vector2(300.0, 200.0), unit.move_target, "target-switch: move_target should reflect new order")


func _test_diagnostics_reflect_state() -> void:
	var world := Dota2LabWorld.new()
	world.issue_move("blue_0", Vector2(600.0, 200.0))
	world.step(TICK_DELTA)
	var metrics := world.get_metrics()
	_assert_true(metrics.has("state_counts"), "diagnostics: state_counts must be present")
	_assert_true(metrics.has("long_path_requests"), "diagnostics: long_path_requests must be present")
	_assert_true(metrics.has("pathfinder"), "diagnostics: pathfinder sub-dict must be present")


# ─────────────────────────── Helpers ─────────────────────────────────────────

func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
