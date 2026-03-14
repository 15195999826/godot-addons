class_name TestFramework
extends Node

## 轻量级测试框架（兼容 AutoLoad）

# 测试套件
var _suites := {}

# 当前运行状态
var _current_suite_name := ""
var _current_test_name := ""
var _assertion_count := 0
var _test_count := 0
var _pass_count := 0
var _fail_count := 0
var _failures := []

# 生命周期回调
var _before_each_callbacks: Array[Callable] = []
var _after_each_callbacks: Array[Callable] = []

## 测试套件定义

static func describe(suite_name: String, test_block: Callable) -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance:
		push_error("[TestFramework] No instance available")
		return
	instance._current_suite_name = suite_name
	instance._suites[suite_name] = {
		"tests": [],
		"beforeEach": [],
		"afterEach": [],
	}
	test_block.call()
	instance._current_suite_name = ""

## 测试用例定义

static func it(test_name: String, test_fn: Callable) -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance or instance._current_suite_name.is_empty():
		push_error("[TestFramework] it() must be called inside describe()")
		return

	var suite: Dictionary = instance._suites[instance._current_suite_name]
	suite["tests"].append({
		"name": test_name,
		"fn": test_fn,
	})

## 生命周期钩子

static func before_each(callback: Callable) -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance or instance._current_suite_name.is_empty():
		push_error("[TestFramework] before_each() must be called inside describe()")
		return

	var suite: Dictionary = instance._suites[instance._current_suite_name]
	suite["beforeEach"].append(callback)

static func after_each(callback: Callable) -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance or instance._current_suite_name.is_empty():
		push_error("[TestFramework] after_each() must be called inside describe()")
		return

	var suite: Dictionary = instance._suites[instance._current_suite_name]
	suite["afterEach"].append(callback)

## 断言函数

static func expect(actual: Variant) -> Expectation:
	var instance: TestFramework = TestFramework.get_instance()
	return Expectation.new(actual, instance)

## 框架单例

static func get_instance() -> TestFramework:
	if Engine.has_meta("test_framework_instance"):
		return Engine.get_meta("test_framework_instance")
	return null

## 运行所有测试

func run() -> int:
	_test_count = 0
	_pass_count = 0
	_fail_count = 0
	_failures.clear()

	print("\n" + "=".repeat(60))
	print("运行测试套件")
	print("=".repeat(60) + "\n")

	for suite_name: String in _suites:
		_run_suite(suite_name)

	# 打印总结
	_print_summary()

	return _fail_count

func _run_suite(suite_name: String) -> void:
	var suite: Dictionary = _suites[suite_name]
	var tests: Array[Dictionary] = suite["tests"] as Array[Dictionary]
	var before_each_list: Array[Callable] = suite["beforeEach"] as Array[Callable]
	var after_each_list: Array[Callable] = suite["afterEach"] as Array[Callable]

	print("📦 %s" % suite_name)
	print("-".repeat(60))

	_current_suite_name = suite_name
	_before_each_callbacks.clear()
	for callback: Callable in before_each_list:
		_before_each_callbacks.append(callback)
	_after_each_callbacks.clear()
	for callback: Callable in after_each_list:
		_after_each_callbacks.append(callback)

	for test_data: Dictionary in tests:
		_run_test(suite_name, test_data)

	print("")

func _run_test(suite_name: String, test_data: Dictionary) -> void:
	var test_name: String = test_data["name"]
	var test_fn: Callable = test_data["fn"]

	_current_test_name = test_name
	_assertion_count = 0

	# 运行 before_each
	for before_callback in _before_each_callbacks:
		before_callback.call()

	# 运行测试
	test_fn.call()

	# 运行 after_each
	for after_callback in _after_each_callbacks:
		after_callback.call()

	_test_count += 1

	# 检查断言数
	if _assertion_count == 0:
		_fail_count += 1
		_failures.append({
			"suite": suite_name,
			"test": test_name,
			"message": "No assertions made",
		})
		print("  ❌ %s (No assertions)" % test_name)
	else:
		_pass_count += 1
		print("  ✅ %s (%d assertions)" % [test_name, _assertion_count])

func _print_summary() -> void:
	print("=".repeat(60))
	print("测试完成")
	print("  总计: %d  |  通过: %d  |  失败: %d" % [_test_count, _pass_count, _fail_count])

	if _fail_count > 0:
		print("\n失败的测试:")
		for failure: Dictionary in _failures:
			print("  - %s / %s: %s" % [failure.suite, failure.test, failure.message])

	print("=".repeat(60) + "\n")

## 注册断言（由 Expectation 调用）

func register_assertion() -> void:
	_assertion_count += 1

func register_failure(message: String) -> void:
	_fail_count += 1
	_pass_count -= 1
	_failures.append({
		"suite": _current_suite_name,
		"test": _current_test_name,
		"message": message,
	})

func _enter_tree() -> void:
	Engine.set_meta("test_framework_instance", self)

## 工具函数 - 兼容旧式测试注册

static func register_test(name: String, callback: Callable) -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance:
		return

	if not instance._suites.has("LegacyTests"):
		instance._suites["LegacyTests"] = {
			"tests": [],
			"beforeEach": [],
			"afterEach": [],
		}
	instance._suites["LegacyTests"]["tests"].append({
		"name": name,
		"fn": callback,
	})

static func assert_equal(expected: Variant, actual: Variant) -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance:
		return
	instance.register_assertion()
	if expected != actual:
		instance.register_failure("Expected %s but got %s" % [str(expected), str(actual)])

static func assert_true(value: bool, message: String = "") -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance:
		return
	instance.register_assertion()
	if not value:
		var msg := message if not message.is_empty() else "Expected true but got false"
		instance.register_failure(msg)

static func assert_false(value: bool, message: String = "") -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance:
		return
	instance.register_assertion()
	if value:
		var msg := message if not message.is_empty() else "Expected false but got true"
		instance.register_failure(msg)

static func assert_near(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	var instance: TestFramework = TestFramework.get_instance()
	if not instance:
		return
	instance.register_assertion()
	if abs(actual - expected) > tolerance:
		var msg := message if not message.is_empty() else "Expected %s to be close to %s (±%s)" % [str(actual), str(expected), str(tolerance)]
		instance.register_failure(msg)

## 断言类

class Expectation extends RefCounted:
	var _actual: Variant
	var _negated := false
	var _framework: TestFramework

	func _init(actual: Variant, framework: TestFramework) -> void:
		_actual = actual
		_framework = framework

	func not_() -> Expectation:
		_negated = not _negated
		return self

	func to_be(expected: Variant) -> void:
		var passed: bool = _actual == expected
		if _negated:
			passed = not passed

		if _framework:
			_framework.register_assertion()

		if not passed:
			var message := "Expected %s to%s be %s, got %s" % [
				_value_to_string(_actual),
				" not" if _negated else "",
				_value_to_string(expected),
				_value_to_string(_actual),
			]
			if _framework:
				_framework.register_failure(message)

	func to_equal(expected: Variant) -> void:
		to_be(expected)

	func to_be_true() -> void:
		to_be(true)

	func to_be_false() -> void:
		to_be(false)

	func to_be_null() -> void:
		to_be(null)

	func to_be_greater_than(expected: float) -> void:
		var passed := float(_actual) > float(expected)
		if _negated:
			passed = not passed

		if _framework:
			_framework.register_assertion()

		if not passed:
			var message := "Expected %s to%s be greater than %s" % [
				_value_to_string(_actual),
				" not" if _negated else "",
				_value_to_string(expected),
			]
			if _framework:
				_framework.register_failure(message)

	func to_be_less_than(expected: float) -> void:
		var passed := float(_actual) < float(expected)
		if _negated:
			passed = not passed

		if _framework:
			_framework.register_assertion()

		if not passed:
			var message := "Expected %s to%s be less than %s" % [
				_value_to_string(_actual),
				" not" if _negated else "",
				_value_to_string(expected),
			]
			if _framework:
				_framework.register_failure(message)

	func to_be_close_to(expected: float, tolerance: float = 0.0001) -> void:
		var actual_val := float(_actual)
		var passed: bool = abs(actual_val - expected) <= tolerance
		if _negated:
			passed = not passed

		if _framework:
			_framework.register_assertion()

		if not passed:
			var message := "Expected %s to%s be close to %s (±%s)" % [
				_value_to_string(_actual),
				" not" if _negated else "",
				_value_to_string(expected),
				tolerance,
			]
			if _framework:
				_framework.register_failure(message)

	func to_have_length(expected: int) -> void:
		var actual_length := 0
		if _actual is Array:
			actual_length = _actual.size()
		elif _actual is Dictionary:
			actual_length = _actual.size()
		elif _actual is String:
			actual_length = _actual.length()

		var passed := actual_length == expected
		if _negated:
			passed = not passed

		if _framework:
			_framework.register_assertion()

		if not passed:
			var message := "Expected length %s to%s be %s" % [
				actual_length,
				" not" if _negated else "",
				expected,
			]
			if _framework:
				_framework.register_failure(message)

	func to_contain(item: Variant) -> void:
		var passed := false

		if _actual is Array:
			passed = item in _actual
		elif _actual is Dictionary:
			passed = item in _actual
		elif _actual is String:
			passed = str(item) in _actual

		if _negated:
			passed = not passed

		if _framework:
			_framework.register_assertion()

		if not passed:
			var message := "Expected %s to%s contain %s" % [
				_value_to_string(_actual),
				" not" if _negated else "",
				_value_to_string(item),
			]
			if _framework:
				_framework.register_failure(message)

	func _value_to_string(value: Variant) -> String:
		if value == null:
			return "null"
		elif value is String:
			return '"%s"' % value
		elif value is float or value is int:
			return str(value)
		elif value is bool:
			return "true" if value else "false"
		elif value is Array or value is Dictionary:
			return JSON.stringify(value)
		elif value is Object:
			return "<Object:%s>" % value.get_class()
		else:
			return str(value)
