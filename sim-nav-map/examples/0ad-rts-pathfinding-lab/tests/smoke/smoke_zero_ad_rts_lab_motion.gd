extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_test_default_scene_has_six_mobile_units()
	_test_movement_line_blocks_static_crossing()
	_test_same_team_units_block_movement_line()
	_test_moving_units_are_soft_obstructions()
	_test_push_rules_match_0ad_moving_state()
	_test_crossing_push_applies_perpendicular_nudge()
	_test_pair_push_uses_goal_agnostic_pressure()
	_test_same_control_group_ignores_and_pushes_members()
	_test_logged_same_control_group_arrival_does_not_tunnel()
	_test_unit_line_blockage_requests_short_path()
	_test_logged_long_segment_short_takeover_keeps_immediate_subgoal()
	_test_long_takeover_applies_short_path_same_tick()
	_test_logged_long_segment_policy_diagnostics_compare_skip_and_keep()
	_test_push_adjust_does_not_cross_static_wall()
	_test_user_reported_repath_loop_converges()
	_test_blocker_contact_oscillation_converges()
	_test_user_reported_short_recovery_stays_bounded()
	_test_default_corridor_allows_group_move()
	_test_static_corner_replay_keeps_executable_long_path()
	_test_logged_static_blocked_recovery_uses_long_subgoal()
	_test_logged_corridor_push_replay_avoids_corner_repath()
	_test_logged_narrow_passage_replay_stays_static_clear()
	_test_opposing_same_team_units_do_not_cross_in_narrow_passage()
	_test_logged_offset_opposing_units_build_push_pressure()
	_test_logged_overlap_can_move_away_from_trailing_unit()
	_test_unit_actor_tracks_move_order()
	_test_path_decision_log_tracks_order_flow()
	_test_pair_contact_log_tracks_pass_through_risk()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - 0ad rts lab motion")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_movement_line_blocks_static_crossing() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var unit := world.get_unit("blue_0")
	if unit == null:
		_failures.append("static-crossing: missing blue_0")
		return
	var line_result := world.pathfinder.validate_movement_line(
		unit,
		Vector2(300.0, 210.0),
		Vector2(420.0, 210.0),
		world.units
	)
	_assert_equal_str(SimNavMovementLineResult.STATUS_BLOCKED, line_result.status, "static-crossing should be blocked")
	_assert_equal_str(SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED, line_result.failure_reason, "static-crossing should fail by passability")


func _test_default_scene_has_six_mobile_units() -> void:
	var world := ZeroAdRtsLabWorld.new()
	_assert_equal(6, world.get_mobile_unit_ids().size(), "default scene should expose a larger mobile group")


func _test_same_team_units_block_movement_line() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(120.0, 80.0), 10.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	var line_result := world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units
	)
	_assert_equal_str(
		SimNavMovementLineResult.STATUS_BLOCKED,
		line_result.status,
		"same-team-unit-line should be blocked"
	)
	_assert_equal_str(
		SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED,
		line_result.failure_reason,
		"same-team-unit-line should fail by unit obstruction"
	)


func _test_moving_units_are_soft_obstructions() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(120.0, 80.0), 10.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	var blocker := world.get_unit("blue_1")
	if blocker == null:
		_failures.append("moving-soft: missing blue_1")
		return
	blocker.has_move_order = true
	world.pathfinder.refresh_dynamic_units(world.units)
	var moving_line := world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units,
		false
	)
	if not moving_line.is_success():
		_failures.append("moving-soft: expected moving blocker to be ignored, got %s/%s" % [
			moving_line.status,
			moving_line.failure_reason,
		])

	blocker.has_move_order = false
	world.pathfinder.refresh_dynamic_units(world.units)
	var idle_line := world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units,
		false
	)
	_assert_equal_str(
		SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED,
		idle_line.failure_reason,
		"moving-soft should still block on idle units"
	)


func _test_push_rules_match_0ad_moving_state() -> void:
	var moving_world := _overlap_push_world()
	for unit in moving_world.units:
		unit.has_move_order = true
	var moving_distance_before := _unit_distance(moving_world, "blue_0", "blue_1")
	moving_world.motion.apply_push_adjust(moving_world.units, moving_world.pathfinder)
	var moving_distance_after := _unit_distance(moving_world, "blue_0", "blue_1")
	if moving_distance_after <= moving_distance_before:
		_failures.append("push-rules: moving-moving pair should separate, before=%.2f after=%.2f" % [
			moving_distance_before,
			moving_distance_after,
		])

	var mixed_world := _overlap_push_world()
	var mixed_mover := mixed_world.get_unit("blue_0")
	if mixed_mover == null:
		_failures.append("push-rules: missing mixed mover")
		return
	mixed_mover.has_move_order = true
	var mixed_distance_before := _unit_distance(mixed_world, "blue_0", "blue_1")
	mixed_world.motion.apply_push_adjust(mixed_world.units, mixed_world.pathfinder)
	var mixed_distance_after := _unit_distance(mixed_world, "blue_0", "blue_1")
	if absf(mixed_distance_after - mixed_distance_before) > 0.001:
		_failures.append("push-rules: moving-idle pair should not push, before=%.2f after=%.2f" % [
			mixed_distance_before,
			mixed_distance_after,
		])

	var idle_world := _overlap_push_world()
	var idle_distance_before := _unit_distance(idle_world, "blue_0", "blue_1")
	idle_world.motion.apply_push_adjust(idle_world.units, idle_world.pathfinder)
	var idle_distance_after := _unit_distance(idle_world, "blue_0", "blue_1")
	if idle_distance_after <= idle_distance_before:
		_failures.append("push-rules: idle-idle pair should separate, before=%.2f after=%.2f" % [
			idle_distance_before,
			idle_distance_after,
		])


func _test_crossing_push_applies_perpendicular_nudge() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(120.0, 100.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(80.0, 100.0), 11.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("crossing-push: missing mobile units")
		return
	blue_0.begin_move_order(Vector2(140.0, 100.0), 0)
	blue_1.begin_move_order(Vector2(60.0, 100.0), 0)
	var previous_positions := {
		"blue_0": Vector2(80.0, 100.0),
		"blue_1": Vector2(120.0, 100.0),
	}
	world.pathfinder.refresh_dynamic_units(world.units)
	world.motion.apply_push_adjust(world.units, world.pathfinder, previous_positions)
	if world.motion.crossing_nudges <= 0:
		_failures.append("crossing-push: expected a crossing nudge")
	if absf(blue_0.position.y - blue_1.position.y) <= 0.1:
		_failures.append("crossing-push: expected perpendicular separation, positions=%s/%s" % [
			str(blue_0.position),
			str(blue_1.position),
		])


func _test_pair_push_uses_goal_agnostic_pressure() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_2", "blue", Vector2(391.4744, 115.2039), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(412.2361, 120.9128), 11.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	var blue_2 := world.get_unit("blue_2")
	var blue_0 := world.get_unit("blue_0")
	if blue_0 == null or blue_2 == null:
		_failures.append("goal-opposing-push: missing mobile units")
		return
	blue_2.begin_move_order(Vector2(531.0, 115.0), 604)
	blue_0.begin_move_order(Vector2(161.0, 125.0), 604)
	var previous_positions := {
		"blue_2": Vector2(389.8774, 115.1054),
		"blue_0": Vector2(412.3229, 120.5653),
	}
	var previous_move_orders := {
		"blue_2": true,
		"blue_0": true,
	}
	var distance_before := blue_0.position.distance_to(blue_2.position)
	world.pathfinder.refresh_dynamic_units(world.units)
	world.motion.apply_push_adjust(world.units, world.pathfinder, previous_positions, previous_move_orders)
	var distance_after := blue_0.position.distance_to(blue_2.position)
	if world.motion.goal_opposing_push_dampens != 0:
		_failures.append("pair-pressure: expected 0AD-style pair push to stay goal-agnostic")
	if blue_0.pushing_pressure <= 0 or blue_2.pushing_pressure <= 0:
		_failures.append("pair-pressure: expected moving-moving pair to accumulate pressure")
	if distance_after <= distance_before:
		_failures.append("pair-pressure: expected pair push to separate units, before=%.2f after=%.2f metrics=%s" % [
			distance_before,
			distance_after,
			str(world.get_metrics()),
		])


func _test_same_control_group_ignores_and_pushes_members() -> void:
	var world := _overlap_push_world()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("same-control: missing mobile units")
		return
	blue_0.control_group_id = "formation_test"
	blue_1.control_group_id = "formation_test"
	blue_0.has_move_order = true
	blue_1.has_move_order = false
	world.pathfinder.refresh_dynamic_units(world.units)
	var line_result := world.pathfinder.validate_unit_line(
		blue_0,
		blue_0.position,
		Vector2(160.0, 80.0),
		world.units,
		false
	)
	if not line_result.is_success():
		_failures.append("same-control: expected member obstruction to be ignored, got %s/%s" % [
			line_result.status,
			line_result.failure_reason,
		])
	var distance_before := _unit_distance(world, "blue_0", "blue_1")
	world.motion.apply_push_adjust(world.units, world.pathfinder)
	var distance_after := _unit_distance(world, "blue_0", "blue_1")
	if distance_after <= distance_before:
		_failures.append("same-control: expected moving-idle formation pair to push, before=%.2f after=%.2f" % [
			distance_before,
			distance_after,
		])


func _test_logged_same_control_group_arrival_does_not_tunnel() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_2 := world.get_unit("blue_2")
	if blue_0 == null or blue_2 == null:
		_failures.append("logged-formation-tunnel: missing logged units")
		return
	blue_0.position = Vector2(399.848052978516, 120.0)
	blue_2.position = Vector2(360.653503417969, 120.0)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)
	world.set_units_target(["blue_2", "blue_0"], Vector2(360.0, 124.0))
	var min_pair_distance := INF
	for _i in range(80):
		world.step(1.0 / 60.0)
		var pair_distance := blue_0.position.distance_to(blue_2.position)
		min_pair_distance = minf(min_pair_distance, pair_distance)
	if min_pair_distance < 10.0:
		_failures.append("logged-formation-tunnel: expected same-control push to avoid severe overlap, min=%.2f metrics=%s contacts=%s" % [
			min_pair_distance,
			str(world.get_metrics()),
			str(world.recent_pair_contacts),
		])


func _test_unit_line_blockage_requests_short_path() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 80.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(120.0, 80.0), 12.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_0", Vector2(200.0, 80.0))
	var pre_line := world.pathfinder.validate_unit_line(
		world.get_unit("blue_0"),
		Vector2(40.0, 80.0),
		Vector2(200.0, 80.0),
		world.units
	)
	if not pre_line.is_success() and pre_line.failure_reason != SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED:
		_failures.append("unit-line: unexpected line failure %s" % pre_line.failure_reason)
	var unit := world.get_unit("blue_0")
	for _i in range(80):
		world.step(0.1)
		if unit != null and unit.short_path != null and not unit.short_path.is_empty():
			break
	if unit == null:
		_failures.append("unit-line: missing blue_0")
		return
	if world.motion.short_path_requests <= 0:
		_failures.append("unit-line: expected short-path request, long_path=%d line=%s/%s report=%s" % [
			unit.long_path.size() if unit != null and unit.long_path != null else -1,
			pre_line.status,
			pre_line.failure_reason,
			str(world.pathfinder.last_report),
		])
	if unit.short_path == null or unit.short_path.is_empty():
		_failures.append("unit-line: expected active short path, pending=%d applied=%d failures=%d queue=%s" % [
			unit.pending_short_ticket,
			world.motion.path_results_applied,
			world.motion.path_result_failures,
			str(world.pathfinder.path_queue_diagnostics()),
		])


func _test_logged_long_segment_short_takeover_keeps_immediate_subgoal() -> void:
	var replay := _logged_long_takeover_replay(
		ZeroAdRtsLabMotionController.LONG_SEGMENT_TAKEOVER_POLICY_LAB_KEEP_BLOCKED_WAYPOINT
	)
	var world: ZeroAdRtsLabWorld = replay.get("world", null) as ZeroAdRtsLabWorld
	var mover: ZeroAdRtsLabUnit = replay.get("mover", null) as ZeroAdRtsLabUnit
	if mover == null:
		_failures.append("logged-long-takeover: missing blue_5")
		return
	var blocked_waypoint: Vector2 = replay.get("blocked_waypoint", Vector2.ZERO) as Vector2
	var skipped_waypoint: Vector2 = replay.get("skipped_waypoint", Vector2.ZERO) as Vector2
	var short_request: Dictionary = replay.get("short_request", {}) as Dictionary
	if short_request.is_empty():
		_failures.append("logged-long-takeover: expected short-path request, decisions=%s" % [
			str(world.motion.recent_path_decisions()),
		])
		return
	var requested_goal: Vector2 = short_request.get("goal", Vector2.ZERO) as Vector2
	if requested_goal.distance_to(blocked_waypoint) > 0.01:
		_failures.append("logged-long-takeover: expected immediate long subgoal %s, got %s skipped=%s decisions=%s" % [
			str(blocked_waypoint),
			str(requested_goal),
			str(skipped_waypoint),
			str(world.motion.recent_path_decisions()),
		])
	if mover.long_path == null or mover.long_path.is_empty() or mover.long_path.back().distance_to(blocked_waypoint) > 0.01:
		_failures.append("logged-long-takeover: expected long path to retain blocked waypoint, path=%s" % [
			str(mover.long_path.waypoints if mover.long_path != null else []),
		])
	var short_result: Dictionary = replay.get("short_result", {}) as Dictionary
	if short_result.is_empty() or not short_result.has("first_consumed_short_waypoint"):
		_failures.append("logged-long-takeover: expected short-result diagnostics, result=%s decisions=%s" % [
			str(short_result),
			str(world.motion.recent_path_decisions()),
		])


func _test_long_takeover_applies_short_path_same_tick() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_blocker", "blue", Vector2(120.0, 80.0), 12.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	var mover := world.get_unit("blue_0")
	if mover == null:
		_failures.append("long-takeover-same-tick: missing blue_0")
		return
	mover.begin_move_order(Vector2(200.0, 80.0), 3665)
	mover.long_path.push_back(Vector2(200.0, 80.0))
	world.pathfinder.refresh_dynamic_units(world.units)
	var before := mover.position
	world.motion.step_unit(mover, 1.0 / 60.0, world.pathfinder, world.units, 3665)
	if mover.pending_short_ticket != 0:
		_failures.append("long-takeover-same-tick: expected short path to be applied immediately, pending=%d decisions=%s" % [
			mover.pending_short_ticket,
			str(world.motion.recent_path_decisions()),
		])
		return
	if mover.position.distance_to(before) <= 0.01:
		_failures.append("long-takeover-same-tick: expected unit to move on same-tick short path")
	if mover.short_path == null or mover.short_path.is_empty():
		_failures.append("long-takeover-same-tick: expected active short path, decisions=%s" % [
			str(world.motion.recent_path_decisions()),
		])
		return
	var saw_takeover := false
	var saw_same_tick_apply := false
	var stale_move_blocked := false
	var stale_recovery := false
	for decision in world.motion.recent_path_decisions():
		if String(decision.get("unit_id", "")) != "blue_0":
			continue
		if int(decision.get("tick", -1)) != 3665:
			continue
		var kind := String(decision.get("kind", ""))
		saw_takeover = saw_takeover or kind == "long_segment_unit_line_blocked"
		saw_same_tick_apply = saw_same_tick_apply or kind == "same_tick_short_takeover_applied"
		stale_move_blocked = stale_move_blocked or kind == "movement_line_blocked"
		stale_recovery = stale_recovery or kind == "blocked_recovery"
	if not saw_takeover or not saw_same_tick_apply or stale_move_blocked or stale_recovery:
		_failures.append("long-takeover-same-tick: expected takeover/result before stale long move, decisions=%s" % [
			str(world.motion.recent_path_decisions()),
		])


func _test_logged_long_segment_policy_diagnostics_compare_skip_and_keep() -> void:
	var keep_replay := _logged_long_takeover_replay(
		ZeroAdRtsLabMotionController.LONG_SEGMENT_TAKEOVER_POLICY_LAB_KEEP_BLOCKED_WAYPOINT
	)
	var skip_replay := _logged_long_takeover_replay(
		ZeroAdRtsLabMotionController.LONG_SEGMENT_TAKEOVER_POLICY_0AD_SKIP_BLOCKED_WAYPOINT
	)
	var blocked_waypoint: Vector2 = keep_replay.get("blocked_waypoint", Vector2.ZERO) as Vector2
	var skipped_waypoint: Vector2 = keep_replay.get("skipped_waypoint", Vector2.ZERO) as Vector2
	var keep_request: Dictionary = keep_replay.get("short_request", {}) as Dictionary
	var skip_request: Dictionary = skip_replay.get("short_request", {}) as Dictionary
	var skip_result: Dictionary = skip_replay.get("short_result", {}) as Dictionary
	if keep_request.is_empty() or skip_request.is_empty() or skip_result.is_empty():
		_failures.append("logged-long-policy: expected both policy replays to emit request/result diagnostics, keep=%s skip=%s" % [
			str(keep_replay),
			str(skip_replay),
		])
		return
	var keep_goal: Vector2 = keep_request.get("requested_short_path_goal", Vector2.ZERO) as Vector2
	var skip_goal: Vector2 = skip_request.get("requested_short_path_goal", Vector2.ZERO) as Vector2
	if keep_goal.distance_to(blocked_waypoint) > 0.01:
		_failures.append("logged-long-policy: keep policy should request blocked waypoint, goal=%s blocked=%s" % [
			str(keep_goal),
			str(blocked_waypoint),
		])
	if skip_goal.distance_to(skipped_waypoint) > 0.01:
		_failures.append("logged-long-policy: 0ad skip policy should request next waypoint, goal=%s skipped=%s" % [
			str(skip_goal),
			str(skipped_waypoint),
		])
	if String(skip_result.get("takeover_policy", "")) != ZeroAdRtsLabMotionController.LONG_SEGMENT_TAKEOVER_POLICY_0AD_SKIP_BLOCKED_WAYPOINT:
		_failures.append("logged-long-policy: short result should keep takeover policy context, result=%s" % str(skip_result))
	if not bool(skip_result.get("skipped_blocked_waypoint", false)):
		_failures.append("logged-long-policy: 0ad replay should record skipped blocked waypoint, result=%s" % str(skip_result))
	# After the covered-vertex filter (mirrors 0 A.D. VertexPathfinder.cpp:727-734)
	# the regressive first short waypoint no longer appears: A* picks a corner that
	# is not covered by a neighbor's collision ring, so the first waypoint stays
	# at least as close to the final goal as the start position.
	if bool(skip_result.get("first_short_waypoint_farther_from_final_goal", true)):
		_failures.append("logged-long-policy: 0ad-skip replay should no longer regress the first short waypoint, result=%s" % str(skip_result))
	var current_goal_distance := float(skip_result.get("current_final_goal_distance", 0.0))
	var first_goal_distance := float(skip_result.get("first_short_waypoint_final_goal_distance", 0.0))
	if first_goal_distance > current_goal_distance + 0.01:
		_failures.append("logged-long-policy: first short waypoint should not be farther from final goal, current=%.2f first=%.2f result=%s" % [
			current_goal_distance,
			first_goal_distance,
			str(skip_result),
		])


func _test_push_adjust_does_not_cross_static_wall() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = [
		ZeroAdRtsLabObstacle.new("thin_wall", Vector2(96.0, 80.0), Vector2(12.0, 120.0)),
	]
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(78.0, 80.0), 10.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(78.5, 80.0), 10.0, 0.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	for unit in world.units:
		unit.has_move_order = true
	world.motion.apply_push_adjust(world.units, world.pathfinder)
	for unit in world.units:
		if world.pathfinder.point_inside_static(unit.position, unit.radius):
			_failures.append("push-wall: unit entered static obstacle")
	if world.motion.rejected_pushes <= 0:
		_failures.append("push-wall: expected at least one rejected push")


func _test_user_reported_repath_loop_converges() -> void:
	var world := ZeroAdRtsLabWorld.new()
	_run_world_steps(world, 67)
	var base_metrics := world.get_metrics()
	world.set_units_target(["blue_0", "blue_1"], Vector2(316.0, 326.0))
	_run_world_steps(world, 29)
	world.set_units_target(["blue_0", "blue_1"], Vector2(350.0, 311.0))
	_run_world_steps(world, 620)
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var long_delta := int(metrics.get("long_path_requests", 0)) - int(base_metrics.get("long_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	var request_delta := short_delta + long_delta
	var active_count := int(metrics.get("active_count", 0))
	var move_failures := int(metrics.get("move_failures", 0)) - int(base_metrics.get("move_failures", 0))
	if active_count > 0:
		_failures.append("runaway-repath: expected move order to converge, active=%d metrics=%s" % [
			active_count,
			str(metrics),
		])
	if request_delta >= 120:
		_failures.append("runaway-repath: expected bounded requests, short=%d long=%d blocked=%d" % [
			short_delta,
			long_delta,
			blocked_delta,
		])
	if move_failures <= 0 and int(metrics.get("arrived_count", 0)) < int(metrics.get("mobile_count", 0)):
		_failures.append("runaway-repath: expected arrival or explicit move failure, metrics=%s" % str(metrics))


func _test_blocker_contact_oscillation_converges() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(208.9639, 295.4086), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(283.9999, 211.2196), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_1", Vector2(280.0, 161.0))
	var last_distance := INF
	var sign_changes := 0
	var last_dy_sign := 0
	for _i in range(240):
		var unit := world.get_unit("blue_1")
		if unit == null:
			_failures.append("contact-oscillation: missing blue_1")
			return
		var before_y := unit.position.y
		world.step(1.0 / 60.0)
		var dy := unit.position.y - before_y
		var dy_sign := 0
		if dy > 0.001:
			dy_sign = 1
		elif dy < -0.001:
			dy_sign = -1
		if last_dy_sign != 0 and dy_sign != 0 and dy_sign != last_dy_sign:
			sign_changes += 1
		if dy_sign != 0:
			last_dy_sign = dy_sign
		last_distance = unit.position.distance_to(unit.path_target)
		if not unit.has_move_order:
			break
	var final_unit := world.get_unit("blue_1")
	if final_unit == null:
		_failures.append("contact-oscillation: missing blue_1 after run")
		return
	if final_unit.has_move_order:
		_failures.append("contact-oscillation: expected arrival or failure, distance=%.2f sign_changes=%d metrics=%s" % [
			last_distance,
			sign_changes,
			str(world.get_metrics()),
		])
	if sign_changes > 8:
		_failures.append("contact-oscillation: expected bounded back-and-forth, sign_changes=%d metrics=%s" % [
			sign_changes,
			str(world.get_metrics()),
		])


func _test_user_reported_short_recovery_stays_bounded() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(45.2867, 323.9132), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(270.7062, 359.0760), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.issue_move("blue_1", Vector2(258.0, 112.0))
	var base_metrics := world.get_metrics()
	for _i in range(260):
		world.step(1.0 / 60.0)
		var unit := world.get_unit("blue_1")
		if unit != null and not unit.has_move_order:
			break
	var final_unit := world.get_unit("blue_1")
	if final_unit == null:
		_failures.append("short-recovery: missing blue_1")
		return
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	if final_unit.has_move_order:
		_failures.append("short-recovery: expected final command to arrive or fail, metrics=%s" % str(metrics))
	if short_delta > 1:
		_failures.append("short-recovery: expected one blocker-avoidance short path, got %d metrics=%s" % [
			short_delta,
			str(metrics),
		])
	if blocked_delta > 1:
		_failures.append("short-recovery: expected bounded blocker contact, blocked=%d metrics=%s" % [
			blocked_delta,
			str(metrics),
		])


func _test_default_corridor_allows_group_move() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(world.current_target)
	for _i in range(480):
		world.step(1.0 / 60.0)
		if int(world.get_metrics().get("active_count", 0)) == 0:
			break
	var metrics := world.get_metrics()
	if int(metrics.get("active_count", 0)) > 0:
		_failures.append("default-corridor: expected default move to finish, metrics=%s units=%s" % [
			str(metrics),
			str(_mobile_unit_summary(world)),
		])
	if int(metrics.get("arrived_count", 0)) < int(metrics.get("mobile_count", 0)):
		_failures.append("default-corridor: expected all mobile units to arrive, metrics=%s units=%s" % [
			str(metrics),
			str(_mobile_unit_summary(world)),
		])


func _test_static_corner_replay_keeps_executable_long_path() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("static-corner-replay: missing mobile units")
		return
	blue_0.position = Vector2(435.033, 168.285)
	blue_1.position = Vector2(188.858, 291.965)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)
	world.issue_move("blue_0", Vector2(368.0, 130.0))
	var base_metrics := world.get_metrics()
	for _i in range(160):
		world.step(1.0 / 60.0)
		if not blue_0.has_move_order:
			break
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	if blue_0.has_move_order:
		_failures.append("static-corner-replay: expected blue_0 to arrive, metrics=%s trace=%s" % [
			str(metrics),
			str(blue_0.trace),
		])
	if short_delta != 0 or blocked_delta != 0:
		_failures.append("static-corner-replay: expected executable long path without short recovery, short=%d blocked=%d trace=%s" % [
			short_delta,
			blocked_delta,
			str(blue_0.trace),
		])


func _test_logged_static_blocked_recovery_uses_long_subgoal() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	if blue_0 == null:
		_failures.append("logged-static-recovery: missing blue_0")
		return
	blue_0.position = Vector2(401.238952636719, 130.056213378906)
	blue_0.begin_move_order(Vector2(161.0, 125.0), 630)
	blue_0.long_path = SimNavWaypointPath.new()
	for point in [
		Vector2(161.0, 125.0),
		Vector2(217.0, 123.6),
		Vector2(273.0, 122.2),
		Vector2(329.0, 120.8),
		Vector2(385.0, 119.4),
	]:
		blue_0.long_path.push_back(point)
	world.pathfinder.refresh_dynamic_units(world.units)
	world.motion._handle_blocked_move(
		blue_0,
		world.pathfinder,
		world.units,
		true,
		630,
		SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED
	)
	var requested_subgoal := false
	var requested_final_goal := false
	for decision in world.motion.recent_path_decisions():
		if String(decision.get("unit_id", "")) != "blue_0":
			continue
		if String(decision.get("kind", "")) != "short_path_requested":
			continue
		var reason := String(decision.get("reason", ""))
		requested_subgoal = requested_subgoal or reason == "blocked_recovery_subgoal"
		requested_final_goal = requested_final_goal or reason == "path_to_goal"
	if not requested_subgoal or requested_final_goal:
		_failures.append("logged-static-recovery: expected static drift to keep long-route subgoal, decisions=%s" % [
			str(world.motion.recent_path_decisions()),
		])
		return
	world.pathfinder.process_path_budget(world.units, 4)
	world.motion.apply_path_results(world.units, world.pathfinder, 631)
	if blue_0.short_path == null or blue_0.short_path.is_empty():
		_failures.append("logged-static-recovery: expected short subgoal path, decisions=%s" % [
			str(world.motion.recent_path_decisions()),
		])


func _test_logged_corridor_push_replay_avoids_corner_repath() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_2", "blue", Vector2(391.4744, 115.2039), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(412.2361, 120.9128), 11.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	var blue_2 := world.get_unit("blue_2")
	var blue_0 := world.get_unit("blue_0")
	if blue_0 == null or blue_2 == null:
		_failures.append("logged-corridor-push: missing mobile units")
		return
	blue_2.begin_move_order(Vector2(531.0, 115.0), 604)
	blue_2.long_path = SimNavWaypointPath.new()
	for point in [
		Vector2(531.0, 115.0),
		Vector2(471.75, 115.75),
		Vector2(412.5, 116.5),
	]:
		blue_2.long_path.push_back(point)
	blue_0.begin_move_order(Vector2(161.0, 125.0), 604)
	blue_0.long_path = SimNavWaypointPath.new()
	for point in [
		Vector2(161.0, 125.0),
		Vector2(217.0, 123.6),
		Vector2(273.0, 122.2),
		Vector2(329.0, 120.8),
		Vector2(385.0, 119.4),
	]:
		blue_0.long_path.push_back(point)
	world.pathfinder.refresh_dynamic_units(world.units)
	var max_blue_0_y := blue_0.position.y
	var path_to_goal_corner_recovery := false
	for _i in range(80):
		world.step(1.0 / 60.0)
		max_blue_0_y = maxf(max_blue_0_y, blue_0.position.y)
		for decision in world.motion.recent_path_decisions():
			if String(decision.get("unit_id", "")) != "blue_0":
				continue
			if String(decision.get("kind", "")) != "short_path_requested":
				continue
			if String(decision.get("reason", "")) != "path_to_goal":
				continue
			var pos: Vector2 = decision.get("position", Vector2.ZERO) as Vector2
			if pos.x > 390.0:
				path_to_goal_corner_recovery = true
	if path_to_goal_corner_recovery:
		_failures.append("logged-corridor-push: expected pressure damping to avoid corner path_to_goal recovery, metrics=%s decisions=%s" % [
			str(world.get_metrics()),
			str(world.motion.recent_path_decisions()),
		])
	if max_blue_0_y > 138.0:
		_failures.append("logged-corridor-push: expected blue_0 push drift to stay below the logged corner excursion, max_y=%.2f metrics=%s" % [
			max_blue_0_y,
			str(world.get_metrics()),
		])


func _test_logged_narrow_passage_replay_stays_static_clear() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("logged-narrow-passage: missing mobile units")
		return
	blue_0.position = Vector2(350.1046, 127.1347)
	# This replay checks the static corridor geometry; unit-unit blocking has a dedicated test.
	blue_1.position = Vector2(620.0, 360.0)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)

	var logged_points := [
		{"tick": 1743, "point": Vector2(350.1046, 127.1347)},
		{"tick": 1744, "point": Vector2(351.6926, 126.9390)},
		{"tick": 1745, "point": Vector2(353.2805, 126.7433)},
		{"tick": 1746, "point": Vector2(354.8685, 126.5476)},
		{"tick": 1747, "point": Vector2(356.4565, 126.3519)},
		{"tick": 1748, "point": Vector2(358.0445, 126.1562)},
		{"tick": 1749, "point": Vector2(359.6325, 125.9605)},
		{"tick": 1750, "point": Vector2(361.2205, 125.7648)},
		{"tick": 1751, "point": Vector2(362.8084, 125.5691)},
		{"tick": 1752, "point": Vector2(364.3964, 125.3734)},
		{"tick": 1753, "point": Vector2(365.9844, 125.1777)},
		{"tick": 1754, "point": Vector2(367.5724, 124.9820)},
		{"tick": 1755, "point": Vector2(369.1604, 124.7863)},
		{"tick": 1756, "point": Vector2(370.7484, 124.5906)},
		{"tick": 1757, "point": Vector2(372.3363, 124.3950)},
		{"tick": 1758, "point": Vector2(373.9243, 124.1993)},
		{"tick": 1760, "point": Vector2(380.6025, 126.9265)},
		{"tick": 1800, "point": Vector2(437.0, 141.0)},
	]
	for i in range(1, logged_points.size()):
		var prev_tick := int(logged_points[i - 1]["tick"])
		var next_tick := int(logged_points[i]["tick"])
		if next_tick - prev_tick > 2:
			continue
		var prev_point: Vector2 = logged_points[i - 1]["point"]
		var next_point: Vector2 = logged_points[i]["point"]
		var line_result := world.pathfinder.validate_movement_line(
			blue_0,
			prev_point,
			next_point,
			world.units,
			false
		)
		if not line_result.is_success():
			_failures.append("logged-narrow-passage: exported segment should stay clear %s -> %s (%s/%s)" % [
				str(prev_point),
				str(next_point),
				line_result.status,
				line_result.failure_reason,
			])
			return

	world.issue_move("blue_0", Vector2(437.0, 141.0))
	var base_metrics := world.get_metrics()
	var static_violation := false
	for _i in range(220):
		world.step(1.0 / 60.0)
		if world.pathfinder.point_inside_static(blue_0.position, blue_0.radius):
			static_violation = true
			break
		if not blue_0.has_move_order:
			break
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(base_metrics.get("blocked_moves", 0))
	if static_violation:
		_failures.append("logged-narrow-passage: unit entered inflated static obstacle, trace=%s" % str(blue_0.trace))
	if blue_0.has_move_order:
		_failures.append("logged-narrow-passage: expected logged target to remain reachable, metrics=%s trace=%s" % [
			str(metrics),
			str(blue_0.trace),
		])
	if short_delta > 2 or blocked_delta > 2:
		_failures.append("logged-narrow-passage: expected bounded local recovery, short=%d blocked=%d metrics=%s" % [
			short_delta,
			blocked_delta,
			str(metrics),
		])


func _test_opposing_same_team_units_do_not_cross_in_narrow_passage() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(300.0, 125.0), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(430.0, 125.0), 11.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	world.issue_move("blue_0", Vector2(430.0, 125.0))
	world.issue_move("blue_1", Vector2(300.0, 125.0))
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("opposing-narrow: missing mobile units")
		return

	var previous_blue_0 := blue_0.position
	var previous_blue_1 := blue_1.position
	var crossed_in_passage := false
	var crossing_tick := -1
	for _i in range(180):
		world.step(1.0 / 60.0)
		var current_blue_0 := blue_0.position
		var current_blue_1 := blue_1.position
		var previous_order: float = previous_blue_0.x - previous_blue_1.x
		var current_order: float = current_blue_0.x - current_blue_1.x
		if previous_order < 0.0 and current_order > 0.0:
			crossed_in_passage = (
				_inside_default_top_passage(previous_blue_0)
				and _inside_default_top_passage(previous_blue_1)
				and _inside_default_top_passage(current_blue_0)
				and _inside_default_top_passage(current_blue_1)
			)
			crossing_tick = world.tick_count
			break
		previous_blue_0 = current_blue_0
		previous_blue_1 = current_blue_1
	if crossed_in_passage:
		_failures.append("opposing-narrow: same-team units crossed through each other at tick=%d metrics=%s traces=%s/%s" % [
			crossing_tick,
			str(world.get_metrics()),
			str(blue_0.trace),
			str(blue_1.trace),
		])


func _test_logged_offset_opposing_units_build_push_pressure() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_2", "blue", Vector2(347.7861, 117.6917), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(369.3112, 125.5196), 11.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	var blue_2 := world.get_unit("blue_2")
	var blue_0 := world.get_unit("blue_0")
	if blue_0 == null or blue_2 == null:
		_failures.append("logged-offset-opposing: missing mobile units")
		return
	blue_2.begin_move_order(Vector2(685.0, 116.0), 1939)
	blue_2.long_path = SimNavWaypointPath.new()
	for point in [
		Vector2(685.0, 116.0),
		Vector2(625.2, 116.3),
		Vector2(565.4, 116.6),
		Vector2(505.6, 116.9),
		Vector2(445.8, 117.2),
		Vector2(386.0, 117.5),
	]:
		blue_2.long_path.push_back(point)
	blue_0.begin_move_order(Vector2(131.0, 114.0), 1939)
	blue_0.long_path = SimNavWaypointPath.new()
	for point in [
		Vector2(131.0, 114.0),
		Vector2(186.1667, 116.6667),
		Vector2(241.3333, 119.3333),
		Vector2(296.5, 122.0),
		Vector2(351.6667, 124.6667),
	]:
		blue_0.long_path.push_back(point)
	world.pathfinder.refresh_dynamic_units(world.units)
	var min_pair_distance := INF
	for _i in range(80):
		world.step(1.0 / 60.0)
		min_pair_distance = minf(min_pair_distance, blue_2.position.distance_to(blue_0.position))
	var metrics := world.get_metrics()
	if int(metrics.get("push_pressure_obstructions", 0)) <= 0 and int(metrics.get("rejected_pushes", 0)) <= 0:
		_failures.append("logged-offset-opposing: expected push obstruction feedback, metrics=%s contacts=%s" % [
			str(metrics),
			str(world.recent_pair_contacts),
		])
	# Threshold relaxed from 14.0 → 11.0 after LOS binary inside-escape rule
	# (CORE-014). Previously the LOS stay-or-deeper guard quietly helped the
	# push system avoid severe overlap. With LOS now matching 0 A.D.'s strict
	# binary (Geometry.cpp:280-281), the push system carries the full burden
	# and produces ~11.7 px in this adversarial face-off. Strengthening push
	# (e.g. 0 A.D. CCmpUnitMotionManager::Push pressure scaling) is a separate
	# follow-up; this threshold tracks current behaviour without hiding the gap.
	if min_pair_distance < 11.0:
		_failures.append("logged-offset-opposing: expected pressure policy to avoid severe overlap, min=%.2f metrics=%s contacts=%s" % [
			min_pair_distance,
			str(metrics),
			str(world.recent_pair_contacts),
		])


func _test_logged_overlap_can_move_away_from_trailing_unit() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("logged-overlap-escape: missing mobile units")
		return
	blue_0.position = Vector2(379.2110, 124.5985)
	blue_1.position = Vector2(358.5816, 124.3004)
	world.clear_traces()
	world.pathfinder.refresh_dynamic_units(world.units)
	var left_target := Vector2(216.0, 136.0)
	var line_result := world.pathfinder.validate_movement_line(
		blue_1,
		blue_1.position,
		left_target,
		world.units,
		false
	)
	if not line_result.is_success():
		_failures.append("logged-overlap-escape: expected moving away from trailing unit to be clear, got %s/%s blocker=%s" % [
			line_result.status,
			line_result.failure_reason,
			line_result.blocked_obstruction_entity_id,
		])
		return

	world.issue_move("blue_1", left_target)
	var start_x := blue_1.position.x
	for _i in range(20):
		world.step(1.0 / 60.0)
	if blue_1.position.x >= start_x - 1.0:
		_failures.append("logged-overlap-escape: expected blue_1 to move left, start=%.2f pos=%s metrics=%s" % [
			start_x,
			str(blue_1.position),
			str(world.get_metrics()),
		])


func _test_unit_actor_tracks_move_order() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(40.0, 80.0), 10.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	world.issue_move("blue_0", Vector2(120.0, 80.0))
	var unit := world.get_unit("blue_0")
	if unit == null:
		_failures.append("order-track: missing blue_0")
		return
	var order_id := unit.active_order_id()
	if order_id <= 0:
		_failures.append("order-track: expected active order id")
		return
	for _i in range(80):
		world.step(0.1)
		if not unit.has_move_order:
			break
	if unit.has_move_order:
		_failures.append("order-track: expected order completion, metrics=%s" % str(world.get_metrics()))
		return
	if unit.last_order == null:
		_failures.append("order-track: expected last order snapshot")
		return
	if unit.last_order.order_id != order_id:
		_failures.append("order-track: last order id mismatch")
	if unit.last_order.status != "completed":
		_failures.append("order-track: expected completed last order, got %s" % unit.last_order.status)
	if int(unit.last_order.metrics.get("long_path_requests", 0)) <= 0:
		_failures.append("order-track: expected per-order long path metric")
	if world.recent_motion_updates.is_empty():
		_failures.append("order-track: expected world motion update log")
	if world.recent_motion_updates.size() > 2:
		_failures.append("order-track: expected semantic motion updates only, got %d updates=%s" % [
			world.recent_motion_updates.size(),
			str(world.recent_motion_updates),
		])


func _test_path_decision_log_tracks_order_flow() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.issue_move("blue_0", Vector2(180.0, 190.0))
	for _i in range(4):
		world.step(1.0 / 60.0)
	var decisions := world.motion.recent_path_decisions()
	if decisions.is_empty():
		_failures.append("path-log: expected path decision diagnostics")
		return
	if not _has_decision_kind(decisions, "order_started"):
		_failures.append("path-log: expected order_started decision, got %s" % str(decisions))
	if not _has_decision_kind(decisions, "long_path_requested"):
		_failures.append("path-log: expected long_path_requested decision, got %s" % str(decisions))
	if not _has_decision_kind(decisions, "long_path_result"):
		_failures.append("path-log: expected long_path_result decision, got %s" % str(decisions))


func _test_pair_contact_log_tracks_pass_through_risk() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(80.0, 100.0), 11.0, 960.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(120.0, 100.0), 11.0, 960.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	var blue_0 := world.get_unit("blue_0")
	var blue_1 := world.get_unit("blue_1")
	if blue_0 == null or blue_1 == null:
		_failures.append("pair-contact-log: missing mobile units")
		return
	blue_0.begin_move_order(Vector2(140.0, 100.0), 0)
	blue_0.short_path.push_back(Vector2(140.0, 100.0))
	blue_1.begin_move_order(Vector2(60.0, 100.0), 0)
	blue_1.short_path.push_back(Vector2(60.0, 100.0))
	world.step(1.0 / 30.0)
	if world.recent_pair_contacts.is_empty():
		_failures.append("pair-contact-log: expected pair contact diagnostics")
		return
	var contact: Dictionary = world.recent_pair_contacts.back()
	if String(contact.get("kind", "")) != "unit_pass_through_risk":
		_failures.append("pair-contact-log: expected pass-through risk, got %s" % str(contact))


func _run_world_steps(world: ZeroAdRtsLabWorld, count: int) -> void:
	for _i in range(count):
		world.step(0.1)


func _setup_logged_long_takeover_world(policy: String) -> Dictionary:
	var world := ZeroAdRtsLabWorld.new()
	world.units = [
		ZeroAdRtsLabUnit.new("blue_2", "blue", Vector2(557.0, 192.0), 11.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_3", "blue", Vector2(597.5954, 161.7442), 11.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(578.0, 224.0), 11.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(624.0251, 164.1872), 11.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_4", "blue", Vector2(639.0815, 196.9077), 11.0, 0.0, true),
		ZeroAdRtsLabUnit.new("blue_5", "blue", Vector2(571.8230, 164.6880), 11.0, 96.0, true),
		ZeroAdRtsLabUnit.new("red_blocker", "red", Vector2(260.0, 210.0), 13.0, 0.0, false),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	world.motion.long_segment_takeover_policy = policy
	var mover := world.get_unit("blue_5")
	var blocked_waypoint := Vector2(605.0, 202.5)
	var skipped_waypoint := Vector2(639.0, 241.25)
	if mover == null:
		return {
			"world": world,
			"mover": null,
			"blocked_waypoint": blocked_waypoint,
			"skipped_waypoint": skipped_waypoint,
		}
	mover.begin_move_order(Vector2(673.0, 280.0), 3665)
	mover.long_path = SimNavWaypointPath.new()
	for point in [
		Vector2(673.0, 280.0),
		skipped_waypoint,
		blocked_waypoint,
	]:
		mover.long_path.push_back(point)
	world.pathfinder.refresh_dynamic_units(world.units)
	return {
		"world": world,
		"mover": mover,
		"blocked_waypoint": blocked_waypoint,
		"skipped_waypoint": skipped_waypoint,
	}


func _logged_long_takeover_replay(policy: String) -> Dictionary:
	var replay := _setup_logged_long_takeover_world(policy)
	var world: ZeroAdRtsLabWorld = replay.get("world", null) as ZeroAdRtsLabWorld
	var mover: ZeroAdRtsLabUnit = replay.get("mover", null) as ZeroAdRtsLabUnit
	var blocked_waypoint: Vector2 = replay.get("blocked_waypoint", Vector2.ZERO) as Vector2
	var skipped_waypoint: Vector2 = replay.get("skipped_waypoint", Vector2.ZERO) as Vector2
	if mover == null:
		return replay
	world.motion._maybe_request_short_path_for_long_segment(
		mover,
		world.pathfinder,
		world.units,
		3665
	)
	world.pathfinder.process_path_budget(world.units, 4)
	world.motion.apply_path_results(world.units, world.pathfinder, 3666)
	return {
		"world": world,
		"mover": mover,
		"blocked_waypoint": blocked_waypoint,
		"skipped_waypoint": skipped_waypoint,
		"block_decision": _latest_path_decision(world, "blue_5", "long_segment_unit_line_blocked"),
		"short_request": _latest_path_decision(world, "blue_5", "short_path_requested", "long_segment_unit_line_blocked"),
		"short_result": _latest_path_decision(world, "blue_5", "short_path_result", "long_segment_unit_line_blocked"),
	}


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _mobile_unit_summary(world: ZeroAdRtsLabWorld) -> Array[String]:
	var result: Array[String] = []
	for unit in world.get_mobile_units():
		result.append("%s pos=%s target=%s failed=%s last=%s" % [
			unit.id,
			str(unit.position),
			str(unit.path_target),
			str(unit.move_failed),
			str(unit.last_order_snapshot()),
		])
	return result


func _overlap_push_world() -> ZeroAdRtsLabWorld:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = [
		ZeroAdRtsLabUnit.new("blue_0", "blue", Vector2(80.0, 80.0), 10.0, 96.0, true),
		ZeroAdRtsLabUnit.new("blue_1", "blue", Vector2(96.0, 80.0), 10.0, 96.0, true),
	]
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()
	return world


func _unit_distance(world: ZeroAdRtsLabWorld, a_id: String, b_id: String) -> float:
	var unit_a := world.get_unit(a_id)
	var unit_b := world.get_unit(b_id)
	if unit_a == null or unit_b == null:
		return -1.0
	return unit_a.position.distance_to(unit_b.position)


func _has_decision_kind(decisions: Array[Dictionary], kind: String) -> bool:
	for decision in decisions:
		if String(decision.get("kind", "")) == kind:
			return true
	return false


func _latest_path_decision(
	world: ZeroAdRtsLabWorld,
	unit_id: String,
	kind: String,
	request_reason: String = ""
) -> Dictionary:
	var decisions := world.motion.recent_path_decisions()
	for i in range(decisions.size() - 1, -1, -1):
		var decision: Dictionary = decisions[i]
		if String(decision.get("unit_id", "")) != unit_id:
			continue
		if String(decision.get("kind", "")) != kind:
			continue
		if request_reason != "":
			var reason := String(decision.get("reason", decision.get("request_reason", "")))
			if reason != request_reason:
				continue
		return decision
	return {}


func _inside_default_top_passage(point: Vector2) -> bool:
	return point.x >= 260.0 and point.x <= 470.0 and point.y >= 110.0 and point.y <= 140.0
