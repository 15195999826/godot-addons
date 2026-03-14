extends Node

func _init() -> void:
	TestFramework.register_test("EventProcessor pre modifies event", _test_pre_modify)
	TestFramework.register_test("EventProcessor pre cancels event", _test_pre_cancel)

func _test_pre_modify() -> void:
	var mock_state := {}
	var config := EventProcessorConfig.new(5, 2)
	var processor := EventProcessor.new(config)
	
	var registration := PreHandlerRegistration.new(
		"h1",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-1",  # ability_id
		"config-1",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.modify_intent("h1", [
				Modification.multiply("damage", 0.5),
			])
	)
	processor.register_pre_handler(registration)

	var mutable := processor.process_pre_event({ "kind": "damage", "damage": 100.0 }, mock_state)
	TestFramework.assert_near(50.0, float(mutable.get_current_value("damage")))
	TestFramework.assert_true(not mutable.cancelled)

func _test_pre_cancel() -> void:
	var mock_state := {}
	var config := EventProcessorConfig.new(5, 2)
	var processor := EventProcessor.new(config)
	
	var registration := PreHandlerRegistration.new(
		"h2",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-1",  # ability_id
		"config-1",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.cancel_intent("h2", "immune")
	)
	processor.register_pre_handler(registration)

	var mutable := processor.process_pre_event({ "kind": "damage", "damage": 100.0 }, mock_state)
	TestFramework.assert_true(mutable.cancelled)
	TestFramework.assert_equal("immune", mutable.cancel_reason)
