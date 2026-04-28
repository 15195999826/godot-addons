extends Node

## 验证 generator `_extends` 产生的 Hex 战斗属性集继承链工作正常:
##   1. 父属性 (hp/max_hp) 在 Character / Environment 子集都可见
##   2. 父级 cross-attr clamp (hp ≤ max_hp) 在子集实例上仍生效
##   3. 子集独有属性 (atk/def/speed) 只出现在 Character, Environment 没有
##   4. 给 Environment 加未注册属性 modifier 不 crash (warning + ignore)


func _init() -> void:
	TestFramework.register_test("HexBattleActor parent attrs visible on Character", _test_parent_attrs_on_character)
	TestFramework.register_test("HexBattleActor parent attrs visible on Environment", _test_parent_attrs_on_environment)
	TestFramework.register_test("Parent cross-clamp (hp ≤ max_hp) effective on Character", _test_clamp_on_character)
	TestFramework.register_test("Parent cross-clamp (hp ≤ max_hp) effective on Environment", _test_clamp_on_environment)
	TestFramework.register_test("Environment lacks character-only attrs (atk/def/speed)", _test_env_lacks_character_attrs)
	TestFramework.register_test("Modifier on undefined attr is silently ignored", _test_undefined_modifier_warning)


func _test_parent_attrs_on_character() -> void:
	var attrs := HexBattleCharacterAttributeSet.new("test")
	TestFramework.assert_near(100.0, attrs.hp, "Character.hp inherits parent default")
	TestFramework.assert_near(100.0, attrs.max_hp, "Character.max_hp inherits parent default")


func _test_parent_attrs_on_environment() -> void:
	var attrs := HexBattleEnvironmentAttributeSet.new("test")
	TestFramework.assert_near(100.0, attrs.hp, "Environment.hp inherits parent default")
	TestFramework.assert_near(100.0, attrs.max_hp, "Environment.max_hp inherits parent default")


func _test_clamp_on_character() -> void:
	var attrs := HexBattleCharacterAttributeSet.new("test")
	attrs.set_max_hp_base(50.0)
	attrs.set_hp_base(999.0)
	TestFramework.assert_near(50.0, attrs.hp, "hp clamped by max_hp on Character (parent clamp inherited)")


func _test_clamp_on_environment() -> void:
	var attrs := HexBattleEnvironmentAttributeSet.new("test")
	attrs.set_max_hp_base(50.0)
	attrs.set_hp_base(999.0)
	TestFramework.assert_near(50.0, attrs.hp, "hp clamped by max_hp on Environment (parent clamp inherited)")


func _test_env_lacks_character_attrs() -> void:
	var attrs := HexBattleEnvironmentAttributeSet.new("test")
	# atk/def/speed 是 Character 的专属属性, Environment 不应注册它们到 _raw
	TestFramework.assert_false(attrs._raw.has_attribute("atk"),
		"Environment should not register character-only attr 'atk'")
	TestFramework.assert_false(attrs._raw.has_attribute("def"),
		"Environment should not register character-only attr 'def'")
	TestFramework.assert_false(attrs._raw.has_attribute("speed"),
		"Environment should not register character-only attr 'speed'")


func _test_undefined_modifier_warning() -> void:
	# 给 Environment 加 atk modifier (未注册的属性) 应该 silent ignore, 不 crash。
	var attrs := HexBattleEnvironmentAttributeSet.new("test")
	var modifier := AttributeModifier.new(
		"test_atk_mod", "atk", AttributeModifier.Type.ADD_BASE, 10.0, "test"
	)
	attrs._raw.add_modifier(modifier)  # 期望 warning + return, 不 crash
	# 通过断言"hp/max_hp 仍是默认值"验证整体没崩
	TestFramework.assert_near(100.0, attrs.hp, "Environment instance still functional after invalid modifier")
