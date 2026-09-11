extends Node

## Post 事件订阅派发合同
##
## 观众由注册决定：Ability.apply_effects 按 component 的 trigger kind 各注册一条 PostHandlerRegistration、
## remove_effects 注销；死活由 actor 决定：派发时按 id 重建 context，先问 owner 的 is_event_responsive。
## 本文件钉住：同 kind 只注册一条、定向投递 kind 永不注册且照常定向投递恰一次、派发顺序（registry 顺序 → grant 顺序）、
## revoke / expire / remove_actor / end() 注销、响应钩子与豁免、Break 短路、嵌套派发的深度上限、triggered 监听者只回调一次、
## on_apply 里已过期的 ability 不注册、注册的 owner 取所在 AbilitySet 的 owner。

const LogCounter := preload("res://addons/logic-game-framework/tests/log_counter.gd")

const KIND := "post_dispatch_probe"
const DEATH_KIND := "post_dispatch_death"


## 可调响应策略的 BattleActor：死后只响应 exempt_when_dead 里的 post kind（亡语式豁免）。
class DispatchActor:
	extends BattleActor

	var ability_set: AbilitySet
	var exempt_when_dead: Array[String] = []

	func _init() -> void:
		type = "post_dispatch_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set

	func is_event_responsive(event_dict: Dictionary, phase: String) -> bool:
		if not is_dead():
			return true
		return phase == EventPhase.PHASE_POST and exempt_when_dead.has(str(event_dict.get("kind", "")))


## 把 label 追加进原始事件的 "log" 数组（测试握着那个 dict；action 本身无状态）。
class AppendLabelAction:
	extends Action.BaseAction

	var label: String

	func _init(p_label: String) -> void:
		super._init(TargetSelector.new())
		label = p_label

	func execute(ctx: ExecutionContext) -> ActionResult:
		(ctx.get_original_event()["log"] as Array).append(label)
		return ActionResult.create_success_result([])


## 记一笔后把同一个事件再 post 派发一次（嵌套深度探针）。
class RedispatchAction:
	extends Action.BaseAction

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(ctx: ExecutionContext) -> ActionResult:
		var event := ctx.get_original_event()
		(event["log"] as Array).append("depth")
		ctx.instance.event_processor.process_post_event(event)
		return ActionResult.create_success_result([])


## on_apply 里让所属 ability 过期的 component（一次性 on_apply 效果的形状）。
class ExpireOnApplyComponent:
	extends AbilityComponent

	func on_apply(context: AbilityLifecycleContext) -> void:
		context.ability.expire("post_dispatch_expire_on_apply")


class ExpireOnApplyConfig:
	extends AbilityComponentConfig

	func create_component() -> AbilityComponent:
		return ExpireOnApplyComponent.new()


func _init() -> void:
	TestFramework.register_test("PostDispatch: same kind on two components registers once, both run", _test_one_registration_per_kind)
	TestFramework.register_test("PostDispatch: direct delivery kinds never register, still delivered exactly once", _test_direct_delivery_kinds)
	TestFramework.register_test("PostDispatch: order follows registry order then grant order", _test_dispatch_order)
	TestFramework.register_test("PostDispatch: revoke and expire unregister", _test_revoke_and_expire_unregister)
	TestFramework.register_test("PostDispatch: remove_actor and end() clear registrations", _test_remove_actor_and_end_clear)
	TestFramework.register_test("PostDispatch: unresponsive owner skipped, exempt kind still delivered", _test_responsiveness_gate)
	TestFramework.register_test("PostDispatch: disabled ability skipped", _test_disabled_ability_skipped)
	TestFramework.register_test("PostDispatch: nested dispatch stops at max_depth", _test_nested_dispatch_depth)
	TestFramework.register_test("PostDispatch: triggered listener fires once with component names", _test_triggered_listener_once)
	TestFramework.register_test("PostDispatch: ability expired during on_apply registers nothing", _test_expired_during_apply_registers_nothing)
	TestFramework.register_test("PostDispatch: registration owner is the ability set's owner", _test_registration_owner_follows_ability_set)


## 同一 ability 两个 component 都监听 KIND：kind 去重后只注册一条，一次派发两个 component 各跑一次。
func _test_one_registration_per_kind() -> void:
	var instance := _create_instance("post_dispatch_dedupe")
	var actor := _spawn(instance)
	actor.ability_set.grant_ability(Ability.new(_ability_config("dedupe", [
		_no_instance(KIND, AppendLabelAction.new("first")),
		_no_instance(KIND, AppendLabelAction.new("second")),
	]), actor.get_id()))

	TestFramework.assert_equal(1, _registration_count(instance, KIND))
	TestFramework.assert_equal(["first", "second"], _dispatch(instance))
	GameWorld.destroy_instance(instance.id)


## 定向投递 kind（AbilityGranted / AbilityActivate）永不注册：grant 自投递让 GRANTED_SELF 恰好激活一次，
## AbilitySet.receive_event 的激活请求恰好激活一次——两条路都走就会是两次。
func _test_direct_delivery_kinds() -> void:
	var instance := _create_instance("post_dispatch_direct")
	var actor := _spawn(instance)
	var timeline := TimelineData.new("t-post-dispatch-direct", 1000.0, {})
	var granted := Ability.new(_ability_config("direct_granted", [
		ActivateInstanceConfig.builder().trigger(TriggerConfig.GRANTED_SELF).timeline(timeline).build(),
	]), actor.get_id())
	actor.ability_set.grant_ability(granted)
	var active := Ability.new(AbilityConfig.builder()
		.config_id("direct_active")
		.active_use(ActiveUseConfig.builder().timeline(timeline).build())
		.build(), actor.get_id())
	actor.ability_set.grant_ability(active)

	for kind in EventProcessor.DIRECT_DELIVERY_KINDS:
		TestFramework.assert_equal(0, _registration_count(instance, kind))
	TestFramework.assert_equal(1, granted.get_executing_instances().size())
	actor.ability_set.receive_event(GameEvent.AbilityActivate.create(active.id, actor.get_id()).to_dict())
	TestFramework.assert_equal(1, active.get_executing_instances().size())
	GameWorld.destroy_instance(instance.id)


## 派发顺序 = owner 进 registry 的顺序 → 同一 owner 内的 grant 顺序：B 先 grant、A 后 grant 两个，派发仍是 A1、A2、B1。
func _test_dispatch_order() -> void:
	var instance := _create_instance("post_dispatch_order")
	var actor_a := _spawn(instance)
	var actor_b := _spawn(instance)
	_grant_label(actor_b, "B1")
	_grant_label(actor_a, "A1")
	_grant_label(actor_a, "A2")

	TestFramework.assert_equal(["A1", "A2", "B1"], _dispatch(instance))
	GameWorld.destroy_instance(instance.id)


## revoke 与 expire 都当场注销该 ability 的注册（expire 不等 AbilitySet 的过期清扫）。
func _test_revoke_and_expire_unregister() -> void:
	var instance := _create_instance("post_dispatch_unregister")
	var actor := _spawn(instance)
	var revoked := _grant_label(actor, "revoked")
	var expired := _grant_label(actor, "expired")
	TestFramework.assert_equal(["revoked", "expired"], _dispatch(instance))

	actor.ability_set.revoke_ability(revoked.id)
	expired.expire("post_dispatch_test")
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	TestFramework.assert_equal([], _dispatch(instance))
	GameWorld.destroy_instance(instance.id)


## remove_actor 清掉该 owner 的 pre / post 注册、不动别人；end() 清空两张表。
func _test_remove_actor_and_end_clear() -> void:
	var instance := _create_instance("post_dispatch_clear")
	var leaving := _spawn(instance)
	var staying := _spawn(instance)
	for actor: DispatchActor in [leaving, staying]:
		actor.ability_set.grant_ability(Ability.new(_ability_config("clear", [
			_no_instance(KIND, AppendLabelAction.new(actor.get_id())),
			PreEventConfig.new(KIND, func(_mutable: MutableEvent, _ctx: AbilityLifecycleContext) -> Intent:
				return EventPhase.pass_intent()),
		]), actor.get_id()))

	instance.remove_actor(leaving.get_id())
	TestFramework.assert_equal([staying.get_id()], _dispatch(instance))
	TestFramework.assert_equal(1, (instance.event_processor._pre_handlers.get(KIND, []) as Array).size())

	instance.end()
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	TestFramework.assert_equal(0, (instance.event_processor._pre_handlers.get(KIND, []) as Array).size())
	GameWorld.destroy_instance(instance.id)


## 死者不响应：派发先问 is_event_responsive，返回 false 就跳过；豁免的 kind（亡语式）死后照样送达；
## 解闩后恢复——注册一直在。
func _test_responsiveness_gate() -> void:
	var instance := _create_instance("post_dispatch_responsive")
	var actor := _spawn(instance)
	actor.exempt_when_dead.append(DEATH_KIND)
	actor.ability_set.grant_ability(Ability.new(_ability_config("responsive", [
		_no_instance(KIND, AppendLabelAction.new("hit")),
		_no_instance(DEATH_KIND, AppendLabelAction.new("deathrattle")),
	]), actor.get_id()))

	actor.mark_dead()
	TestFramework.assert_equal([], _dispatch(instance, KIND))
	TestFramework.assert_equal(["deathrattle"], _dispatch(instance, DEATH_KIND))
	actor.set_death_latch(false)
	TestFramework.assert_equal(["hit"], _dispatch(instance, KIND))
	GameWorld.destroy_instance(instance.id)


## Break：disabled 的 ability 注册还在，派发到 receive_event 就短路；解除后恢复。
func _test_disabled_ability_skipped() -> void:
	var instance := _create_instance("post_dispatch_disabled")
	var actor := _spawn(instance)
	var ability := _grant_label(actor, "passive")

	ability.add_disabled_source("break_source")
	TestFramework.assert_equal(1, _registration_count(instance, KIND))
	TestFramework.assert_equal([], _dispatch(instance))
	ability.remove_disabled_source("break_source")
	TestFramework.assert_equal(["passive"], _dispatch(instance))
	GameWorld.destroy_instance(instance.id)


## handler 里再派发同一个事件：到 max_depth 停下、报一条深度超限错误，深度计数归零（不挂、不无限递归）。
func _test_nested_dispatch_depth() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("post_dispatch_depth", EventProcessorConfig.new(3)))
	var actor := _spawn(instance)
	actor.ability_set.grant_ability(Ability.new(_ability_config("redispatch", [
		_no_instance(KIND, RedispatchAction.new()),
	]), actor.get_id()))

	var log_counter := LogCounter.new()
	OS.add_logger(log_counter)
	var labels := _dispatch(instance)
	OS.remove_logger(log_counter)
	TestFramework.assert_equal(3, labels.size())
	TestFramework.assert_equal(1, log_counter.errors)
	TestFramework.assert_equal(0, instance.event_processor.get_current_depth())
	GameWorld.destroy_instance(instance.id)


## triggered 监听者（录像 abilityTriggered 的来源）：一次派发只回调一次，带全部被触发 component 的名字。
func _test_triggered_listener_once() -> void:
	var instance := _create_instance("post_dispatch_triggered")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("triggered", [
		_no_instance(KIND, AppendLabelAction.new("first")),
		_no_instance(KIND, AppendLabelAction.new("second")),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	var calls: Array[Array] = []
	ability.add_triggered_listener(func(event_dict: Dictionary, triggered_components: Array[String]) -> void:
		calls.append([str(event_dict.get("kind", "")), triggered_components.duplicate()]))

	_dispatch(instance)
	TestFramework.assert_equal(1, calls.size())
	TestFramework.assert_equal([KIND, [NoInstanceComponent.TYPE, NoInstanceComponent.TYPE]], calls[0])
	GameWorld.destroy_instance(instance.id)


## component 的 on_apply 让本 ability 过期（remove_effects 已跑完）：apply_effects 不再注册，否则这条注册没有人注销。
func _test_expired_during_apply_registers_nothing() -> void:
	var instance := _create_instance("post_dispatch_expire_on_apply")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("expire_on_apply", [
		_no_instance(KIND, AppendLabelAction.new("never")),
		ExpireOnApplyConfig.new(),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)

	TestFramework.assert_true(ability.is_expired())
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	TestFramework.assert_true(ability._post_unregisters.is_empty())
	GameWorld.destroy_instance(instance.id)


## 注册的 owner 取 ability 所在 AbilitySet 的 owner，不取 Ability 构造时记下的 owner_actor_id：
## 派发按它找回 ability，remove_actor 按它注销。
func _test_registration_owner_follows_ability_set() -> void:
	var instance := _create_instance("post_dispatch_owner")
	var actor := _spawn(instance)
	actor.ability_set.grant_ability(Ability.new(_ability_config("owner_from_set", [
		_no_instance(KIND, AppendLabelAction.new("heard")),
	]), ""))

	TestFramework.assert_equal(["heard"], _dispatch(instance))
	instance.remove_actor(actor.get_id())
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	GameWorld.destroy_instance(instance.id)


# ========== 夹具 ==========

static func _create_instance(instance_id: String) -> GameplayInstance:
	return GameWorld.create_instance(GameplayInstance.new(instance_id))


static func _spawn(instance: GameplayInstance) -> DispatchActor:
	return instance.add_actor(DispatchActor.new()) as DispatchActor


static func _no_instance(kind: String, action: Action.BaseAction) -> NoInstanceConfig:
	return NoInstanceConfig.builder().trigger(TriggerConfig.new(kind)).action(action).build()


static func _ability_config(config_id: String, components: Array[AbilityComponentConfig]) -> AbilityConfig:
	var builder := AbilityConfig.builder().config_id(config_id)
	for component in components:
		builder.component_config(component)
	return builder.build()


## grant 一个监听 KIND、触发时记下 label 的 ability。
static func _grant_label(actor: DispatchActor, label: String) -> Ability:
	var ability := Ability.new(_ability_config("label_" + label, [
		_no_instance(KIND, AppendLabelAction.new(label)),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	return ability


static func _registration_count(instance: GameplayInstance, kind: String) -> int:
	return (instance.event_processor._post_handlers.get(kind, []) as Array).size()


## 派发一条 kind 事件，返回 action 记下的 label（按派发顺序）。
static func _dispatch(instance: GameplayInstance, kind: String = KIND) -> Array[String]:
	var event := {"kind": kind, "log": []}
	instance.event_processor.process_post_event(event)
	var labels: Array[String] = []
	labels.assign(event["log"])
	return labels
