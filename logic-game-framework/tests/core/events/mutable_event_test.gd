extends Node

func _init() -> void:
	TestFramework.register_test("MutableEvent applies modifications", _test_modifications)
	TestFramework.register_test("MutableEvent collects computation steps", _test_steps)

func _test_modifications() -> void:
	var event := {
		"kind": "damage",
		"damage": 100.0,
	}
	var mutable := MutableEvent.new(event, EventPhase.PHASE_PRE)
	mutable.add_modification(Modification.multiply("damage", 0.7))
	mutable.add_modification(Modification.add("damage", -10.0))
	# 应用顺序：set -> add -> multiply
	# 计算：100 - 10 (add) = 90, 90 * 0.7 (multiply) = 63
	TestFramework.assert_near(63.0, float(mutable.get_current_value("damage")))

	var final_event := mutable.to_final_event()
	TestFramework.assert_near(63.0, float(final_event["damage"]))

func _test_steps() -> void:
	var event := {
		"kind": "damage",
		"damage": 50.0,
	}
	var mutable := MutableEvent.new(event, EventPhase.PHASE_PRE)
	mutable.add_modification(Modification.set_value("damage", 60.0, "buff"))
	mutable.add_modification(Modification.add("damage", 10.0, "bonus"))
	var record := mutable.get_field_computation_steps("damage")
	TestFramework.assert_true(record != null)
	TestFramework.assert_near(70.0, float(record["finalValue"]))
