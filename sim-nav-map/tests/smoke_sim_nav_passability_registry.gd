extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map passability registry")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var registry := SimNavPassabilityClassRegistry.new()
	var infantry := _class_config("infantry", 8.0, true)
	var air := _class_config("air", 0.0, false)

	var infantry_mask := registry.register(infantry)
	var air_mask := registry.register(air)

	_assert_equal(1, infantry_mask, "first passability class should use bit 0")
	_assert_equal(2, air_mask, "second passability class should use bit 1")
	_assert_equal(0, infantry.bit_index, "registry should assign first bit index")
	_assert_equal(1, air.bit_index, "registry should assign second bit index")
	_assert_equal(infantry_mask, registry.get_mask("infantry"), "get_mask should return registered mask")
	_assert_equal(air_mask, registry.get_mask("air"), "get_mask should return second registered mask")
	_assert_true(registry.get_pass_class("infantry") == infantry, "get_pass_class should return config reference")
	_assert_true(registry.get_class_by_mask(air_mask) == air, "get_class_by_mask should resolve config")
	_assert_equal(2, registry.size(), "registry size should track classes")
	_assert_float(8.0, registry.max_clearance(), "max_clearance should ignore lower classes")

	var nav_map := SimNavMap.new(4, 4, 8.0, Vector2.ZERO, 1)
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 4.0, true))
	var flyer_mask := nav_map.register_passability_class(_class_config("flyer", 0.0, false))
	_assert_equal(ground_mask, nav_map.get_passability_mask("ground"), "map should expose registry mask")
	_assert_equal(flyer_mask, nav_map.get_passability_registry().get_mask("flyer"), "map registry should expose masks")
	_assert_equal(2, nav_map.get_passability_classes().size(), "map should expose registered class list")


func _class_config(name_id: String, clearance: float, affects_pathfinding: bool) -> SimNavPassabilityClassConfig:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = name_id
	config.clearance = clearance
	config.affects_pathfinding = affects_pathfinding
	return config


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_equal(expected: int, actual: int, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%d actual=%d)" % [message, expected, actual])


func _assert_float(expected: float, actual: float, message: String) -> void:
	if absf(expected - actual) > 0.001:
		_failures.append("%s (expected=%.3f actual=%.3f)" % [message, expected, actual])
