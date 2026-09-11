extends Node

## PreEventComponent 测试
##
## 注意：PreEventComponent 的 handler/filter lambda 经 AbilityLifecycleContext.rebuild_for_handler
## 按 owner id 反查重建 context，要求 actor 必须通过 GameWorld.create_instance + instance.add_actor 注册。
## 因此每个测试都走完整注册流程，不能直接 new AbilitySet 用硬编码 owner_id。

class MockActor:
	extends BattleActor

	## rebuild_for_handler 走 BattleActor.ability_set_of() → get_ability_set()
	var ability_set: AbilitySet

	func _init() -> void:
		type = "MockActor"

	func get_ability_set() -> AbilitySet:
		return ability_set


class MockInstance:
	extends GameplayInstance

	func _init() -> void:
		super._init("", EventProcessorConfig.new(10, 2))
		type = "MockInstance"


func _init() -> void:
	TestFramework.register_test("PreEventComponent - registers handler when granted", _test_registration)
	TestFramework.register_test("PreEventComponent - unregisters handler when revoked", _test_unregistration)
	TestFramework.register_test("PreEventComponent - modifies event values", _test_modify_event)
	TestFramework.register_test("PreEventComponent - dead actor stops responding", _test_dead_actor_stops_responding)
	TestFramework.register_test("PreEventComponent - cancels event", _test_cancel_event)
	TestFramework.register_test("PreEventComponent - ability expired earlier in the same dispatch is skipped", _test_expired_mid_dispatch_skipped)


## 测试环境：注册到 GameWorld 的 mock instance（自带 event_processor）+ mock actor + 配套 ability_set
class TestEnv:
	extends RefCounted
	var instance: GameplayInstance
	var actor: MockActor
	var owner_id: String
	var ability_set: AbilitySet


func _setup_env() -> TestEnv:
	var env := TestEnv.new()
	env.instance = GameWorld.create_instance(MockInstance.new())

	env.actor = MockActor.new()
	env.instance.add_actor(env.actor)
	env.owner_id = env.actor.get_id()

	env.ability_set = AbilitySet.new(env.owner_id, null)
	env.actor.ability_set = env.ability_set
	return env


func _teardown_env(env: TestEnv) -> void:
	GameWorld.destroy_instance(env.instance.id)


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
	var mutable := env.instance.event_processor.process_pre_event(event)

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
	var mutable := env.instance.event_processor.process_pre_event(event)

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
	var mutable := env.instance.event_processor.process_pre_event(event)

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
	var mutable := env.instance.event_processor.process_pre_event(event)

	TestFramework.assert_true(mutable.cancelled)
	TestFramework.assert_equal("immune", mutable.cancel_reason)
	_teardown_env(env)


## 死者不再触发 PreEvent handler（反伤 / 护盾等被动死后失效）。
##
## 真正执行短路的是 `AbilityLifecycleContext.rebuild_for_handler` 对 owner `is_event_responsive(event, "pre")`
## 的询问，所以断言必须打在派发结果上——只断言钩子的返回值钉不住这条链。
func _test_dead_actor_stops_responding() -> void:
	var env := _setup_env()

	var component_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.5),
			])
	)
	var ability_config := AbilityConfig.new("buff_thorns", "", "", "", [], [], [component_config])
	env.ability_set.grant_ability(Ability.new(ability_config, env.owner_id))

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": env.owner_id, "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		50.0, 0.0001, "活着时 handler 应生效")

	env.actor.mark_dead()
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		100.0, 0.0001, "死后 handler 不应再改事件")

	env.actor.set_death_latch(false)
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		50.0, 0.0001, "解闩后 handler 应恢复（注册没被销毁）")
	_teardown_env(env)


## pre 派发遍历快照：先执行的 handler 让排在后面的 ability 过期，后者的注册仍在快照里，
## 但重建 context 时发现 ability 已过期，不再改事件。
func _test_expired_mid_dispatch_skipped() -> void:
	var env := _setup_env()

	var expirer_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			ctx.ability_set.find_ability_by_config_id("buff_halve").expire("expired_mid_dispatch")
			return EventPhase.pass_intent()
	)
	env.ability_set.grant_ability(Ability.new(
		AbilityConfig.new("buff_expirer", "", "", "", [], [], [expirer_config]), env.owner_id))
	var halve_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.5),
			])
	)
	env.ability_set.grant_ability(Ability.new(
		AbilityConfig.new("buff_halve", "", "", "", [], [], [halve_config]), env.owner_id))

	var event := {"kind": "pre_damage", "sourceId": "enemy-1", "targetId": env.owner_id, "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		100.0, 0.0001, "同一次派发里已过期的 ability 不应再改事件")
	_teardown_env(env)
