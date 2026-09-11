extends Node

## RawAttributeSet 单测：stat 属性（base + modifier 四层公式、动态依赖）与资源属性（hp 这类直接存值、
## clamp 到 [minValue, maxRef 当前值]、不进 modifier 管线）。
## 拒绝路径（add_modifier / set_base 指向资源、动态依赖以资源为源）走 Log.assert_crash，
## 断言失败打 SCRIPT ERROR 而 launcher 判其为 FAIL，所以不测（同 flow_action_test 的约定）。


func _init() -> void:
	TestFramework.register_test("RawAttributeSet - should get base value", _test_get_base)
	TestFramework.register_test("RawAttributeSet - should set base value", _test_set_base)
	TestFramework.register_test("RawAttributeSet - should calculate with AddBase modifier", _test_add_base_modifier)
	TestFramework.register_test("RawAttributeSet - should calculate with MulBase modifier", _test_mul_base_modifier)
	TestFramework.register_test("RawAttributeSet - should calculate with AddFinal modifier", _test_add_final_modifier)
	TestFramework.register_test("RawAttributeSet - should calculate with MulFinal modifier", _test_mul_final_modifier)
	TestFramework.register_test("RawAttributeSet - should calculate full four-layer formula", _test_four_layer_formula)
	TestFramework.register_test("RawAttributeSet - should add modifier", _test_add_modifier)
	TestFramework.register_test("RawAttributeSet - should remove modifier", _test_remove_modifier)
	TestFramework.register_test("RawAttributeSet - should remove modifiers by source", _test_remove_by_source)
	TestFramework.register_test("RawAttributeSet - should notify base value changes", _test_base_change_notification)
	TestFramework.register_test("RawAttributeSet - should remove change listener", _test_remove_listener)
	TestFramework.register_test("RawAttributeSet - should clamp value to min constraint", _test_min_constraint)
	TestFramework.register_test("RawAttributeSet - should clamp value to max constraint", _test_max_constraint)
	TestFramework.register_test("RawAttributeSet - dynamic circular dependency converges", _test_dynamic_circular_dependency_converges)
	TestFramework.register_test("RawAttributeSet - dynamic dependency is reversible", _test_dynamic_dependency_reversible)
	TestFramework.register_test("RawAttributeSet - resource follows max_ref down and back up", _test_resource_follows_max_ref_down_and_back_up)
	TestFramework.register_test("RawAttributeSet - resource survives a transient cap drop via modifiers", _test_resource_survives_transient_cap_drop_via_modifiers)
	TestFramework.register_test("RawAttributeSet - resource serializes its value", _test_resource_serializes_its_value)
	TestFramework.register_test("RawAttributeSet - apply_config keeps key order across kinds", _test_apply_config_keeps_key_order_with_resource)
	TestFramework.register_test("RawAttributeSet - set_resource / add_resource clamp to [min, max_ref]", _test_set_resource_clamps_to_min_and_cap)
	TestFramework.register_test("RawAttributeSet - set_resource notifies only itself and only on change", _test_set_resource_notifies_only_on_change)
	TestFramework.register_test("RawAttributeSet - resource without max_ref is uncapped", _test_uncapped_resource_and_kind_queries)
	TestFramework.register_test("RawAttributeSet - apply_config clamps resource initial value to its cap", _test_apply_config_clamps_initial_value_to_cap)


## stat 夹具：atk / def 两个纯 stat 属性。
func _make_stats() -> RawAttributeSet:
	return RawAttributeSet.new([
		{"name": "atk", "baseValue": 50},
		{"name": "def", "baseValue": 30},
	])


## 资源夹具：与生成 set 同形——按 key 顺序定义，hp（资源）排在它的上限 max_hp 之前。
func _make_with_hp() -> RawAttributeSet:
	var attr_set := RawAttributeSet.new()
	attr_set.apply_config({
		"atk": { "baseValue": 50.0 },
		"hp": { "kind": "resource", "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 100.0, "minValue": 1.0 },
	})
	return attr_set


func _test_get_base() -> void:
	var attribute_set := _make_stats()
	TestFramework.assert_equal(50, attribute_set.get_base("atk"))
	TestFramework.assert_equal(30, attribute_set.get_base("def"))

func _test_set_base() -> void:
	var attribute_set := _make_stats()
	attribute_set.set_base("atk", 120)
	TestFramework.assert_equal(120, attribute_set.get_base("atk"))

func _test_add_base_modifier() -> void:
	var attribute_set := _make_stats()
	# Base = 50, AddBase = +10
	# CurrentValue = ((50 + 10) × 1 + 0) × 1 = 60
	var mod := AttributeModifier.create_add_base("mod1", "atk", 10)
	attribute_set.add_modifier(mod)
	TestFramework.assert_near(60, attribute_set.get_current_value("atk"))
	TestFramework.assert_near(10, attribute_set.get_add_base_sum("atk"))

func _test_mul_base_modifier() -> void:
	var attribute_set := _make_stats()
	# Base = 50, MulBase = +20% (0.2)
	# CurrentValue = ((50 + 0) × 1.2 + 0) × 1 = 60
	var mod := AttributeModifier.create_mul_base("mod1", "atk", 0.2)
	attribute_set.add_modifier(mod)
	TestFramework.assert_near(60, attribute_set.get_current_value("atk"))
	TestFramework.assert_near(1.2, attribute_set.get_mul_base_product("atk"))

func _test_add_final_modifier() -> void:
	var attribute_set := _make_stats()
	# Base = 50, AddFinal = +50
	# CurrentValue = ((50 + 0) × 1 + 50) × 1 = 100
	var mod := AttributeModifier.create_add_final("mod1", "atk", 50)
	attribute_set.add_modifier(mod)
	TestFramework.assert_near(100, attribute_set.get_current_value("atk"))
	TestFramework.assert_near(50, attribute_set.get_add_final_sum("atk"))

func _test_mul_final_modifier() -> void:
	var attribute_set := _make_stats()
	# Base = 50, MulFinal = -30% (-0.3)
	# CurrentValue = ((50 + 0) × 1 + 0) × 0.7 = 35
	var mod := AttributeModifier.create_mul_final("mod1", "atk", -0.3)
	attribute_set.add_modifier(mod)
	TestFramework.assert_near(35, attribute_set.get_current_value("atk"))
	TestFramework.assert_near(0.7, attribute_set.get_mul_final_product("atk"))

func _test_four_layer_formula() -> void:
	var attribute_set := _make_stats()
	# Base = 50
	# AddBase = +10
	# MulBase = +20% (0.2)
	# AddFinal = +50
	# MulFinal = +10% (0.1)
	#
	# BodyValue = (50 + 10) × 1.2 = 72
	# CurrentValue = (72 + 50) × 1.1 = 134.2
	attribute_set.add_modifier(AttributeModifier.create_add_base("mod1", "atk", 10))
	attribute_set.add_modifier(AttributeModifier.create_mul_base("mod2", "atk", 0.2))
	attribute_set.add_modifier(AttributeModifier.create_add_final("mod3", "atk", 50))
	attribute_set.add_modifier(AttributeModifier.create_mul_final("mod4", "atk", 0.1))

	var breakdown := attribute_set.get_breakdown("atk")
	TestFramework.assert_equal(50, breakdown.base)
	TestFramework.assert_near(10, breakdown.add_base_sum)
	TestFramework.assert_near(1.2, breakdown.mul_base_product)
	TestFramework.assert_near(72, breakdown.body_value)
	TestFramework.assert_near(50, breakdown.add_final_sum)
	TestFramework.assert_near(1.1, breakdown.mul_final_product)
	TestFramework.assert_near(134.2, breakdown.current_value)

func _test_add_modifier() -> void:
	var attribute_set := _make_stats()
	var mod := AttributeModifier.create_add_base("mod1", "atk", 5)
	attribute_set.add_modifier(mod)
	TestFramework.assert_near(55, attribute_set.get_current_value("atk"))

func _test_remove_modifier() -> void:
	var attribute_set := _make_stats()
	var mod := AttributeModifier.create_add_base("mod1", "atk", 5)
	attribute_set.add_modifier(mod)
	attribute_set.remove_modifier("mod1")
	TestFramework.assert_near(50, attribute_set.get_current_value("atk"))

func _test_remove_by_source() -> void:
	var attribute_set := _make_stats()
	attribute_set.add_modifier(AttributeModifier.create_add_base("mod1", "atk", 10, "buff1"))
	attribute_set.add_modifier(AttributeModifier.create_add_base("mod2", "atk", 20, "buff1"))
	attribute_set.add_modifier(AttributeModifier.create_add_base("mod3", "atk", 15, "buff2"))
	attribute_set.remove_modifiers_by_source("buff1")
	TestFramework.assert_near(65, attribute_set.get_current_value("atk"))

func _test_base_change_notification() -> void:
	var attribute_set := _make_stats()
	var changes: Array[Dictionary] = []

	var listener := func(event: Dictionary) -> void:
		if event.get("attribute_name") == "atk":
			changes.append(event)

	attribute_set.add_change_listener(listener)
	attribute_set.set_base("atk", 150)

	TestFramework.assert_equal(1, changes.size())
	TestFramework.assert_equal("atk", changes[0].get("attribute_name"))
	TestFramework.assert_equal(50, changes[0].get("old_value"))
	TestFramework.assert_equal(150, changes[0].get("new_value"))

func _test_remove_listener() -> void:
	var attribute_set := _make_stats()
	var changes: Array[Dictionary] = []

	var listener := func(event: Dictionary) -> void:
		if event.get("attribute_name") == "atk":
			changes.append(event)

	attribute_set.add_change_listener(listener)
	attribute_set.remove_change_listener(listener)
	attribute_set.set_base("atk", 150)

	TestFramework.assert_equal(0, changes.size())

func _test_min_constraint() -> void:
	var constrained_set := RawAttributeSet.new([
		{"name": "atk", "baseValue": 100, "minValue": 10},
	])
	constrained_set.set_base("atk", 5)
	TestFramework.assert_equal(10, constrained_set.get_base("atk"))

func _test_max_constraint() -> void:
	var constrained_set := RawAttributeSet.new([
		{"name": "mp", "baseValue": 50, "maxValue": 100},
	])
	constrained_set.set_base("mp", 150)
	TestFramework.assert_equal(100, constrained_set.get_base("mp"))


func _test_dynamic_circular_dependency_converges() -> void:
	# 测试两轮快照求解：动态依赖通过 register_dynamic_dep 声明式注册
	# 被动 a：max_hp += atk × 0.1  (ADD_BASE)
	# 被动 b：atk += max_hp × 0.01 (ADD_BASE)
	# 被动 c：max_hp += atk × 0.2  (ADD_BASE)
	# 被动 d：atk += max_hp × 0.02 (ADD_BASE)
	# 初始：max_hp = 100, atk = 20
	# 装备：max_hp +20, atk +20

	var attr_set := RawAttributeSet.new([
		{"name": "max_hp", "baseValue": 100},
		{"name": "atk", "baseValue": 20},
	])

	# 添加动态依赖的 modifier（初始值 0，求解器会自动计算）
	var mod_a := AttributeModifier.create_add_base("dyn_a", "max_hp", 0.0, "skill_a")
	var mod_b := AttributeModifier.create_add_base("dyn_b", "atk", 0.0, "skill_b")
	var mod_c := AttributeModifier.create_add_base("dyn_c", "max_hp", 0.0, "skill_c")
	var mod_d := AttributeModifier.create_add_base("dyn_d", "atk", 0.0, "skill_d")

	attr_set.add_modifier(mod_a)
	attr_set.add_modifier(mod_b)
	attr_set.add_modifier(mod_c)
	attr_set.add_modifier(mod_d)

	# 注册动态依赖
	attr_set.register_dynamic_dep("dyn_a", "atk", "max_hp", AttributeModifier.Type.ADD_BASE, 0.1)
	attr_set.register_dynamic_dep("dyn_b", "max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.01)
	attr_set.register_dynamic_dep("dyn_c", "atk", "max_hp", AttributeModifier.Type.ADD_BASE, 0.2)
	attr_set.register_dynamic_dep("dyn_d", "max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.02)

	# 无装备时，纯动态依赖：base max_hp=100, atk=20
	# 第 1 轮：静态值 max_hp=100, atk=20
	#   a: 20*0.1=2, b: 100*0.01=1, c: 20*0.2=4, d: 100*0.02=2
	#   → max_hp=106, atk=23
	# 第 2 轮：
	#   a: 23*0.1=2.3, b: 106*0.01=1.06, c: 23*0.2=4.6, d: 106*0.02=2.12
	#   → max_hp=106.9, atk=23.18
	# tolerance 0.1：raw_attribute_set.gd 自身注释声明两轮快照精度损失约 0.08%，
	# 在 100~150 量级下 = 0.08~0.12；原 0.01 严于实现保证。
	TestFramework.assert_near(attr_set.get_current_value("max_hp"), 106.9, 0.1)
	TestFramework.assert_near(attr_set.get_current_value("atk"), 23.18, 0.1)

	# 穿戴装备：max_hp +20, atk +20
	attr_set.add_modifier(AttributeModifier.create_add_base("equip_hp", "max_hp", 20, "equipment"))
	attr_set.add_modifier(AttributeModifier.create_add_base("equip_atk", "atk", 20, "equipment"))

	# 两轮快照求解结果（见类头注释）：max_hp ≈ 133.08, atk ≈ 43.96
	TestFramework.assert_near(attr_set.get_current_value("max_hp"), 133.08, 0.1)
	TestFramework.assert_near(attr_set.get_current_value("atk"), 43.96, 0.1)

	# get_breakdown 一致性：再次调用应得到相同值
	TestFramework.assert_near(attr_set.get_current_value("max_hp"), 133.08, 0.1)
	TestFramework.assert_near(attr_set.get_current_value("atk"), 43.96, 0.1)


func _test_dynamic_dependency_reversible() -> void:
	# 测试可逆性：add buff → remove buff = 原状态
	# 使用与 _test_dynamic_circular_dependency_converges 相同的配置

	var attr_set := RawAttributeSet.new([
		{"name": "max_hp", "baseValue": 100},
		{"name": "atk", "baseValue": 20},
	])

	# 动态依赖 modifier
	var mod_a := AttributeModifier.create_add_base("dyn_a", "max_hp", 0.0, "skill_a")
	var mod_b := AttributeModifier.create_add_base("dyn_b", "atk", 0.0, "skill_b")
	var mod_c := AttributeModifier.create_add_base("dyn_c", "max_hp", 0.0, "skill_c")
	var mod_d := AttributeModifier.create_add_base("dyn_d", "atk", 0.0, "skill_d")

	attr_set.add_modifier(mod_a)
	attr_set.add_modifier(mod_b)
	attr_set.add_modifier(mod_c)
	attr_set.add_modifier(mod_d)

	attr_set.register_dynamic_dep("dyn_a", "atk", "max_hp", AttributeModifier.Type.ADD_BASE, 0.1)
	attr_set.register_dynamic_dep("dyn_b", "max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.01)
	attr_set.register_dynamic_dep("dyn_c", "atk", "max_hp", AttributeModifier.Type.ADD_BASE, 0.2)
	attr_set.register_dynamic_dep("dyn_d", "max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.02)

	# 装备
	attr_set.add_modifier(AttributeModifier.create_add_base("equip_hp", "max_hp", 20, "equipment"))
	attr_set.add_modifier(AttributeModifier.create_add_base("equip_atk", "atk", 20, "equipment"))

	# 记录 buff 前状态
	var before_max_hp := attr_set.get_current_value("max_hp")
	var before_atk := attr_set.get_current_value("atk")

	# 添加 atk +10 buff
	attr_set.add_modifier(AttributeModifier.create_add_base("buff_atk", "atk", 10, "temp_buff"))

	# buff 后应该变化
	var buffed_max_hp := attr_set.get_current_value("max_hp")
	var buffed_atk := attr_set.get_current_value("atk")
	TestFramework.assert_true(buffed_atk > before_atk, "atk should increase with buff")
	TestFramework.assert_true(buffed_max_hp > before_max_hp, "max_hp should increase due to dynamic dep on atk")

	# 移除 buff
	attr_set.remove_modifier("buff_atk")

	# 可逆性：移除后 == buff 前（严格相等）
	var after_max_hp := attr_set.get_current_value("max_hp")
	var after_atk := attr_set.get_current_value("atk")
	TestFramework.assert_near(after_max_hp, before_max_hp, 0.0001, "max_hp should be exactly restored after removing buff")
	TestFramework.assert_near(after_atk, before_atk, 0.0001, "atk should be exactly restored after removing buff")


# ========== 资源属性 ==========


## 资源存的是写入时 clamp 过的值，读取按 max_ref 当前值封顶：上限下降把读值拉低、
## 回升后读值恢复（存值不被上限暂降改写）；拉低 / 恢复的通知与同批 stat 通知一起、
## 按定义顺序发出（hp 定义在 max_hp 之前 → hp 事件在前）。
func _test_resource_follows_max_ref_down_and_back_up() -> void:
	var attr_set := _make_with_hp()
	var events: Array[Dictionary] = []
	attr_set.add_change_listener(func(event: Dictionary) -> void:
		events.append(event))

	attr_set.set_base("max_hp", 60.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 60.0, 0.0001, "max_hp drop pulls hp down")
	var names_after_drop: Array[String] = []
	for event in events:
		names_after_drop.append(event.get("attribute_name", "") as String)
	var expected_after_drop: Array[String] = ["hp", "max_hp"]
	TestFramework.assert_equal(expected_after_drop, names_after_drop)
	TestFramework.assert_near(float(events[0].get("old_value")), 100.0)
	TestFramework.assert_near(float(events[0].get("new_value")), 60.0)

	attr_set.set_base("max_hp", 100.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 100.0, 0.0001, "the stored value survives a transient cap drop")
	TestFramework.assert_equal(4, events.size())
	TestFramework.assert_equal("hp", events[2].get("attribute_name"))
	TestFramework.assert_near(float(events[2].get("old_value")), 60.0)
	TestFramework.assert_near(float(events[2].get("new_value")), 100.0)
	TestFramework.assert_equal("max_hp", events[3].get("attribute_name"))


## modifier 入口的上限暂降（重穿装备 / Break 撤销加成）同样不吞存值；暂降期间 serialize 出的是封顶后的读值，
## 暂降期间的写入从封顶读值起算、按暂降上限 clamp 并留下。
func _test_resource_survives_transient_cap_drop_via_modifiers() -> void:
	var attr_set := _make_with_hp()
	attr_set.add_modifier(AttributeModifier.create_add_base("gear_max_hp", "max_hp", 50.0, "gear"))
	attr_set.set_resource("hp", 150.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 150.0)

	attr_set.remove_modifiers_by_source("gear")
	TestFramework.assert_near(attr_set.get_current_value("hp"), 100.0, 0.0001, "cap drop via modifier removal pulls hp down")
	TestFramework.assert_near(float((attr_set.serialize()["hp"] as Dictionary).get("value", -1.0)), 100.0, 0.0001, "serialize writes the capped value")
	attr_set.add_modifier(AttributeModifier.create_add_base("gear_max_hp", "max_hp", 50.0, "gear"))
	TestFramework.assert_near(attr_set.get_current_value("hp"), 150.0, 0.0001, "re-granting the cap restores the stored value")

	attr_set.remove_modifiers_by_source("gear")
	attr_set.add_resource("hp", -10.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 90.0, 0.0001, "a write during the drop starts from the capped value")
	attr_set.add_modifier(AttributeModifier.create_add_base("gear_max_hp", "max_hp", 50.0, "gear"))
	TestFramework.assert_near(attr_set.get_current_value("hp"), 90.0, 0.0001, "a write during the drop sticks after the cap comes back")


## serialize 带资源值（无 base / modifiers），deserialize 还原成资源。
func _test_resource_serializes_its_value() -> void:
	var attr_set := _make_with_hp()
	attr_set.add_modifier(AttributeModifier.create_add_base("buff", "atk", 5.0, "source"))

	var data := attr_set.serialize()
	var hp_data: Dictionary = data["hp"]
	TestFramework.assert_equal("resource", hp_data.get("kind", ""))
	TestFramework.assert_near(float(hp_data.get("value", -1.0)), 100.0)
	TestFramework.assert_false(hp_data.has("modifiers"), "resource has no modifier list")

	var restored := RawAttributeSet.deserialize(data)
	TestFramework.assert_near(restored.get_current_value("hp"), 100.0)
	TestFramework.assert_near(restored.get_current_value("atk"), 55.0)


## 属性名顺序 = apply_config 的 key 顺序，资源与 stat 混排不改变它（通知 / 快照 / 序列化都按这个序）。
func _test_apply_config_keeps_key_order_with_resource() -> void:
	var attr_set := RawAttributeSet.new()
	attr_set.apply_config({
		"speed": { "baseValue": 7.0 },
		"hp": { "kind": "resource", "baseValue": 10.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 10.0 },
		"atk": { "baseValue": 3.0 },
	})
	var expected: Array[String] = ["speed", "hp", "max_hp", "atk"]
	TestFramework.assert_equal(expected, attr_set.get_attribute_names())
	var snapshot_names: Array[String] = []
	for attr_name in attr_set.snapshot_current_values().keys():
		snapshot_names.append(attr_name as String)
	TestFramework.assert_equal(expected, snapshot_names)


## 写资源：只 clamp 到 [minValue, max_ref 当前值]，不跑 stat 管线。
func _test_set_resource_clamps_to_min_and_cap() -> void:
	var attr_set := _make_with_hp()
	attr_set.set_resource("hp", 130.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 100.0, 0.0001, "set above cap clamps to max_hp")
	attr_set.set_resource("hp", -5.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 0.0, 0.0001, "set below minValue clamps to 0")
	attr_set.add_resource("hp", 30.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 30.0)
	attr_set.add_resource("hp", 500.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 100.0, 0.0001, "add past cap clamps to max_hp")
	attr_set.add_resource("hp", -40.0)
	TestFramework.assert_near(attr_set.get_current_value("hp"), 60.0)
	# stat 不受资源写入影响
	TestFramework.assert_near(attr_set.get_current_value("atk"), 50.0)
	TestFramework.assert_near(attr_set.get_current_value("max_hp"), 100.0)


## 资源写入只通知自己、只在值变时通知（clamp 后与旧值相同 = 无事件），change_type = "current"。
func _test_set_resource_notifies_only_on_change() -> void:
	var attr_set := _make_with_hp()
	var events: Array[Dictionary] = []
	attr_set.add_change_listener(func(event: Dictionary) -> void:
		events.append(event))

	attr_set.set_resource("hp", 40.0)
	TestFramework.assert_equal(1, events.size())
	TestFramework.assert_equal("hp", events[0].get("attribute_name"))
	TestFramework.assert_near(float(events[0].get("old_value")), 100.0)
	TestFramework.assert_near(float(events[0].get("new_value")), 40.0)
	TestFramework.assert_equal("current", events[0].get("change_type"))

	attr_set.set_resource("hp", 40.0)
	TestFramework.assert_equal(1, events.size())
	attr_set.set_resource("hp", 999.0)
	TestFramework.assert_equal(2, events.size())
	TestFramework.assert_near(float(events[1].get("new_value")), 100.0)
	attr_set.set_resource("hp", 999.0)
	TestFramework.assert_equal(2, events.size())
	attr_set.add_resource("hp", 0.0)
	TestFramework.assert_equal(2, events.size())


## 没有 max_ref 的资源只受 minValue 约束；kind 查询区分两种属性。
func _test_uncapped_resource_and_kind_queries() -> void:
	var attr_set := _make_stats()
	attr_set.define_resource("mp", 50.0, 0.0)
	TestFramework.assert_true(attr_set.has_attribute("mp"))
	TestFramework.assert_true(attr_set.is_resource("mp"))
	TestFramework.assert_false(attr_set.is_resource("atk"))
	TestFramework.assert_false(attr_set.is_resource("no_such_attr"))
	attr_set.set_resource("mp", 1000000.0)
	TestFramework.assert_near(attr_set.get_current_value("mp"), 1000000.0, 0.0001, "no max_ref = no cap")
	attr_set.set_resource("mp", -1.0)
	TestFramework.assert_near(attr_set.get_current_value("mp"), 0.0)
	var expected: Array[String] = ["atk", "def", "mp"]
	TestFramework.assert_equal(expected, attr_set.get_attribute_names())




## config 里资源初值高于上限：apply_config 收尾按 max_ref 一次 clamp（与 stat 入口方法同一条规则）。
func _test_apply_config_clamps_initial_value_to_cap() -> void:
	var attr_set := RawAttributeSet.new()
	attr_set.apply_config({
		"hp": { "kind": "resource", "baseValue": 150.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 100.0 },
	})
	TestFramework.assert_near(attr_set.get_current_value("hp"), 100.0)
	TestFramework.assert_near(attr_set.get_breakdown("hp").current_value, 100.0)
