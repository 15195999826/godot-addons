extends Node

const GENERATED_PATH := "res://addons/logic-game-framework/example/attributes/generated/example_hero_attribute_set.gd"

func _init() -> void:
	TestFramework.register_test("Generated example attribute set works", _test_generated_example)

func _test_generated_example() -> void:
	if not FileAccess.file_exists(GENERATED_PATH):
		TestFramework.assert_true(false, "Generated file missing: %s (run LGFramework -> 生成属性集)" % GENERATED_PATH)
		return

	var script := load(GENERATED_PATH)
	TestFramework.assert_true(script != null, "Failed to load generated script: %s" % GENERATED_PATH)
	if script == null:
		return

	var instance: RefCounted = script.new()
	TestFramework.assert_true(instance != null, "Failed to instantiate generated attribute set")
	if instance == null:
		return

	TestFramework.assert_near(120.0, instance.max_hp)
	instance.set_max_hp_base(150.0)
	TestFramework.assert_near(150.0, instance.max_hp)

	TestFramework.assert_near(12.0, instance.attack)
	instance.set_attack_base(20.0)
	TestFramework.assert_near(20.0, instance.attack)
