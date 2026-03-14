extends Node

func _init() -> void:
	TestFramework.register_test("RawAttributeSet apply_config accessors", _test_accessors)
	TestFramework.register_test("RawAttributeSet supports modifiers", _test_modifiers)
	TestFramework.register_test("RawAttributeSet supports listeners", _test_listeners)
	TestFramework.register_test("RawAttributeSet serialize/restore", _test_serialize_restore)

func _test_accessors() -> void:
	var attrs := RawAttributeSet.new()
	attrs.apply_config({
		"attack": { "baseValue": 10.0 },
		"speed": { "baseValue": 5.0 },
	})

	TestFramework.assert_near(10.0, attrs.get_current_value("attack"))
	TestFramework.assert_near(5.0, attrs.get_current_value("speed"))
	TestFramework.assert_true(attrs.has_attribute("attack"))
	TestFramework.assert_true(attrs.has_attribute("speed"))

	attrs.set_base("attack", 20.0)
	TestFramework.assert_near(20.0, attrs.get_current_value("attack"))

func _test_modifiers() -> void:
	var attrs := RawAttributeSet.new()
	attrs.apply_config({
		"attack": { "baseValue": 10.0 },
	})
	attrs.add_modifier(AttributeModifier.create_add_base("buff", "attack", 5.0))
	TestFramework.assert_near(15.0, attrs.get_current_value("attack"))

func _test_listeners() -> void:
	var attrs := RawAttributeSet.new()
	attrs.apply_config({
		"hp": { "baseValue": 100.0 },
	})
	var state := { "hit": false }
	var unsubscribe: Callable = attrs.on_attribute_changed("hp", func(event: Dictionary) -> void:
		state["hit"] = true
		TestFramework.assert_near(100.0, float(event["oldValue"]))
		TestFramework.assert_near(90.0, float(event["newValue"]))
	)
	attrs.set_base("hp", 90.0)
	TestFramework.assert_true(state["hit"])
	unsubscribe.call()

func _test_serialize_restore() -> void:
	var attrs := RawAttributeSet.new()
	attrs.apply_config({
		"attack": { "baseValue": 10.0 },
	})
	attrs.add_modifier(AttributeModifier.create_add_base("buff", "attack", 5.0, "source"))

	var data: Dictionary = attrs.serialize()
	var restored := RawAttributeSet.deserialize(data)
	TestFramework.assert_near(15.0, restored.get_current_value("attack"))
