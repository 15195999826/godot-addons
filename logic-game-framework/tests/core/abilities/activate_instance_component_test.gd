extends Node

func _init() -> void:
	TestFramework.register_test("ActivateInstanceComponent any trigger", _test_any_trigger)
	TestFramework.register_test("ActivateInstanceComponent all trigger", _test_all_trigger)

func _test_any_trigger() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-any",
		1.0,
		{}
	))

	var owner_actor_id := "actor-1"
	var component_config := ActivateInstanceConfig.new(
		"t-any",
		[],
		[
			TriggerConfig.new("hit"),
			TriggerConfig.new("heal"),
		],
		"any"
	)
	var ability_config := AbilityConfig.new(
		"test",
		"",
		"",
		"",
		[],
		[],
		[component_config]
	)
	var ability := Ability.new(ability_config, owner_actor_id)
	var component: ActivateInstanceComponent = ability.get_all_components()[0] as ActivateInstanceComponent
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null)
	ability.apply_effects(context)

	var triggered := component.on_event({"kind": "hit"}, context, null)
	TestFramework.assert_true(triggered)
	TestFramework.assert_equal(1, ability.get_executing_instances().size())

func _test_all_trigger() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-all",
		1.0,
		{}
	))

	var owner_actor_id := "actor-2"
	var component_config := ActivateInstanceConfig.new(
		"t-all",
		[],
		[
			TriggerConfig.new("hit"),
			TriggerConfig.new("heal"),
		],
		"all"
	)
	var ability_config := AbilityConfig.new(
		"test",
		"",
		"",
		"",
		[],
		[],
		[component_config]
	)
	var ability := Ability.new(ability_config, owner_actor_id)
	var component: ActivateInstanceComponent = ability.get_all_components()[0] as ActivateInstanceComponent
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null)
	ability.apply_effects(context)

	var triggered := component.on_event({"kind": "hit"}, context, null)
	TestFramework.assert_true(not triggered)
	TestFramework.assert_equal(0, ability.get_executing_instances().size())
