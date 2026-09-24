extends Node

## Post 事件订阅派发合同
##
## 观众由注册决定：Ability.apply_effects 按 component 的 trigger kind 各注册一条 PostHandlerRegistration、
## remove_effects 注销；死活由 actor 决定：派发时按 id 重建 context，先问 owner 的 is_event_responsive。
## 本文件钉住：同 kind 只注册一条、内置 ABILITY_ACTIVATE / GRANTED_SELF 是 direct trigger 不注册且按地址恰送达一次、派发顺序（registry 顺序 → grant 顺序）、
## revoke / expire / remove_actor / end() 注销、响应钩子与豁免、Break 短路、嵌套派发的深度上限、triggered 监听者只回调一次、
## on_apply 里过期即停止 apply 且不注册、注册的 owner 取所在 AbilitySet 的 owner；
## event_filter 两段式：带 event_filter 的登记在重建 context 之前判（不问 is_event_responsive）、同 kind 混合声明退回全派但 event_filter
## 仍在 match 里生效、并集语义、通过 event_filter 后死活门照旧、定向投递也按 event_filter 判。
## 寄给单个 ability 实例的回复（EventProcessor.deliver_to_ability + TriggerConfig.direct()）：direct trigger 不进广播注册表、
## 只在定向通道触发、同 kind 广播 trigger 只在广播通道触发；不问死活门（filter 自己拒）；收件人不在了静默丢弃；
## 投递内 expire 当场 revoke；嵌套投递受深度上限。

const LogCounter := preload("res://addons/logic-game-framework/tests/log_counter.gd")

const KIND := "post_dispatch_probe"
const DEATH_KIND := "post_dispatch_death"


## 可调响应策略的 BattleActor：死后只响应 exempt_when_dead 里的 post kind（亡语式豁免）。
## responsive_queries 数 is_event_responsive 被问的次数：被 event_filter 跳过的登记不会问到这里。
class DispatchActor:
	extends BattleActor

	var ability_set: AbilitySet
	var exempt_when_dead: Array[String] = []
	var responsive_queries := 0

	func _init() -> void:
		type = "post_dispatch_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set

	func is_event_responsive(event_dict: Dictionary, phase: String) -> bool:
		responsive_queries += 1
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


## 记一笔后把同一个事件再寄回本 ability 实例一次（定向投递的嵌套深度探针）。
class RedeliverAction:
	extends Action.BaseAction

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(ctx: ExecutionContext) -> ActionResult:
		var event := ctx.get_original_event()
		(event["log"] as Array).append("depth")
		ctx.instance.event_processor.deliver_to_ability(event, ctx.ability_ref.owner_actor_id, ctx.ability_ref.id)
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


## post 触发的 action 里让所属 ability 过期（一次性被动的形状：触发一次即消耗）。
class ExpireSelfAction:
	extends Action.BaseAction

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(ctx: ExecutionContext) -> ActionResult:
		ctx.ability_ref.resolve().expire("post_dispatch_consumed")
		return ActionResult.create_success_result([])


func _init() -> void:
	TestFramework.register_test("PostDispatch: same kind on two components registers once, both run", _test_one_registration_per_kind)
	TestFramework.register_test("PostDispatch: built-in activate / granted triggers never register, each delivered once by address", _test_direct_delivery_kinds)
	TestFramework.register_test("PostDispatch: order follows registry order then grant order", _test_dispatch_order)
	TestFramework.register_test("PostDispatch: revoke and expire unregister", _test_revoke_and_expire_unregister)
	TestFramework.register_test("PostDispatch: remove_actor and end() clear registrations", _test_remove_actor_and_end_clear)
	TestFramework.register_test("PostDispatch: unresponsive owner skipped, exempt kind still delivered", _test_responsiveness_gate)
	TestFramework.register_test("PostDispatch: disabled ability skipped", _test_disabled_ability_skipped)
	TestFramework.register_test("PostDispatch: nested dispatch stops at max_depth", _test_nested_dispatch_depth)
	TestFramework.register_test("PostDispatch: triggered listener fires once with component names", _test_triggered_listener_once)
	TestFramework.register_test("PostDispatch: ability expired during on_apply stops applying and registers nothing", _test_expired_during_apply_stops_applying)
	TestFramework.register_test("PostDispatch: registration owner is the ability set's owner", _test_registration_owner_follows_ability_set)
	TestFramework.register_test("PostDispatch: ability expired inside its own handler is revoked in the same dispatch", _test_expired_in_handler_revoked_immediately)
	TestFramework.register_test("PostDispatch: event_filter rejects before the context is rebuilt", _test_event_filter_skips_before_context)
	TestFramework.register_test("PostDispatch: a kind with a event_filter-less trigger falls back to full dispatch, event_filter still matches", _test_event_filter_mixed_kind_falls_back)
	TestFramework.register_test("PostDispatch: event_filters of one kind across components form a union", _test_event_filter_union_across_components)
	TestFramework.register_test("PostDispatch: a passed event_filter still goes through the responsiveness gate", _test_event_filter_then_responsive_gate)
	TestFramework.register_test("PostDispatch: direct delivery evaluates the event_filter inside the trigger match", _test_event_filter_in_direct_delivery)
	TestFramework.register_test("DeliverToAbility: a direct trigger never registers, hears its own delivery, ignores the broadcast", _test_direct_trigger_channel)
	TestFramework.register_test("DeliverToAbility: a broadcast trigger of the same kind hears the broadcast, ignores the delivery", _test_broadcast_trigger_ignores_delivery)
	TestFramework.register_test("DeliverToAbility: a dead owner is still delivered to, the gate is never asked, a filter can refuse", _test_direct_delivery_skips_responsiveness_gate)
	TestFramework.register_test("DeliverToAbility: a missing recipient is dropped silently", _test_direct_delivery_missing_recipient)
	TestFramework.register_test("DeliverToAbility: an ability expired inside its delivery is revoked in the same delivery", _test_direct_delivery_expire_revokes)
	TestFramework.register_test("DeliverToAbility: nested delivery stops at max_depth", _test_direct_delivery_depth)


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


## 内置 ABILITY_ACTIVATE / GRANTED_SELF 是 direct trigger，永不注册：grant 把 AbilityGranted 只寄给新实例让 GRANTED_SELF 恰好
## 激活一次；激活请求按地址寄给 active 恰好激活一次，寄错地址（不存在的实例）返回 false、谁也不激活。
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

	TestFramework.assert_equal(0, _registration_count(instance, GameEvent.ABILITY_ACTIVATE_EVENT))
	TestFramework.assert_equal(0, _registration_count(instance, GameEvent.ABILITY_GRANTED_EVENT))
	TestFramework.assert_equal(1, granted.get_executing_instances().size())
	TestFramework.assert_equal(0, active.get_executing_instances().size())
	var request := GameEvent.AbilityActivate.create(active.id, actor.get_id()).to_dict()
	TestFramework.assert_false(instance.event_processor.deliver_to_ability(request, actor.get_id(), "nobody"))
	TestFramework.assert_equal(0, active.get_executing_instances().size())
	TestFramework.assert_true(instance.event_processor.deliver_to_ability(request, actor.get_id(), active.id))
	TestFramework.assert_equal(1, active.get_executing_instances().size())
	TestFramework.assert_equal(1, granted.get_executing_instances().size())
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


## triggered 监听者（录像 ability_triggered 的来源）：一次派发只回调一次，带全部被触发 component 的名字。
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


## component 的 on_apply 让本 ability 过期（remove_effects 已跑完）：apply_effects 就此停下，排在后面的
## component 不再 apply（这里的 PreEvent 不注册 pre handler），post handler 也不注册——做了就没有人撤销。
func _test_expired_during_apply_stops_applying() -> void:
	var instance := _create_instance("post_dispatch_expire_on_apply")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("expire_on_apply", [
		ExpireOnApplyConfig.new(),
		PreEventConfig.new(KIND, func(_mutable: MutableEvent, _ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.pass_intent()),
		_no_instance(KIND, AppendLabelAction.new("never")),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)

	TestFramework.assert_true(ability.is_expired())
	TestFramework.assert_equal(0, (instance.event_processor._pre_handlers.get(KIND, []) as Array).size())
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	TestFramework.assert_true(ability._post_unregisters.is_empty())
	GameWorld.destroy_instance(instance.id)


## 注册的 owner 与 PreEventComponent 同取 context 的 owner（所在 AbilitySet 的 owner）：派发按它找回 ability，
## remove_actor 按它注销。Ability 自己那份 owner 由 set 在 grant 时盖章：构造时留空即填 set 的 owner（source 同步补齐，
## 显式给的 source 保留），于是 on_remove / 叠层 / Break 的 for_ability 与 execution 的 AbilityRef 反查到同一个 owner。
func _test_registration_owner_follows_ability_set() -> void:
	var instance := _create_instance("post_dispatch_owner")
	var actor := _spawn(instance)
	var stamped := Ability.new(_ability_config("owner_from_set", [
		_no_instance(KIND, AppendLabelAction.new("heard")),
	]), "")
	actor.ability_set.grant_ability(stamped)
	var no_components: Array[AbilityComponentConfig] = []
	var sourced := Ability.new(_ability_config("owner_from_set_sourced", no_components), "", "post_dispatch_caster")
	actor.ability_set.grant_ability(sourced)

	TestFramework.assert_equal(actor.get_id(), stamped.owner_actor_id)
	TestFramework.assert_equal(actor.get_id(), stamped.source_actor_id)
	TestFramework.assert_equal(actor.get_id(), sourced.owner_actor_id)
	TestFramework.assert_equal("post_dispatch_caster", sourced.source_actor_id)
	TestFramework.assert_equal(["heard"], _dispatch(instance))
	instance.remove_actor(actor.get_id())
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	GameWorld.destroy_instance(instance.id)


## 一次性被动：post 触发的 action 里 expire 自己 → 本次派发内当场除名（与 tick / 定向投递经 _process_abilities 的清扫对称），
## 不等 owner 的下一次 tick：名单里已没有它、abilityRevoked 恰一次（reason = expired、expire_reason 原样）、注册已清。
func _test_expired_in_handler_revoked_immediately() -> void:
	var instance := _create_instance("post_dispatch_expire_in_handler")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("expire_in_handler", [
		_no_instance(KIND, AppendLabelAction.new("consumed")),
		_no_instance(KIND, ExpireSelfAction.new()),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	var revoked: Array = []
	actor.ability_set.on_ability_revoked(func(revoked_ability: Ability, reason: String, _set: AbilitySet, expire_reason: String) -> void:
		revoked.append([revoked_ability.id, reason, expire_reason]))

	TestFramework.assert_equal(["consumed"], _dispatch(instance))
	TestFramework.assert_true(ability.is_expired())
	TestFramework.assert_true(actor.ability_set.find_ability_by_id(ability.id) == null, "过期的 ability 应在本次派发内离开名单")
	TestFramework.assert_equal(0, actor.ability_set.get_ability_count())
	TestFramework.assert_equal([[ability.id, AbilitySet.REVOKE_REASON_EXPIRED, "post_dispatch_consumed"]], revoked)
	TestFramework.assert_equal(0, _registration_count(instance, KIND))
	GameWorld.destroy_instance(instance.id)


## event_filter 只看事件 + 三个 id，在重建 context 之前判：不是发给我的事件连 is_event_responsive 都不问；
## 通过的照常重建 context、跑 trigger、触发。登记条数不变——观众仍由注册决定，event_filter 只是让站长叫人前先看一眼。
func _test_event_filter_skips_before_context() -> void:
	var instance := _create_instance("post_dispatch_event_filter")
	var actor_a := _spawn(instance)
	var actor_b := _spawn(instance)
	_grant_event_filtered(actor_a, "A", _source_is_owner)
	_grant_event_filtered(actor_b, "B", _source_is_owner)
	TestFramework.assert_equal(2, _registration_count(instance, KIND))

	TestFramework.assert_equal(["A"], _dispatch_with(instance, {"source": actor_a.get_id()}))
	TestFramework.assert_equal(1, actor_a.responsive_queries)
	TestFramework.assert_equal(0, actor_b.responsive_queries)
	TestFramework.assert_equal([], _dispatch_with(instance, {"source": "nobody"}))
	TestFramework.assert_equal(1, actor_a.responsive_queries)
	TestFramework.assert_equal(0, actor_b.responsive_queries)
	GameWorld.destroy_instance(instance.id)


## 同 kind 有 trigger 没带 event_filter：登记不预筛（事件可能经那条 trigger 触发），context 照常重建；
## 带 event_filter 的 component 在 match_single_trigger 里仍按 event_filter 判，不因退回全派而放宽。
func _test_event_filter_mixed_kind_falls_back() -> void:
	var instance := _create_instance("post_dispatch_event_filter_mixed")
	var actor := _spawn(instance)
	actor.ability_set.grant_ability(Ability.new(_ability_config("mixed", [
		_no_instance_event_filtered(KIND, _source_is_owner, AppendLabelAction.new("mine")),
		_no_instance(KIND, AppendLabelAction.new("any")),
	]), actor.get_id()))
	var registration: PostHandlerRegistration = (instance.event_processor._post_handlers[KIND] as Array)[0]
	TestFramework.assert_true(registration.event_filters.is_empty(), "a mixed kind registers without event_filters")

	TestFramework.assert_equal(["any"], _dispatch_with(instance, {"source": "nobody"}))
	TestFramework.assert_equal(1, actor.responsive_queries)
	TestFramework.assert_equal(["mine", "any"], _dispatch_with(instance, {"source": actor.get_id()}))
	GameWorld.destroy_instance(instance.id)


## 同 kind 的 event_filter 取并集：两个 component 各认 source / target，登记两条 event_filter，任一通过才叫人；
## 叫到之后各 component 仍只按自己的 trigger 触发。
func _test_event_filter_union_across_components() -> void:
	var instance := _create_instance("post_dispatch_event_filter_union")
	var actor := _spawn(instance)
	actor.ability_set.grant_ability(Ability.new(_ability_config("union", [
		_no_instance_event_filtered(KIND, _source_is_owner, AppendLabelAction.new("shot")),
		_no_instance_event_filtered(KIND, _target_is_owner, AppendLabelAction.new("hit")),
	]), actor.get_id()))
	var registration: PostHandlerRegistration = (instance.event_processor._post_handlers[KIND] as Array)[0]
	TestFramework.assert_equal(2, registration.event_filters.size())

	TestFramework.assert_equal(["hit"], _dispatch_with(instance, {"source": "nobody", "target": actor.get_id()}))
	TestFramework.assert_equal(["shot"], _dispatch_with(instance, {"source": actor.get_id(), "target": "nobody"}))
	TestFramework.assert_equal([], _dispatch_with(instance, {"source": "nobody", "target": "nobody"}))
	TestFramework.assert_equal(2, actor.responsive_queries)
	GameWorld.destroy_instance(instance.id)


## event_filter 通过后照旧问 is_event_responsive：死者自家的事件仍被死活门拦下（观众由注册决定、死活由 actor 决定不变）。
func _test_event_filter_then_responsive_gate() -> void:
	var instance := _create_instance("post_dispatch_event_filter_gate")
	var actor := _spawn(instance)
	_grant_event_filtered(actor, "mine", _source_is_owner)
	actor.mark_dead()
	TestFramework.assert_equal([], _dispatch_with(instance, {"source": actor.get_id()}))
	TestFramework.assert_equal(1, actor.responsive_queries)
	GameWorld.destroy_instance(instance.id)


## 定向投递没有 processor 预筛，direct trigger 带的 event_filter 在 match_single_trigger 里照样求值：不过不触发、过了恰触发一次。
func _test_event_filter_in_direct_delivery() -> void:
	var instance := _create_instance("post_dispatch_event_filter_direct")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("event_filter_direct", [
		NoInstanceConfig.builder()
			.trigger(TriggerConfig.new(KIND).event_filter(_source_is_owner).direct())
			.action(AppendLabelAction.new("mine"))
			.build(),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	TestFramework.assert_equal(0, _registration_count(instance, KIND))

	TestFramework.assert_equal([], _deliver_with(instance, actor.get_id(), ability.id, {"source": "someone_else"}))
	TestFramework.assert_equal(["mine"], _deliver_with(instance, actor.get_id(), ability.id, {"source": actor.get_id()}))
	GameWorld.destroy_instance(instance.id)


## direct trigger 不进广播注册表：同 kind 的广播到不了它；deliver_to_ability 寄给谁谁触发，同 owner 的另一个 ability 不沾边。
func _test_direct_trigger_channel() -> void:
	var instance := _create_instance("deliver_channel")
	var actor := _spawn(instance)
	var receiver := _grant_direct(actor, "mine")
	var neighbour := _grant_direct(actor, "theirs")
	TestFramework.assert_equal(0, _registration_count(instance, KIND))

	TestFramework.assert_equal([], _dispatch(instance))
	TestFramework.assert_equal(["mine"], _deliver(instance, actor.get_id(), receiver.id))
	TestFramework.assert_equal(["theirs"], _deliver(instance, actor.get_id(), neighbour.id))
	GameWorld.destroy_instance(instance.id)


## 同一 ability 对同 kind 既有 direct 又有广播 trigger：kind 只因广播那条注册一次；广播只触发广播那条、定向只触发 direct 那条。
func _test_broadcast_trigger_ignores_delivery() -> void:
	var instance := _create_instance("deliver_mixed_channels")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("mixed_channels", [
		_no_instance_direct(KIND, AppendLabelAction.new("direct")),
		_no_instance(KIND, AppendLabelAction.new("broadcast")),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	TestFramework.assert_equal(1, _registration_count(instance, KIND))

	TestFramework.assert_equal(["broadcast"], _dispatch(instance))
	TestFramework.assert_equal(["direct"], _deliver(instance, actor.get_id(), ability.id))
	GameWorld.destroy_instance(instance.id)


## 定向投递不问死活门：owner 死了照样送达、is_event_responsive 一次都没被问；「人死弹灭」由 direct trigger 的 filter 自己拒。
func _test_direct_delivery_skips_responsiveness_gate() -> void:
	var instance := _create_instance("deliver_dead_owner")
	var actor := _spawn(instance)
	var always := _grant_direct(actor, "always")
	var alive_only := Ability.new(_ability_config("direct_alive_only", [
		_no_instance_direct(KIND, AppendLabelAction.new("alive_only"), _owner_alive),
	]), actor.get_id())
	actor.ability_set.grant_ability(alive_only)

	actor.mark_dead()
	TestFramework.assert_equal(["always"], _deliver(instance, actor.get_id(), always.id))
	TestFramework.assert_equal([], _deliver(instance, actor.get_id(), alive_only.id))
	TestFramework.assert_equal(0, actor.responsive_queries)
	actor.set_death_latch(false)
	TestFramework.assert_equal(["alive_only"], _deliver(instance, actor.get_id(), alive_only.id))
	GameWorld.destroy_instance(instance.id)


## 收件人不在了：错的实例 id、已 revoke 的 ability、已 remove 的 owner——都返回 false、不报错、深度归零。
func _test_direct_delivery_missing_recipient() -> void:
	var instance := _create_instance("deliver_missing_recipient")
	var actor := _spawn(instance)
	var ability := _grant_direct(actor, "gone")
	var log_counter := LogCounter.new()
	OS.add_logger(log_counter)

	TestFramework.assert_false(instance.event_processor.deliver_to_ability({"kind": KIND, "log": []}, actor.get_id(), "nobody"))
	actor.ability_set.revoke_ability(ability.id)
	TestFramework.assert_false(instance.event_processor.deliver_to_ability({"kind": KIND, "log": []}, actor.get_id(), ability.id))
	instance.remove_actor(actor.get_id())
	TestFramework.assert_false(instance.event_processor.deliver_to_ability({"kind": KIND, "log": []}, actor.get_id(), ability.id))
	OS.remove_logger(log_counter)
	TestFramework.assert_equal(0, log_counter.errors)
	TestFramework.assert_equal(0, instance.event_processor.get_current_depth())
	GameWorld.destroy_instance(instance.id)


## 一次性回复：收件 ability 在 action 里 expire 自己 → 本次投递内当场除名、abilityRevoked 恰一次，再寄就没人收。
func _test_direct_delivery_expire_revokes() -> void:
	var instance := _create_instance("deliver_expire")
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("direct_expire", [
		_no_instance_direct(KIND, AppendLabelAction.new("consumed")),
		_no_instance_direct(KIND, ExpireSelfAction.new()),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	var revoked: Array = []
	actor.ability_set.on_ability_revoked(func(revoked_ability: Ability, reason: String, _set: AbilitySet, expire_reason: String) -> void:
		revoked.append([revoked_ability.id, reason, expire_reason]))

	TestFramework.assert_equal(["consumed"], _deliver(instance, actor.get_id(), ability.id))
	TestFramework.assert_true(actor.ability_set.find_ability_by_id(ability.id) == null, "过期的 ability 应在本次投递内离开名单")
	TestFramework.assert_equal([[ability.id, AbilitySet.REVOKE_REASON_EXPIRED, "post_dispatch_consumed"]], revoked)
	TestFramework.assert_equal([], _deliver(instance, actor.get_id(), ability.id))
	GameWorld.destroy_instance(instance.id)


## action 里再把同一事件寄回自己：到 max_depth 停下、报一条深度超限错误、深度计数归零。
func _test_direct_delivery_depth() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("deliver_depth", EventProcessorConfig.new(3)))
	var actor := _spawn(instance)
	var ability := Ability.new(_ability_config("direct_redeliver", [
		_no_instance_direct(KIND, RedeliverAction.new()),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)

	var log_counter := LogCounter.new()
	OS.add_logger(log_counter)
	var labels := _deliver(instance, actor.get_id(), ability.id)
	OS.remove_logger(log_counter)
	TestFramework.assert_equal(3, labels.size())
	TestFramework.assert_equal(1, log_counter.errors)
	TestFramework.assert_equal(0, instance.event_processor.get_current_depth())
	GameWorld.destroy_instance(instance.id)


# ========== 夹具 ==========

static func _create_instance(instance_id: String) -> GameplayInstance:
	return GameWorld.create_instance(GameplayInstance.new(instance_id))


static func _spawn(instance: GameplayInstance) -> DispatchActor:
	return instance.add_actor(DispatchActor.new()) as DispatchActor


static func _no_instance(kind: String, action: Action.BaseAction) -> NoInstanceConfig:
	return NoInstanceConfig.builder().trigger(TriggerConfig.new(kind)).action(action).build()


static func _no_instance_event_filtered(kind: String, event_filter: Callable, action: Action.BaseAction) -> NoInstanceConfig:
	return NoInstanceConfig.builder().trigger(TriggerConfig.new(kind).event_filter(event_filter)).action(action).build()


## event_filter：事件的 source 是本 owner（「是不是我射的」的形状）
static func _source_is_owner(event_dict: Dictionary, h: HandlerContext) -> bool:
	return str(event_dict.get("source", "")) == h.owner_id


## event_filter：事件的 target 是本 owner（「是不是打中我」的形状）
static func _target_is_owner(event_dict: Dictionary, h: HandlerContext) -> bool:
	return str(event_dict.get("target", "")) == h.owner_id


## grant 一个监听 KIND、带 event_filter、触发时记下 label 的 ability。
static func _grant_event_filtered(actor: DispatchActor, label: String, event_filter: Callable) -> Ability:
	var ability := Ability.new(_ability_config("event_filter_" + label, [
		_no_instance_event_filtered(KIND, event_filter, AppendLabelAction.new(label)),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	return ability


## 派发一条带额外字段的 KIND 事件，返回 action 记下的 label。
static func _dispatch_with(instance: GameplayInstance, fields: Dictionary) -> Array[String]:
	var event := {"kind": KIND, "log": []}
	event.merge(fields)
	instance.event_processor.process_post_event(event)
	var labels: Array[String] = []
	labels.assign(event["log"])
	return labels


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


## 只收定向投递的 NoInstance 组件；filter 可选（Callable() = 不挂）。
static func _no_instance_direct(kind: String, action: Action.BaseAction, filter: Callable = Callable()) -> NoInstanceConfig:
	return NoInstanceConfig.builder().trigger(TriggerConfig.new(kind, filter).direct()).action(action).build()


## grant 一个只收定向投递的 KIND、触发时记下 label 的 ability。
static func _grant_direct(actor: DispatchActor, label: String) -> Ability:
	var ability := Ability.new(_ability_config("direct_" + label, [
		_no_instance_direct(KIND, AppendLabelAction.new(label)),
	]), actor.get_id())
	actor.ability_set.grant_ability(ability)
	return ability


## filter：owner 活着才收（「人死弹灭」的形状；定向投递不问死活门，这条由 trigger 自己声明）
static func _owner_alive(_event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var owner := GameWorld.get_actor(ctx.owner_actor_id) as BattleActor
	return owner != null and not owner.is_dead()


## 把一条 KIND 事件寄给 owner 的 ability 实例，返回 action 记下的 label。
static func _deliver(instance: GameplayInstance, owner_id: String, ability_id: String) -> Array[String]:
	var event := {"kind": KIND, "log": []}
	instance.event_processor.deliver_to_ability(event, owner_id, ability_id)
	var labels: Array[String] = []
	labels.assign(event["log"])
	return labels


## 把一条带额外字段的 KIND 事件寄给 owner 的 ability 实例，返回 action 记下的 label。
static func _deliver_with(instance: GameplayInstance, owner_id: String, ability_id: String, fields: Dictionary) -> Array[String]:
	var event := {"kind": KIND, "log": []}
	event.merge(fields)
	instance.event_processor.deliver_to_ability(event, owner_id, ability_id)
	var labels: Array[String] = []
	labels.assign(event["log"])
	return labels
