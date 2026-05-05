extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map spatial index")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var index := SimNavSpatialIndex.new(10.0)
	index.add(3, Vector2(0.0, 0.0), Vector2(5.0, 5.0))
	index.add(1, Vector2(12.0, 0.0), Vector2(16.0, 4.0))
	index.add(2, Vector2(40.0, 0.0), Vector2(45.0, 5.0))

	_assert_tags([1, 3], index.query(Vector2(-1.0, -1.0), Vector2(20.0, 10.0)), "query should return sorted intersecting tags")
	_assert_true(index.move(2, Vector2(18.0, 0.0), Vector2(25.0, 5.0)), "move should update existing tag")
	_assert_tags([1, 2, 3], index.query(Vector2(-1.0, -1.0), Vector2(26.0, 10.0)), "query should include moved tag")
	_assert_true(index.remove(1), "remove should delete existing tag")
	_assert_false(index.remove(1), "remove should be idempotent for missing tag")
	_assert_tags([2, 3], index.query(Vector2(-1.0, -1.0), Vector2(26.0, 10.0)), "query should not include removed tag")


func _assert_tags(expected: Array[int], actual: Array[int], message: String) -> void:
	if expected.size() != actual.size():
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
		return
	for i in range(expected.size()):
		if expected[i] != actual[i]:
			_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
			return


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append(message)
