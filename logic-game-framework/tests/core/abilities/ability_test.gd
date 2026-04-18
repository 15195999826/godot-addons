extends Node

class TestComponent:
	extends AbilityComponent

	var applied := false
	var removed := false
	var event_hit := false

	func _init() -> void:
		type = "TestComponent"

	func on_apply(_context: AbilityLifecycleContext) -> void:
		applied = true

	func on_remove(_context: AbilityLifecycleContext) -> void:
		removed = true

	func on_event(_event_dict: Dictionary, _context: AbilityLifecycleContext, _game_state_provider: Variant) -> bool:
		event_hit = true
		return true

class TestComponentConfig:
	extends AbilityComponentConfig

	func create_component() -> AbilityComponent:
		return TestComponent.new()
func _init() -> void:
	TestFramework.register_test("Ability applies/removes and expires", _test_lifecycle)
	TestFramework.register_test("Ability triggers component listeners", _test_triggered_listener)
	TestFramework.register_test("Ability ticks execution instances", _test_execution_instances)

func _test_lifecycle() -> void:
	var owner_actor_id := "actor-1"
	var test_config := TestComponentConfig.new()
	var config := AbilityConfig.new(
		"fire",
		"",
		"",
		"",
		[],
		[],
		[test_config]
	)
	var ability := Ability.new(config, owner_actor_id)
	var component: TestComponent = ability.get_all_components()[0] as TestComponent
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null)

	ability.apply_effects(context)
	TestFramework.assert_equal(Ability.STATE_GRANTED, ability.get_state())
	TestFramework.assert_true(component.applied)

	ability.remove_effects()
	TestFramework.assert_true(component.removed)

	ability.expire("manual")
	TestFramework.assert_equal(Ability.STATE_EXPIRED, ability.get_state())
	TestFramework.assert_equal("manual", ability.get_expire_reason())
func _test_triggered_listener() -> void:
	var owner_actor_id := "actor-2"
	var test_config := TestComponentConfig.new()
	var config := AbilityConfig.new(
		"storm",
		"",
		"",
		"",
		[],
		[],
		[test_config]
	)
	var ability := Ability.new(config, owner_actor_id)
	var component: TestComponent = ability.get_all_components()[0] as TestComponent
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null)
	ability.apply_effects(context)

	var result := { "event": {}, "components": [] as Array[String] }
	ability.add_triggered_listener(func(event_dict: Dictionary, triggered_components: Array) -> void:
		result["event"] = event_dict
		result["components"] = triggered_components
	)

	ability.receive_event({ "kind": "hit" }, context, null)

	TestFramework.assert_true(component.event_hit)
	TestFramework.assert_true(not result["event"].is_empty())
	TestFramework.assert_equal("hit", str(result["event"].get("kind", "")))
	TestFramework.assert_equal(1, result["components"].size())
	TestFramework.assert_equal("TestComponent", result["components"][0])
func _test_execution_instances() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new("t-ability", 1.0, {}))

	var owner_actor_id := "actor-3"
	var config := AbilityConfig.new("blink")
	var ability := Ability.new(config, owner_actor_id)

	var empty_actions: Array[Action.BaseAction] = []
	ability.activate_new_execution_instance("t-ability", [], empty_actions, empty_actions, {}, null)

	TestFramework.assert_equal(1, ability.get_executing_instances().size())
	ability.tick_executions(1.0, null)
	TestFramework.assert_equal(0, ability.get_executing_instances().size())
