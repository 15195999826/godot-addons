extends Node

func _init() -> void:
	TestFramework.register_test("EventProcessor pre modifies event", _test_pre_modify)
	TestFramework.register_test("EventProcessor pre cancels event", _test_pre_cancel)
	TestFramework.register_test("EventProcessor pre handlers are isolated per instance", _test_pre_handlers_isolated_per_instance)

func _test_pre_modify() -> void:
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

	var mutable := processor.process_pre_event({ "kind": "damage", "damage": 100.0 })
	TestFramework.assert_near(50.0, float(mutable.get_current_value("damage")))
	TestFramework.assert_true(not mutable.cancelled)

func _test_pre_cancel() -> void:
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

	var mutable := processor.process_pre_event({ "kind": "damage", "damage": 100.0 })
	TestFramework.assert_true(mutable.cancelled)
	TestFramework.assert_equal("immune", mutable.cancel_reason)

## processor 归 instance：注册在 A 上的 pre handler，B 派发同 kind 事件时看不到。
func _test_pre_handlers_isolated_per_instance() -> void:
	var a := GameplayInstance.new("processor-isolation-a")
	var b := GameplayInstance.new("processor-isolation-b")
	a.event_processor.register_pre_handler(PreHandlerRegistration.new(
		"h-iso",  # id
		"damage",  # event_kind
		"actor-a",  # owner_id
		"ability-a",  # ability_id
		"config-a",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.cancel_intent("h-iso", "only_a")
	))

	TestFramework.assert_true(a.event_processor.process_pre_event({ "kind": "damage", "damage": 1.0 }).cancelled)
	TestFramework.assert_false(b.event_processor.process_pre_event({ "kind": "damage", "damage": 1.0 }).cancelled)
