extends Node

## PreEventComponent 测试
##
## 注意：PreEventComponent 的 handler/filter lambda 内部调 GameWorld.get_actor(owner_id)
## 重建 context，要求 actor 必须通过 GameWorld.create_instance + instance.add_actor 注册。
## 因此每个测试都走完整注册流程，不能直接 new AbilitySet 用硬编码 owner_id。

class MockActor:
	extends Actor

	## 必须叫 ability_set（生产代码 CharacterActor 也是这个字段名）
	## PreEventComponent._rebuild_context 通过 `"ability_set" in actor` 探测
	var ability_set: AbilitySet

	func _init() -> void:
		type = "MockActor"


class MockInstance:
	extends GameplayInstance

	func _init() -> void:
		super._init()
		type = "MockInstance"


class MockState:
	extends RefCounted

	var _actor: MockActor
	var event_processor: EventProcessor

	func _init(actor_value: MockActor, event_processor_value: EventProcessor) -> void:
		_actor = actor_value
		event_processor = event_processor_value

	func get_actor(_actor_id: String) -> MockActor:
		return _actor


func _init() -> void:
	TestFramework.register_test("PreEventComponent - registers handler when granted", _test_registration)
	TestFramework.register_test("PreEventComponent - unregisters handler when revoked", _test_unregistration)
	TestFramework.register_test("PreEventComponent - modifies event values", _test_modify_event)
	TestFramework.register_test("PreEventComponent - cancels event", _test_cancel_event)


## 测试环境：独立 event_processor + 注册到 GameWorld 的 mock actor + 配套 ability_set
class TestEnv:
	extends RefCounted
	var old_processor: EventProcessor
	var event_processor: EventProcessor
	var instance: GameplayInstance
	var actor: MockActor
	var owner_id: String
	var ability_set: AbilitySet
	var state: MockState


func _setup_env() -> TestEnv:
	var env := TestEnv.new()
	env.old_processor = GameWorld.event_processor
	env.event_processor = EventProcessor.new(EventProcessorConfig.new(10, 2))
	GameWorld.event_processor = env.event_processor

	env.instance = GameWorld.create_instance(func() -> GameplayInstance:
		return MockInstance.new()
	)

	env.actor = MockActor.new()
	env.instance.add_actor(env.actor)
	env.owner_id = env.actor.get_id()

	env.ability_set = AbilitySet.new(env.owner_id, null)
	env.actor.ability_set = env.ability_set

	env.state = MockState.new(env.actor, env.event_processor)
	return env


func _teardown_env(env: TestEnv) -> void:
	GameWorld.destroy_instance(env.instance.id)
	GameWorld.event_processor = env.old_processor


func _test_registration() -> void:
	var env := _setup_env()

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
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": env.owner_id, "damage": 100}
	var mutable := env.event_processor.process_pre_event(event, env.state)

	TestFramework.assert_true(not mutable.cancelled)
	TestFramework.assert_near(70, float(mutable.get_current_value("damage")))
	_teardown_env(env)


func _test_unregistration() -> void:
	var env := _setup_env()

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.5),
			])
	)

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)
	env.ability_set.revoke_ability(ability.id)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": env.owner_id, "damage": 100}
	var mutable := env.event_processor.process_pre_event(event, env.state)

	TestFramework.assert_near(100, float(mutable.get_current_value("damage")))
	_teardown_env(env)


func _test_modify_event() -> void:
	var env := _setup_env()

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.7),
				Modification.add("damage", -10.0),
			])
	)

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": env.owner_id, "damage": 100}
	var mutable := env.event_processor.process_pre_event(event, env.state)

	# 计算顺序: SET → ADD → MULTIPLY
	# (100 + (-10)) * 0.7 = 63
	TestFramework.assert_near(63, float(mutable.get_current_value("damage")))
	_teardown_env(env)


func _test_cancel_event() -> void:
	var env := _setup_env()

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.cancel_intent(ctx.ability.id, "immune")
	)

	var ability_config := AbilityConfig.new("buff_immune", "", "", "", [], [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": env.owner_id, "damage": 100}
	var mutable := env.event_processor.process_pre_event(event, env.state)

	TestFramework.assert_true(mutable.cancelled)
	TestFramework.assert_equal("immune", mutable.cancel_reason)
	_teardown_env(env)
