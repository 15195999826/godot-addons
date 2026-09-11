extends Node

func _init() -> void:
	TestFramework.register_test("ActivateInstanceComponent any trigger", _test_any_trigger)
	TestFramework.register_test("ActivateInstanceComponent all trigger", _test_all_trigger)
	TestFramework.register_test("ActivateInstanceConfig builder freezes timeline tags", _test_builder_freezes_tags)
	TestFramework.register_test("ActiveUseConfig builder yields an ActivateInstanceConfig subtype", _test_active_use_config_is_activate_instance_config)

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
		[component_config]
	)
	var ability := Ability.new(ability_config, owner_actor_id)
	var component: ActivateInstanceComponent = ability.get_all_components()[0] as ActivateInstanceComponent
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null)
	ability.apply_effects(context)

	var triggered := component.on_event({"kind": "hit"}, context)
	TestFramework.assert_true(triggered)
	var expected_kinds: Array[String] = ["hit", "heal"]
	TestFramework.assert_equal(expected_kinds, component.get_post_event_kinds())
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
		[component_config]
	)
	var ability := Ability.new(ability_config, owner_actor_id)
	var component: ActivateInstanceComponent = ability.get_all_components()[0] as ActivateInstanceComponent
	var context := AbilityLifecycleContext.new(owner_actor_id, null, ability, null, null)
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

## 配置层级镜像组件层级：ActiveUse 组件是 ActivateInstance 组件，它的配置也是 ActivateInstanceConfig；
## 继承来的链式方法在子 builder 上仍返回子 builder（condition 接在 on_tag 之后能编译）。
func _test_active_use_config_is_activate_instance_config() -> void:
	var timeline := TimelineData.new("t-active-use-is-a", 1.0, {"hit": 0.5})
	var no_actions: Array[Action.BaseAction] = []
	var condition := Condition.HasTagCondition.new("ready")
	var config := (ActiveUseConfig.builder()
		.timeline(timeline)
		.on_tag("hit", no_actions)
		.condition(condition)
		.build())
	# 经 Object 变量做运行期类型判定（静态类型上 analyzer 会把类型关系直接判定成编译错误，测的不是它）
	var built: Object = config
	TestFramework.assert_true(built is ActiveUseConfig)
	TestFramework.assert_true(built is ActivateInstanceConfig)
	TestFramework.assert_true(config.timeline_data == timeline)
	TestFramework.assert_equal(1, config.tag_actions.size())
	TestFramework.assert_equal(1, config.conditions.size())
	TestFramework.assert_true(config.conditions[0] == condition)
