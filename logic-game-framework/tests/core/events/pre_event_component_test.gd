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
	## is_event_responsive 被问的次数：只有重建 context 时才问到（filter_lambda 与 handler_lambda 各问一次），
	## 被 event_filter 拒掉的登记一次都不问。
	var responsive_queries := 0

	func _init() -> void:
		type = "MockActor"

	func get_ability_set() -> AbilitySet:
		return ability_set

	func is_event_responsive(event_dict: Dictionary, phase: String) -> bool:
		responsive_queries += 1
		return super.is_event_responsive(event_dict, phase)


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
	TestFramework.register_test("PreEventComponent - two same-kind components on one ability unregister independently", _test_same_kind_components_unregister_independently)
	TestFramework.register_test("PreEventComponent - event_filter rejects before the context is rebuilt", _test_event_filter_rejects_before_context)
	TestFramework.register_test("PreEventComponent - context_filter runs after the rebuild and can refuse", _test_context_filter_refuses_with_context)


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
			return event.get("target_id") == ctx.owner_actor_id
	)

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
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

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)
	env.ability_set.revoke_ability(ability.id)

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
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

	var ability_config := AbilityConfig.new("buff_armor", "", "", "", [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
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

	var ability_config := AbilityConfig.new("buff_immune", "", "", "", [], [component_config])
	var ability := Ability.new(ability_config, env.owner_id)
	env.ability_set.grant_ability(ability)

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
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
	var ability_config := AbilityConfig.new("buff_thorns", "", "", "", [], [component_config])
	env.ability_set.grant_ability(Ability.new(ability_config, env.owner_id))

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
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
		AbilityConfig.new("buff_expirer", "", "", "", [], [expirer_config]), env.owner_id))
	var halve_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.5),
			])
	)
	env.ability_set.grant_ability(Ability.new(
		AbilityConfig.new("buff_halve", "", "", "", [], [halve_config]), env.owner_id))

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		100.0, 0.0001, "同一次派发里已过期的 ability 不应再改事件")
	_teardown_env(env)


## 同一 ability 挂两个同 kind 的 PreEventComponent：注册 id 各自带组件序号，
## 先注销后一个组件不会误删前一个的注册；两个都注销后事件才回到原值。
func _test_same_kind_components_unregister_independently() -> void:
	var env := _setup_env()

	var halve_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", 0.5),
			])
	)
	var minus_ten_config := PreEventConfig.new(
		"pre_damage",
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.add("damage", -10.0),
			])
	)
	var ability := Ability.new(AbilityConfig.new("buff_two_pre", "", "", "", [], [halve_config, minus_ten_config]), env.owner_id)
	env.ability_set.grant_ability(ability)
	var components := ability.get_all_components()
	TestFramework.assert_equal(2, components.size())

	var event := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
	# 两个都在：(100 - 10) * 0.5 = 45
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		45.0, 0.0001, "both components registered")

	# 只注销第二个组件：第一个（减半）必须仍在
	components[1].on_remove(null)
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		50.0, 0.0001, "removing the second component must not take the first component's registration with it")

	components[0].on_remove(null)
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(event).get_current_value("damage")),
		100.0, 0.0001, "after both components are removed the event is untouched")

	env.ability_set.revoke_ability(ability.id)
	_teardown_env(env)


## event_filter 在重建 context 之前判：不是打在我身上的事件，连 is_event_responsive 都不问、context_filter 也不跑；
## 通过的照常重建 context（filter_lambda 与 handler_lambda 各一次）、跑 context_filter、跑 handler。
## 两个 actor 共用同一份 config：链式方法是 copy-with，同一份 config 建出的两个组件各按自己的 owner 判。
func _test_event_filter_rejects_before_context() -> void:
	var env := _setup_env()
	var other := MockActor.new()
	env.instance.add_actor(other)
	other.ability_set = AbilitySet.new(other.get_id(), null)

	var context_filter_owners: Array[String] = []
	var target_is_me := func(event: Dictionary, me: HandlerContext) -> bool:
		return str(event.get("target_id", "")) == me.owner_id
	var note_owner := func(_event: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		context_filter_owners.append(ctx.owner_actor_id)
		return true
	var config := PreEventConfig.new("pre_damage", _halve).event_filter(target_is_me).context_filter(note_owner)
	TestFramework.assert_true(config.has_event_filter())
	env.ability_set.grant_ability(Ability.new(AbilityConfig.new("buff_halve_mine", "", "", "", [], [config]), env.owner_id))
	other.ability_set.grant_ability(Ability.new(AbilityConfig.new("buff_halve_mine", "", "", "", [], [config]), other.get_id()))

	var mine := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(mine).get_current_value("damage")),
		50.0, 0.0001, "通过 event_filter 的登记照常改事件")
	TestFramework.assert_equal(2, env.actor.responsive_queries)  # 通过 event_filter 的登记才重建 context（context_filter 与 handler 各一次）
	TestFramework.assert_equal(0, other.responsive_queries)  # 被 event_filter 拒掉的登记不重建 context
	TestFramework.assert_equal([env.owner_id], context_filter_owners)  # context_filter 只对通过 event_filter 的登记跑

	var nobody := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": "nobody", "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(nobody).get_current_value("damage")),
		100.0, 0.0001, "谁都不是的事件没人改")
	TestFramework.assert_equal(2, env.actor.responsive_queries)  # 两条登记都被 event_filter 拒掉，谁都不重建
	TestFramework.assert_equal(0, other.responsive_queries)
	TestFramework.assert_equal(1, context_filter_owners.size())
	_teardown_env(env)


## context_filter 拿完整 ctx、在重建之后跑：拒掉就不跑 handler。它和构造函数第三个位置参数写的是同一个字段。
func _test_context_filter_refuses_with_context() -> void:
	var env := _setup_env()
	var from_boss := func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		return ctx.ability != null and ctx.owner_actor_id == env.owner_id and str(event.get("source_id", "")) == "boss"
	env.ability_set.grant_ability(Ability.new(
		AbilityConfig.new("buff_halve_boss", "", "", "", [], [PreEventConfig.new("pre_damage", _halve).context_filter(from_boss)]),
		env.owner_id))

	var from_minion := {"kind": "pre_damage", "source_id": "enemy-1", "target_id": env.owner_id, "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(from_minion).get_current_value("damage")),
		100.0, 0.0001, "context_filter 拒掉的不改事件")
	TestFramework.assert_equal(1, env.actor.responsive_queries)  # context_filter 之前已经重建过 context（问过一次死活门）

	var from_boss_event := {"kind": "pre_damage", "source_id": "boss", "target_id": env.owner_id, "damage": 100}
	TestFramework.assert_near(
		float(env.instance.event_processor.process_pre_event(from_boss_event).get_current_value("damage")),
		50.0, 0.0001, "context_filter 放行的照常改事件")
	TestFramework.assert_equal(3, env.actor.responsive_queries)
	_teardown_env(env)


static func _halve(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
	return EventPhase.modify_intent(ctx.ability.id, [Modification.multiply("damage", 0.5)])
