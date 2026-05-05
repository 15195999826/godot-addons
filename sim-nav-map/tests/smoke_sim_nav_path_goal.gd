extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map path goal geometry")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	_test_circle_navcell_membership_and_distance()
	_test_inverted_circle_membership()
	_test_rotated_square_nearest_point()


func _test_circle_navcell_membership_and_distance() -> void:
	var nav_map := SimNavMap.new(10, 10, 8.0, Vector2.ZERO, 4)
	var goal := SimNavPathGoal.circle(nav_map.navcell_center_world(Vector2i(5, 5)), 10.0)
	_assert_true(goal.navcell_contains_goal(nav_map, Vector2i(5, 5)), "circle should contain its center navcell")
	_assert_true(goal.navcell_contains_goal(nav_map, Vector2i(4, 5)), "circle should contain intersecting neighbor navcell")
	_assert_false(goal.navcell_contains_goal(nav_map, Vector2i(2, 5)), "circle should reject far navcell")
	_assert_float(0.0, goal.distance_to_point(nav_map.navcell_center_world(Vector2i(5, 5))), "circle center distance")


func _test_inverted_circle_membership() -> void:
	var nav_map := SimNavMap.new(10, 10, 8.0, Vector2.ZERO, 4)
	var center := nav_map.navcell_center_world(Vector2i(5, 5))
	var goal := SimNavPathGoal.inverted_circle(center, 16.0)
	_assert_false(goal.navcell_contains_goal(nav_map, Vector2i(5, 5)), "inverted circle should reject navcell fully inside circle")
	_assert_true(goal.navcell_contains_goal(nav_map, Vector2i(0, 0)), "inverted circle should contain far outside navcell")
	_assert_float(16.0, goal.distance_to_point(center), "inverted circle center distance")


func _test_rotated_square_nearest_point() -> void:
	var goal := SimNavPathGoal.square(Vector2(40.0, 40.0), 10.0, 6.0, PI * 0.25)
	_assert_true(goal.contains_point(Vector2(40.0, 40.0)), "rotated square should contain center")
	_assert_false(goal.contains_point(Vector2(70.0, 40.0)), "rotated square should reject far point")
	var nearest := goal.nearest_point_on_goal(Vector2(70.0, 40.0))
	_assert_true(goal.contains_point(nearest), "nearest square point should be inside square")
	_assert_true(nearest.distance_to(Vector2(70.0, 40.0)) < 25.0, "nearest square point should be closer than center")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)


func _assert_float(expected: float, actual: float, message: String) -> void:
	if absf(expected - actual) > 0.01:
		_failures.append("%s (expected=%.2f actual=%.2f)" % [message, expected, actual])
