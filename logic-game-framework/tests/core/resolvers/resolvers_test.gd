extends Node

## Resolvers 单元测试

func _init() -> void:
	# FloatResolver 测试
	TestFramework.register_test("FloatResolver - should resolve fixed value", _test_float_val)
	TestFramework.register_test("FloatResolver - should resolve dynamic value", _test_float_fn)
	
	# IntResolver 测试
	TestFramework.register_test("IntResolver - should resolve fixed value", _test_int_val)
	TestFramework.register_test("IntResolver - should resolve dynamic value", _test_int_fn)
	
	# StringResolver 测试
	TestFramework.register_test("StringResolver - should resolve fixed value", _test_str_val)
	TestFramework.register_test("StringResolver - should resolve dynamic value", _test_str_fn)
	
	# DictResolver 测试
	TestFramework.register_test("DictResolver - should resolve fixed value", _test_dict_val)
	TestFramework.register_test("DictResolver - should resolve dynamic value", _test_dict_fn)
	
	# Vector3Resolver 测试
	TestFramework.register_test("Vector3Resolver - should resolve fixed value", _test_vec3_val)
	TestFramework.register_test("Vector3Resolver - should resolve dynamic value", _test_vec3_fn)
	
	# 默认参数测试
	TestFramework.register_test("Resolvers - should work as default parameter", _test_default_param)


# ============================================================
# 测试辅助
# ============================================================

func _create_mock_context(event: Dictionary = {}) -> ExecutionContext:
	var event_dict_chain: Array[Dictionary] = []
	if not event.is_empty():
		event_dict_chain = [event]
	return ExecutionContext.new(event_dict_chain, null, null, null, null)


# ============================================================
# FloatResolver 测试
# ============================================================

func _test_float_val() -> void:
	var resolver := Resolvers.float_val(42.5)
	var ctx := _create_mock_context()
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_near(42.5, result, 0.001, "FloatResolver should return fixed value")


func _test_float_fn() -> void:
	var resolver := Resolvers.float_fn(func(exec_ctx: ExecutionContext) -> float:
		var event := exec_ctx.get_current_event()
		return event.get("power", 0.0) as float
	)
	var ctx := _create_mock_context({ "power": 100.0 })
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_near(100.0, result, 0.001, "FloatResolver should return dynamic value from event")


# ============================================================
# IntResolver 测试
# ============================================================

func _test_int_val() -> void:
	var resolver := Resolvers.int_val(5)
	var ctx := _create_mock_context()
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_equal(5, result)


func _test_int_fn() -> void:
	var resolver := Resolvers.int_fn(func(exec_ctx: ExecutionContext) -> int:
		var event := exec_ctx.get_current_event()
		return event.get("stacks", 0) as int
	)
	var ctx := _create_mock_context({ "stacks": 3 })
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_equal(3, result)


# ============================================================
# StringResolver 测试
# ============================================================

func _test_str_val() -> void:
	var resolver := Resolvers.str_val("attack_slash")
	var ctx := _create_mock_context()
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_equal("attack_slash", result)


func _test_str_fn() -> void:
	var resolver := Resolvers.str_fn(func(exec_ctx: ExecutionContext) -> String:
		var event := exec_ctx.get_current_event()
		return event.get("cue_id", "") as String
	)
	var ctx := _create_mock_context({ "cue_id": "skill_fireball" })
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_equal("skill_fireball", result)


# ============================================================
# DictResolver 测试
# ============================================================

func _test_dict_val() -> void:
	var resolver := Resolvers.dict_val({ "intensity": 1.5, "color": "red" })
	var ctx := _create_mock_context()
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_equal(1.5, result.get("intensity"))
	TestFramework.assert_equal("red", result.get("color"))


func _test_dict_fn() -> void:
	var resolver := Resolvers.dict_fn(func(exec_ctx: ExecutionContext) -> Dictionary:
		var event := exec_ctx.get_current_event()
		return event.get("params", {}) as Dictionary
	)
	var ctx := _create_mock_context({ "params": { "element": "fire" } })
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_equal("fire", result.get("element"))


# ============================================================
# Vector3Resolver 测试
# ============================================================

func _test_vec3_val() -> void:
	var resolver := Resolvers.vec3_val(Vector3(100, 200, 0))
	var ctx := _create_mock_context()
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_near(100.0, result.x, 0.001, "Vector3Resolver should return correct x")
	TestFramework.assert_near(200.0, result.y, 0.001, "Vector3Resolver should return correct y")
	TestFramework.assert_near(0.0, result.z, 0.001, "Vector3Resolver should return correct z")


func _test_vec3_fn() -> void:
	var resolver := Resolvers.vec3_fn(func(exec_ctx: ExecutionContext) -> Vector3:
		var event := exec_ctx.get_current_event()
		return event.get("position", Vector3.ZERO) as Vector3
	)
	var ctx := _create_mock_context({ "position": Vector3(50, 75, 10) })
	
	var result := resolver.resolve(ctx)
	
	TestFramework.assert_near(50.0, result.x, 0.001, "Vector3Resolver should return dynamic x from event")
	TestFramework.assert_near(75.0, result.y, 0.001, "Vector3Resolver should return dynamic y from event")
	TestFramework.assert_near(10.0, result.z, 0.001, "Vector3Resolver should return dynamic z from event")


# ============================================================
# 默认参数测试
# ============================================================

## 模拟一个使用 Resolver 作为默认参数的函数
func _example_action_with_default(
	damage: FloatResolver,
	duration: FloatResolver = Resolvers.float_val(-1.0)
) -> Dictionary:
	var ctx := _create_mock_context()
	return {
		"damage": damage.resolve(ctx),
		"duration": duration.resolve(ctx),
	}


func _test_default_param() -> void:
	# 测试不传可选参数（使用默认值）
	var result1 := _example_action_with_default(Resolvers.float_val(50.0))
	TestFramework.assert_near(50.0, result1.damage, 0.001, "Should use provided damage value")
	TestFramework.assert_near(-1.0, result1.duration, 0.001, "Should use default duration value (-1)")
	
	# 测试传入可选参数
	var result2 := _example_action_with_default(
		Resolvers.float_val(100.0),
		Resolvers.float_val(5000.0)
	)
	TestFramework.assert_near(100.0, result2.damage, 0.001, "Should use provided damage value")
	TestFramework.assert_near(5000.0, result2.duration, 0.001, "Should use provided duration value")
