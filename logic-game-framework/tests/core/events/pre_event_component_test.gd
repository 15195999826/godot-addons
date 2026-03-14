extends Node

class MockActor:
	extends RefCounted

	var _ability_set: AbilitySet

	func _init(ability_set_value: AbilitySet) -> void:
		_ability_set = ability_set_value

	func get_ability_set() -> AbilitySet:
		return _ability_set


class MockState:
	extends RefCounted

	var _actor: MockActor
	var event_processor: EventProcessor

	func _init(ability_set_value: AbilitySet, event_processor_value: EventProcessor) -> void:
		_actor = MockActor.new(ability_set_value)
		event_processor = event_processor_value

	func get_actor(_actor_id: String) -> MockActor:
		return _actor

func _init() -> void:
	TestFramework.register_test("PreEventComponent - registers handler when granted", _test_registration)
	TestFramework.register_test("PreEventComponent - unregisters handler when revoked", _test_unregistration)
	TestFramework.register_test("PreEventComponent - modifies event values", _test_modify_event)
	TestFramework.register_test("PreEventComponent - cancels event", _test_cancel_event)

func _build_context(state: Variant, event: Dictionary = {}) -> ExecutionContext:
	var event_dict_chain: Array[Dictionary] = [event]
	return ExecutionContext.create(
		event_dict_chain,
		state,
		EventCollector.new(),
		null,  # ability_ref
		null   # execution_info
	)

## 创建测试用 EventProcessor 并设置到 GameWorld，返回旧的 processor 用于恢复
func _setup_event_processor() -> EventProcessor:
	var old_processor := GameWorld.event_processor
	var event_processor := EventProcessor.new(EventProcessorConfig.new(10, 2))
	GameWorld.event_processor = event_processor
	return old_processor

## 恢复 GameWorld.event_processor 到测试前状态
func _teardown_event_processor(old_processor: EventProcessor) -> void:
	GameWorld.event_processor = old_processor

func _test_registration() -> void:
	var old_processor := _setup_event_processor()
	var owner_actor_id := "unit-1"
	var ability_set := AbilitySet.create(owner_actor_id, null)

	var event_processor := GameWorld.event_processor
	var state := MockState.new(ability_set, event_processor)

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.7),
			]),
		func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return event.get("targetId") == ctx.owner_actor_id
	)

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, owner_actor_id)
	ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": "unit-1", "damage": 100}
	var mutable := event_processor.process_pre_event(event, state)

	TestFramework.assert_true(not mutable.cancelled)
	TestFramework.assert_near(70, float(mutable.get_current_value("damage")))
	_teardown_event_processor(old_processor)

func _test_unregistration() -> void:
	var old_processor := _setup_event_processor()
	var owner_actor_id := "unit-1"
	var ability_set := AbilitySet.create(owner_actor_id, null)

	var event_processor := GameWorld.event_processor
	var state := MockState.new(ability_set, event_processor)

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.5),
			])
	)

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, owner_actor_id)
	ability_set.grant_ability(ability)
	ability_set.revoke_ability(ability.id)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": "unit-1", "damage": 100}
	var mutable := event_processor.process_pre_event(event, state)

	TestFramework.assert_near(100, float(mutable.get_current_value("damage")))
	_teardown_event_processor(old_processor)

func _test_modify_event() -> void:
	var old_processor := _setup_event_processor()
	var owner_actor_id := "unit-1"
	var ability_set := AbilitySet.create(owner_actor_id, null)

	var event_processor := GameWorld.event_processor
	var state := MockState.new(ability_set, event_processor)

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.7),
				Modification.add("damage", -10.0),
			])
	)

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, owner_actor_id)
	ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": "unit-1", "damage": 100}
	var mutable := event_processor.process_pre_event(event, state)

	# 计算顺序: SET → ADD → MULTIPLY
	# (100 + (-10)) * 0.7 = 63
	TestFramework.assert_near(63, float(mutable.get_current_value("damage")))
	_teardown_event_processor(old_processor)

func _test_cancel_event() -> void:
	var old_processor := _setup_event_processor()
	var owner_actor_id := "unit-1"
	var ability_set := AbilitySet.create(owner_actor_id, null)

	var event_processor := GameWorld.event_processor
	var state := MockState.new(ability_set, event_processor)

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.cancel_intent(ctx.ability.id, "immune")
	)

	var ability_config := AbilityConfig.new("buff_immune", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, owner_actor_id)
	ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": "unit-1", "damage": 100}
	var mutable := event_processor.process_pre_event(event, state)

	TestFramework.assert_true(mutable.cancelled)
	TestFramework.assert_equal("immune", mutable.cancel_reason)
	_teardown_event_processor(old_processor)
