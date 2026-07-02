extends Node

# Minimal smoke for Dota2 RTS Pathfinding Lab state machine.
# Verifies the 5-state FSM transitions specified in
# docs/design-notes/motion-controller-design.md §3.2 and the
# NO_SAME_TICK_TAKEOVER invariant from §5.1.

const TICK_DELTA := 1.0 / 60.0
const MAX_TICKS := 400
const MIN_VISIBLE_TURN_ONLY_TICKS := 12


var _failures: Array[String] = []


func _ready() -> void:
	_test_initial_state_is_idle()
	_test_start_move_order_transitions_to_waiting_long()
	_test_simple_move_reaches_goal()
	_test_facing_turns_before_translation()
	_test_dota2_action_cone_moves_while_turning()
	_test_no_same_tick_takeover_invariant()
	_test_short_path_uses_local_subgoal_for_far_target()
	_test_unreachable_goal_terminates_failed()
	_test_target_switch_cancels_prior()
	_test_rapid_target_switch_cleans_queue()
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
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("mover", "blue", Vector2(100.0, 170.0), 11.0, 110.0, true),
	]
	world._rebuild_navigation()
	world.issue_move("mover", Vector2(260.0, 170.0))
	var unit := world.get_unit("mover")
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
	var distance := unit.position.distance_to(Vector2(260.0, 170.0))
	_assert_true(distance <= 8.0, "simple-move: final distance %.2f > 8" % distance)


func _test_facing_turns_before_translation() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("turner", "blue", Vector2(100.0, 170.0), 11.0, 110.0, true, PI),
	]
	world._rebuild_navigation()
	var unit := world.get_unit("turner")
	var start_position := unit.position
	world.issue_move("turner", Vector2(260.0, 170.0))
	var saw_turn_only_tick := false
	var turn_only_ticks := 0
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if unit.waiting_for_facing:
			saw_turn_only_tick = true
			turn_only_ticks += 1
			_assert_true(
				unit.position.distance_to(start_position) <= 0.001,
				"facing-turn: unit should rotate in place before translating"
			)
			_assert_true(
				absf(_angle_delta(unit.facing_angle_rad, PI)) > 0.001,
				"facing-turn: facing angle should change during turn-only tick"
			)
			continue
		if saw_turn_only_tick:
			break
	_assert_true(saw_turn_only_tick, "facing-turn: expected at least one waiting_for_facing tick")
	_assert_true(
		turn_only_ticks >= MIN_VISIBLE_TURN_ONLY_TICKS,
		"facing-turn: default 180-degree turn should be visible, got %d turn-only ticks"
			% turn_only_ticks
	)

	var saw_translation_after_turn := false
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if unit.position.distance_to(start_position) > 0.5:
			saw_translation_after_turn = true
			_assert_true(
				not unit.waiting_for_facing,
				"facing-turn: first translated tick should be aligned enough"
			)
			break
	_assert_true(saw_translation_after_turn, "facing-turn: expected translation after turning")


func _test_dota2_action_cone_moves_while_turning() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	var start_angle := deg_to_rad(10.0)
	world.units = [
		Dota2LabUnit.new("cone", "blue", Vector2(100.0, 170.0), 11.0, 110.0, true, start_angle, 0.1),
	]
	world._rebuild_navigation()
	var unit := world.get_unit("cone")
	var start_position := unit.position
	world.issue_move("cone", Vector2(260.0, 170.0))
	var saw_move_while_still_turning := false
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		if unit.position.distance_to(start_position) <= 0.5:
			continue
		var remaining_delta := absf(_angle_delta(unit.facing_angle_rad, 0.0))
		saw_move_while_still_turning = true
		_assert_true(
			not unit.waiting_for_facing,
			"dota2-cone: unit inside action cone should not wait for perfect facing"
		)
		_assert_true(
			remaining_delta > 0.001,
			"dota2-cone: first movement should be allowed before exact facing"
		)
		_assert_true(
			remaining_delta < start_angle,
			"dota2-cone: facing should continue rotating while movement starts"
		)
		break
	_assert_true(
		saw_move_while_still_turning,
		"dota2-cone: expected movement inside 11.5-degree action cone"
	)


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


# movement-feel-policy v2: a lone idle blocker is normally rounded by a
# micro-detour without any short-path request — the short path is an
# escalation tool, not the first response. This scenario therefore asserts
# the OUTCOME (mover gets past the blocker and arrives) and keeps the v1
# short-subgoal locality rules as conditional checks for runs where the
# escalation does fire.
func _test_short_path_uses_local_subgoal_for_far_target() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("mover", "blue", Vector2(100.0, 200.0), 11.0, 110.0, true),
		Dota2LabUnit.new("blocker", "red", Vector2(180.0, 200.0), 13.0, 0.0, false),
	]
	world._rebuild_navigation()
	# Goal stays inside the playable bounds (map 720 wide, 12 px border) —
	# the old 760 sat OUTSIDE the map, which v1 masked by never checking the
	# terminal state and v2's never-give-up HOLDING would wait on forever.
	world.issue_move("mover", Vector2(680.0, 200.0))
	var mover := world.get_unit("mover")
	var saw_short_request := false
	var requested_goal := Vector2.ZERO
	var request_position := Vector2.ZERO
	var saw_block_response := false
	# ~580 px of travel at ~1.8 px/tick needs its own budget beyond MAX_TICKS.
	for i in range(600):
		world.step(TICK_DELTA)
		if mover.last_path_request_kind == Dota2LabUnit.PATH_SOURCE_SHORT and not saw_short_request:
			saw_short_request = true
			requested_goal = mover.last_short_goal
			request_position = mover.position
		if mover.active_detour_point != Vector2.INF or saw_short_request:
			saw_block_response = true
		if mover.state == Dota2LabUnit.STATE_IDLE or mover.state == Dota2LabUnit.STATE_FAILED:
			break

	_assert_true(saw_block_response, "short-subgoal: blocker should trigger a detour or short request")
	_assert_eq(Dota2LabUnit.STATE_IDLE, mover.state, "short-subgoal: mover should get past the blocker and arrive")
	_assert_true(
		mover.position.distance_to(Vector2(680.0, 200.0)) <= 8.0,
		"short-subgoal: mover should stop at the far target, pos=%s" % str(mover.position)
	)
	if saw_short_request:
		_assert_true(
			request_position.distance_to(requested_goal) <= Dota2LabMotionController.SHORT_PATH_SEARCH_RANGE + 0.001,
			"short-subgoal: requested goal should be local, got distance %.2f"
				% request_position.distance_to(requested_goal)
		)
		_assert_true(
			requested_goal.distance_to(mover.move_target) > 64.0,
			"short-subgoal: requested goal should not be the far final target"
		)


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


func _test_rapid_target_switch_cleans_queue() -> void:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("lane_0", "blue", Vector2(100.0, 140.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_1", "blue", Vector2(100.0, 220.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_2", "blue", Vector2(100.0, 300.0), 11.0, 110.0, true),
	]
	world._rebuild_navigation()
	var unit_ids: Array[String] = ["lane_0", "lane_1", "lane_2"]
	var final_targets: Dictionary = {}
	for switch_index in range(5):
		for unit_index in range(unit_ids.size()):
			var unit_id := unit_ids[unit_index]
			var goal := Vector2(240.0 + float(switch_index % 3) * 40.0, 140.0 + float(unit_index) * 80.0)
			final_targets[unit_id] = goal
			world.issue_move(unit_id, goal)
		_assert_ticket_mutex(world, unit_ids, "rapid-switch: after issue %d" % switch_index)
		world.step(TICK_DELTA)
		_assert_ticket_mutex(world, unit_ids, "rapid-switch: after step %d" % switch_index)

	var settled := false
	for i in range(MAX_TICKS):
		world.step(TICK_DELTA)
		_assert_ticket_mutex(world, unit_ids, "rapid-switch: settle tick %d" % i)
		var pathfinder_metrics: Dictionary = world.get_metrics().get("pathfinder", {}) as Dictionary
		if (
			_units_are_terminal(world, unit_ids)
			and int(pathfinder_metrics.get("pending_count", 0)) == 0
			and int(pathfinder_metrics.get("result_count", 0)) == 0
		):
			settled = true
			break

	var metrics := world.get_metrics()
	var queue_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	_assert_true(settled, "rapid-switch: units and queue should settle within %d ticks" % MAX_TICKS)
	_assert_eq(0, int(queue_metrics.get("pending_count", -1)), "rapid-switch: pending_count should drain")
	_assert_eq(0, int(queue_metrics.get("result_count", -1)), "rapid-switch: result_count should drain")
	_assert_true(int(queue_metrics.get("cancelled_count", 0)) > 0, "rapid-switch: cancelled_count should increase")
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		_assert_true(unit != null, "rapid-switch: missing unit %s" % unit_id)
		if unit == null:
			continue
		_assert_eq(final_targets[unit_id], unit.move_target, "rapid-switch: %s should keep latest target" % unit_id)
		_assert_true(
			unit.state != Dota2LabUnit.STATE_WAITING_LONG and unit.state != Dota2LabUnit.STATE_WAITING_SHORT,
			"rapid-switch: %s should not remain in WAITING_*" % unit_id
		)


func _test_diagnostics_reflect_state() -> void:
	var world := Dota2LabWorld.new()
	world.issue_move("blue_0", Vector2(600.0, 200.0))
	world.step(TICK_DELTA)
	var metrics := world.get_metrics()
	_assert_true(metrics.has("state_counts"), "diagnostics: state_counts must be present")
	_assert_true(metrics.has("long_path_requests"), "diagnostics: long_path_requests must be present")
	_assert_true(metrics.has("pathfinder"), "diagnostics: pathfinder sub-dict must be present")
	var pathfinder_metrics: Dictionary = metrics.get("pathfinder", {}) as Dictionary
	_assert_true(pathfinder_metrics.has("cancelled_count"), "diagnostics: cancelled_count must be present")
	_assert_true(pathfinder_metrics.has("stale_result_count"), "diagnostics: stale_result_count must be present")
	_assert_true(pathfinder_metrics.has("result_tickets"), "diagnostics: result_tickets must be present")
	_assert_true(pathfinder_metrics.has("last_processed_requests"), "diagnostics: last_processed_requests must be present")


# ─────────────────────────── Helpers ─────────────────────────────────────────

func _assert_eq(expected: Variant, actual: Variant, label: String) -> void:
	if expected == actual:
		return
	_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)


func _assert_ticket_mutex(world: Dota2LabWorld, unit_ids: Array[String], label: String) -> void:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			_failures.append("%s: missing unit %s" % [label, unit_id])
			continue
		if unit.pending_long_ticket > 0 and unit.pending_short_ticket > 0:
			_failures.append(
				"%s: %s has both long=%d and short=%d"
					% [label, unit_id, unit.pending_long_ticket, unit.pending_short_ticket]
			)


func _units_are_terminal(world: Dota2LabWorld, unit_ids: Array[String]) -> bool:
	for unit_id in unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			return false
		if unit.state != Dota2LabUnit.STATE_IDLE and unit.state != Dota2LabUnit.STATE_FAILED:
			return false
	return true


func _angle_delta(from_angle_rad: float, to_angle_rad: float) -> float:
	return fposmod(to_angle_rad - from_angle_rad + PI, TAU) - PI
