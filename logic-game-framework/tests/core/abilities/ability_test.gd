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

	func on_event(_event_dict: Dictionary, _context: AbilityLifecycleContext) -> bool:
		event_hit = true
		return true

class TestComponentConfig:
	extends AbilityComponentConfig

	func create_component() -> AbilityComponent:
		return TestComponent.new()


class RecordingAction:
	extends Action.BaseAction

	var calls := 0

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(_ctx: ExecutionContext) -> ActionResult:
		calls += 1
		return ActionResult.create_success_result([])


## grant 要求 owner 已登记进 instance（AbilitySet.grant_ability 断言）：排序用例用它承载。
class OrderActor:
	extends BattleActor

	var ability_set: AbilitySet

	func _init() -> void:
		type = "ability_order_pin"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set


func _init() -> void:
	TestFramework.register_test("Ability applies/removes and expires", _test_lifecycle)
	TestFramework.register_test("Ability triggers component listeners", _test_triggered_listener)
	TestFramework.register_test("Ability ticks execution instances", _test_execution_instances)
	TestFramework.register_test("Ability callback cancellation skips timeline start", _test_callback_cancel)
	TestFramework.register_test("Ability resolves active_use components ahead of other components", _test_component_order_active_use_first)

func _test_lifecycle() -> void:
	var owner_actor_id := "actor-1"
	var test_config := TestComponentConfig.new()
	var config := AbilityConfig.new(
		"fire",
		"",
		"",
		"",
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

	ability.receive_event({ "kind": "hit" }, context)

	TestFramework.assert_true(component.event_hit)
	TestFramework.assert_true(not result["event"].is_empty())
	TestFramework.assert_equal("hit", str(result["event"].get("kind", "")))
	TestFramework.assert_equal(1, result["components"].size())
	TestFramework.assert_equal("TestComponent", result["components"][0])
func _test_execution_instances() -> void:
	var timeline := TimelineData.new("t-ability", 1.0, {})

	var owner_actor_id := "actor-3"
	var config := AbilityConfig.new("blink")
	var ability := Ability.new(config, owner_actor_id)

	var empty_actions: Array[Action.BaseAction] = []
	ability.activate_new_execution_instance(timeline, [], empty_actions, empty_actions, {})

	TestFramework.assert_equal(1, ability.get_executing_instances().size())
	ability.tick_executions(1.0)
	TestFramework.assert_equal(0, ability.get_executing_instances().size())


func _test_callback_cancel() -> void:
	var timeline := TimelineData.new("t-callback-cancel", 1.0, {})
	var ability := Ability.new(AbilityConfig.new("callback_cancel"), "actor-4")
	var start_action := RecordingAction.new()
	var start_actions: Array[Action.BaseAction] = [start_action]
	var empty_actions: Array[Action.BaseAction] = []
	ability.add_execution_activated_listener(
		func(instance: AbilityExecutionInstance) -> void:
			instance.cancel())
	var instance := ability.activate_new_execution_instance(
		timeline, [], start_actions, empty_actions, {})
	TestFramework.assert_true(instance.is_cancelled())
	TestFramework.assert_equal(0, start_action.calls)


## 钉：component 解析顺序不随 builder 调用顺序走——active_use 恒排在普通 component 之前
## （同一 ability 内 component 顺序 = 事件响应顺序；hex stance 就是先 component_config 后 active_use 的写法）。
func _test_component_order_active_use_first() -> void:
	var timeline := TimelineData.new("t-order-pin", 1.0, {})
	var config := (AbilityConfig.builder()
		.config_id("order_pin")
		.component_config(TagComponentConfig.builder().tag("order_pin_tag").build())
		.active_use(ActiveUseConfig.builder().timeline(timeline).build())
		.build())
	var instance := GameWorld.create_instance(GameplayInstance.new("ability_order_pin"))
	var actor := instance.add_actor(OrderActor.new()) as OrderActor
	var ability := Ability.new(config, actor.get_id())
	actor.ability_set.grant_ability(ability)

	var components := ability.get_all_components()
	TestFramework.assert_equal(2, components.size())
	TestFramework.assert_true(components[0] is ActiveUseComponent, "active_use 组件应排在最前")
	TestFramework.assert_true(components[1] is TagComponent, "普通 component 应排在 active_use 之后")
	TestFramework.assert_true(actor.ability_set.has_tag("order_pin_tag"))
	GameWorld.destroy_instance(instance.id)
