extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map path request queue")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_ticket_ids_are_nonzero_monotonic()
	_test_budget_processes_fifo()
	_test_elapsed_budget_limits_followup_requests()
	_test_cancel_pending_skips_without_spending_budget()
	_test_cancel_result_removes_stale_result()
	_test_short_request_result()
	_test_deterministic_repeated_queue()
	_test_long_query_result_metadata()
	_test_worker_batch_collects_results_and_filters_cancelled_ticket()
	_test_short_result_metadata_and_filter_clone()
	_test_queue_diagnostics_contract()


func _test_ticket_ids_are_nonzero_monotonic() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var ticket_a := queue.enqueue_long_path(
		nav_map.navcell_center_world(Vector2i(1, 1)),
		SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))),
		pass_mask
	)
	var ticket_b := queue.enqueue_long_path(
		nav_map.navcell_center_world(Vector2i(1, 1)),
		SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(5, 1))),
		pass_mask
	)
	_assert_equal(1, ticket_a, "first async ticket should be non-zero and start at 1")
	_assert_equal(2, ticket_b, "tickets should increase monotonically")


func _test_budget_processes_fifo() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var ticket_a := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))), pass_mask)
	var ticket_b := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(5, 1))), pass_mask)

	_assert_equal(1, queue.process_budget(1), "budget=1 should process one request")
	_assert_true(queue.has_result(ticket_a), "first ticket should have result after first budget step")
	_assert_false(queue.has_result(ticket_b), "second ticket should wait for next budget step")
	var path_a := queue.take_result(ticket_a)
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(4, 1)), path_a.waypoints[0], "first result should match first queued goal")

	_assert_equal(1, queue.process_budget(1), "second budget step should process second request")
	var path_b := queue.take_result(ticket_b)
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(5, 1)), path_b.waypoints[0], "second result should match second queued goal")


func _test_elapsed_budget_limits_followup_requests() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var ticket_a := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))), pass_mask)
	var ticket_b := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(5, 1))), pass_mask)

	_assert_equal(1, queue.process_budget(2, 1), "elapsed budget should stop after the first live request")
	_assert_true(queue.has_result(ticket_a), "first ticket should still complete under elapsed budget")
	_assert_false(queue.has_result(ticket_b), "second ticket should wait when elapsed budget is exhausted")
	_assert_equal(1, int(queue.get_diagnostics().get("pending_count", 0)), "elapsed budget should leave pending work queued")


func _test_cancel_pending_skips_without_spending_budget() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var ticket_a := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))), pass_mask)
	var ticket_b := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(5, 1))), pass_mask)

	_assert_true(queue.cancel(ticket_a), "cancel should remove pending first request")
	_assert_equal(1, queue.process_budget(1), "cancelled pending request should not spend budget")
	_assert_false(queue.has_result(ticket_a), "cancelled pending ticket should not produce stale result")
	_assert_true(queue.has_result(ticket_b), "next live ticket should be processed by same budget")


func _test_cancel_result_removes_stale_result() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var ticket := queue.enqueue_long_path(
		nav_map.navcell_center_world(Vector2i(1, 1)),
		SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))),
		pass_mask
	)
	queue.process_budget(1)
	_assert_true(queue.has_result(ticket), "processed ticket should have result before cancellation")
	_assert_true(queue.cancel(ticket), "cancel should remove already-computed stale result")
	_assert_null(queue.take_result(ticket), "cancelled computed ticket should not be takeable")


func _test_short_request_result() -> void:
	var fixture := _make_short_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var request := SimNavShortPathRequest.new()
	request.start = Vector2(10.0, 50.0)
	request.goal = SimNavPathGoal.point(Vector2(90.0, 50.0))
	request.clearance = 6.0
	request.range_px = 160.0
	request.pass_mask = 1
	var ticket := queue.enqueue_short_path(request)
	_assert_equal(1, queue.process_budget(1), "short request should be processed by budget")
	var path := queue.take_result(ticket)
	_assert_equal(1, path.size(), "direct short request should produce single-goal path")
	_assert_equal_vec(request.goal.center, path.waypoints[0], "short request result should match goal")


func _test_deterministic_repeated_queue() -> void:
	var signature_a := _run_deterministic_queue_once()
	var signature_b := _run_deterministic_queue_once()
	_assert_equal_str(signature_a, signature_b, "same queued request should produce deterministic result")


func _test_long_query_result_metadata() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var query := SimNavLongPathQuery.from_values(
		nav_map.navcell_center_world(Vector2i(1, 1)),
		SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 1))),
		pass_mask,
		"ground"
	)
	query.post_process = SimNavLongPathQuery.POST_PROCESS_MAX_SPACING
	query.waypoint_spacing = 8.0
	var ticket := queue.enqueue_long_path_query(query)
	query.goal.center = nav_map.navcell_center_world(Vector2i(2, 1))
	query.waypoint_spacing = 64.0

	_assert_equal(1, queue.process_budget(1), "long query result request should process by budget")
	var result := queue.take_long_path_result(ticket)
	_assert_true(result != null, "long query result should be takeable as metadata result")
	_assert_equal_str(SimNavLongPathResult.STATUS_SUCCESS, result.status, "queued long query should expose status")
	_assert_equal_str("ground", result.passability_class_name, "queued long query should clone class name")
	_assert_equal(8, int(result.waypoint_spacing), "queued long query should clone spacing preference")
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(6, 1)), result.path.waypoints[0], "queued long query should clone goal at enqueue time")
	_assert_true(result.refined_waypoint_count > 1, "queued max-spacing result should expose refined waypoint count")
	_assert_true(result.path_length > 0.0, "queued result should expose path length")


func _test_worker_batch_collects_results_and_filters_cancelled_ticket() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var ticket_a := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))), pass_mask)
	var ticket_b := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(5, 1))), pass_mask)

	_assert_equal(2, queue.start_worker(), "worker should take all pending requests by default")
	_assert_true(queue.cancel(ticket_a), "cancel should mark in-flight worker ticket stale")
	_assert_equal(1, queue.collect_worker_results(true), "worker collect should skip cancelled ticket")
	_assert_false(queue.has_result(ticket_a), "cancelled in-flight ticket should not produce result")
	_assert_true(queue.has_result(ticket_b), "live in-flight ticket should produce result")
	var path_b := queue.take_result(ticket_b)
	_assert_equal_vec(nav_map.navcell_center_world(Vector2i(5, 1)), path_b.waypoints[0], "worker result should match second queued goal")


func _test_short_result_metadata_and_filter_clone() -> void:
	var fixture := _make_short_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var blocker := SimNavObstructionShapeUnit.new()
	blocker.entity_id = "queued_blocker"
	blocker.center = Vector2(50.0, 50.0)
	blocker.clearance = 12.0
	blocker.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	var blocker_tag := nav_map.add_dynamic_obstruction(blocker)
	var request := SimNavShortPathRequest.new()
	request.start = Vector2(10.0, 50.0)
	request.goal = SimNavPathGoal.point(Vector2(90.0, 50.0))
	request.clearance = 6.0
	request.range_px = 160.0
	request.pass_mask = 1
	var filter := SimNavObstructionFilter.new()
	filter.ignored_tag = blocker_tag
	request.obstruction_filter = filter
	var ticket := queue.enqueue_short_path(request)
	filter.ignored_tag = 0
	_assert_equal(1, queue.process_budget(1), "queued short result should process by budget")
	var result := queue.take_short_path_result(ticket)
	_assert_true(result != null, "queued short result should be takeable as metadata result")
	_assert_equal_str(SimNavShortPathResult.STATUS_DIRECT_GOAL, result.status, "queued short result should expose direct status")
	_assert_equal(blocker_tag, result.obstruction_filter.ignored_tag, "queued short request should clone filter metadata")
	_assert_equal_vec(request.goal.center, result.path.waypoints[0], "queued short metadata path should match goal")


func _test_queue_diagnostics_contract() -> void:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var start := nav_map.navcell_center_world(Vector2i(1, 1))
	var ticket_a := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(4, 1))), pass_mask)
	var ticket_b := queue.enqueue_long_path(start, SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(5, 1))), pass_mask)
	_assert_true(queue.cancel(ticket_b), "diagnostics fixture should cancel pending ticket")
	_assert_equal(1, queue.process_budget(1), "diagnostics fixture should process live ticket")
	_assert_true(queue.has_result(ticket_a), "diagnostics fixture should store live result")
	var diagnostics := queue.get_diagnostics()
	_assert_equal(0, int(diagnostics.get("pending_count", -1)), "diagnostics should expose empty pending count")
	_assert_equal(1, int(diagnostics.get("result_count", 0)), "diagnostics should expose one result")
	_assert_equal(1, int(diagnostics.get("processed_count", 0)), "diagnostics should expose processed count")
	_assert_equal(1, int(diagnostics.get("cancelled_count", 0)), "diagnostics should expose cancelled count")
	var result_tickets: Array = diagnostics.get("result_tickets", [])
	_assert_equal(ticket_a, int(result_tickets[0]), "diagnostics should expose result ticket identity")


func _run_deterministic_queue_once() -> String:
	var fixture := _make_long_fixture()
	var queue: SimNavPathRequestQueue = fixture["queue"]
	var nav_map: SimNavMap = fixture["nav_map"]
	var pass_mask := int(fixture["pass_mask"])
	var ticket := queue.enqueue_long_path(
		nav_map.navcell_center_world(Vector2i(1, 1)),
		SimNavPathGoal.point(nav_map.navcell_center_world(Vector2i(6, 1))),
		pass_mask
	)
	queue.process_budget(1)
	return _path_signature(queue.take_result(ticket))


func _make_long_fixture() -> Dictionary:
	var nav_map := SimNavMap.new(8, 3, 8.0, Vector2.ZERO, 4)
	var pass_mask := _register_ground(nav_map)
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, null, long_pathfinder)
	return {
		"nav_map": nav_map,
		"pass_mask": pass_mask,
		"queue": SimNavPathRequestQueue.new(facade, null),
	}


func _make_short_fixture() -> Dictionary:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 4)
	_register_ground(nav_map)
	return {
		"nav_map": nav_map,
		"queue": SimNavPathRequestQueue.new(null, SimNavVertexPathfinder.new(nav_map)),
	}


func _register_ground(nav_map: SimNavMap) -> int:
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	return nav_map.register_passability_class(ground)


func _path_signature(path: SimNavWaypointPath) -> String:
	var cells: Array[String] = []
	for point in path.waypoints:
		cells.append("%.1f,%.1f" % [point.x, point.y])
	return "|".join(cells)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_null(value: Variant, message: String) -> void:
	if value != null:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_equal_str(expected: String, actual: String, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _assert_equal_vec(expected: Vector2, actual: Vector2, message: String) -> void:
	if expected.distance_to(actual) > 0.01:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
