extends Node

func _init() -> void:
	TestFramework.register_test("ActivateInstanceComponent any trigger", _test_any_trigger)
	TestFramework.register_test("ActivateInstanceComponent all trigger", _test_all_trigger)
	TestFramework.register_test("ActivateInstanceConfig builder freezes timeline tags", _test_builder_freezes_tags)

func _test_any_trigger() -> void:
	var timeline := TimelineData.new("t-any", 1.0, {})

	var owner_actor_id := "actor-1"
	var component_config := ActivateInstanceConfig.new(
		timeline,
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
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null, null)
	ability.apply_effects(context)

	var triggered := component.on_event({"kind": "hit"}, context)
	TestFramework.assert_true(triggered)
	TestFramework.assert_equal(1, ability.get_executing_instances().size())

func _test_all_trigger() -> void:
	var timeline := TimelineData.new("t-all", 1.0, {})

	var owner_actor_id := "actor-2"
	var component_config := ActivateInstanceConfig.new(
		timeline,
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
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null, null)
	ability.apply_effects(context)

	var triggered := component.on_event({"kind": "hit"}, context)
	TestFramework.assert_true(not triggered)
	TestFramework.assert_equal(0, ability.get_executing_instances().size())

## builder.timeline(data) 声明即冻结 tags；共享实例重复声明幂等；config 直接持引用。
func _test_builder_freezes_tags() -> void:
	var timeline := TimelineData.new("t-freeze", 1.0, {"hit": 0.5})
	TestFramework.assert_false(timeline.tags.is_read_only())
	var config := (ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new("hit"))
		.timeline(timeline)
		.build())
	TestFramework.assert_true(timeline.tags.is_read_only())
	TestFramework.assert_true(config.timeline_data == timeline)
	var shared_again := ActiveUseConfig.builder().timeline(timeline).build()
	TestFramework.assert_true(shared_again.timeline_data == timeline)
