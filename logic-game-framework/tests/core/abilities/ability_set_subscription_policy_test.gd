extends Node

## AbilitySet.subscription_policy：持有者一侧的订阅策略。
##
## DIRECT_ONLY 的技能集在 grant 时拒绝任何广播订阅（非 direct 的 post trigger、PreEvent）：断言、不 grant、不登记、
## 不通知 granted 监听者；只收定向投递的 ability 照常 grant 并能收到寄给它的事件。BROADCAST_ALLOWED（默认）照旧。
## 「一个持有者成十上百份」的 actor（单位 / 成员）靠它保证广播登记数不随持有者数涨：条件是回调、处理器不能索引，
## 登记数就是每条事件的派发成本。每条被拒的 grant 是一条刻意触发的断言（TestFramework.expect_script_errors）。

const KIND := "subscription_policy_probe"
const PRE_KIND := "subscription_policy_pre_probe"


class PolicyActor:
	extends BattleActor

	var ability_set: AbilitySet

	func _init() -> void:
		type = "subscription_policy_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set


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


func _init() -> void:
	TestFramework.register_test("SubscriptionPolicy: BROADCAST_ALLOWED (default) grants a broadcast subscriber", _test_default_allows_broadcast)
	TestFramework.register_test("SubscriptionPolicy: DIRECT_ONLY refuses a broadcast post trigger", _test_direct_only_refuses_post_trigger)
	TestFramework.register_test("SubscriptionPolicy: DIRECT_ONLY refuses a PreEvent", _test_direct_only_refuses_pre_event)
	TestFramework.register_test("SubscriptionPolicy: DIRECT_ONLY grants a direct-only ability and delivers to it", _test_direct_only_grants_direct_ability)
	TestFramework.register_test("SubscriptionPolicy: broadcast_subscription_kinds lists post and pre kinds, never direct", _test_broadcast_subscription_kinds)


func _test_default_allows_broadcast() -> void:
	var instance := _create_instance("subscription_policy_default")
	var actor := _spawn(instance)
	TestFramework.assert_equal(AbilitySet.SubscriptionPolicy.BROADCAST_ALLOWED, actor.ability_set.subscription_policy)
	actor.ability_set.grant_ability(Ability.new(_broadcast_config("listener"), actor.get_id()))
	TestFramework.assert_equal(1, actor.ability_set.get_ability_count())
	TestFramework.assert_equal(1, _post_count(instance, KIND))
	TestFramework.assert_equal(["listener"], _dispatch(instance))
	GameWorld.destroy_instance(instance.id)


## 广播 post trigger 被拒：不进技能集、不登记、granted 监听者收不到；同一 set 随后仍能 grant 别的。
func _test_direct_only_refuses_post_trigger() -> void:
	TestFramework.expect_script_errors(1)
	var instance := _create_instance("subscription_policy_refuse_post")
	var actor := _spawn(instance)
	actor.ability_set.subscription_policy = AbilitySet.SubscriptionPolicy.DIRECT_ONLY
	var granted: Array[String] = []
	actor.ability_set.on_ability_granted(func(ability: Ability, _set: AbilitySet) -> void: granted.append(ability.config_id))

	actor.ability_set.grant_ability(Ability.new(_broadcast_config("listener"), actor.get_id()))
	TestFramework.assert_equal(0, actor.ability_set.get_ability_count())  # 被拒的 ability 不进技能集
	TestFramework.assert_equal(0, _post_count(instance, KIND))  # 被拒的 ability 没有登记 post handler
	TestFramework.assert_equal([], granted)  # 被拒的 grant 不通知 granted 监听者
	TestFramework.assert_equal([], _dispatch(instance))

	actor.ability_set.grant_ability(Ability.new(_direct_config("direct"), actor.get_id()))
	TestFramework.assert_equal(1, actor.ability_set.get_ability_count())  # 同一 set 随后仍能 grant 只收定向投递的 ability
	TestFramework.assert_equal(["direct"], granted)
	GameWorld.destroy_instance(instance.id)


## PreEvent 只有广播这一条通道，DIRECT_ONLY 同样拒绝。
func _test_direct_only_refuses_pre_event() -> void:
	TestFramework.expect_script_errors(1)
	var instance := _create_instance("subscription_policy_refuse_pre")
	var actor := _spawn(instance)
	actor.ability_set.subscription_policy = AbilitySet.SubscriptionPolicy.DIRECT_ONLY

	actor.ability_set.grant_ability(Ability.new(_pre_event_config("modifier"), actor.get_id()))
	TestFramework.assert_equal(0, actor.ability_set.get_ability_count())  # 带 PreEvent 的 ability 不进技能集
	TestFramework.assert_equal(0, _pre_count(instance, PRE_KIND))  # 被拒的 ability 没有登记 pre handler
	var mutable := instance.event_processor.process_pre_event({"kind": PRE_KIND, "damage": 100})
	TestFramework.assert_near(100.0, float(mutable.get_current_value("damage")), 0.0001, "没人改事件")
	GameWorld.destroy_instance(instance.id)


## 只收定向投递的 ability（内置激活 trigger + direct 的自定义 trigger）照常 grant、不进广播注册表、能收到寄给它的事件。
func _test_direct_only_grants_direct_ability() -> void:
	var instance := _create_instance("subscription_policy_direct")
	var actor := _spawn(instance)
	actor.ability_set.subscription_policy = AbilitySet.SubscriptionPolicy.DIRECT_ONLY
	var ability := Ability.new(_direct_config("mine"), actor.get_id())
	actor.ability_set.grant_ability(ability)
	TestFramework.assert_equal(1, actor.ability_set.get_ability_count())
	TestFramework.assert_equal(0, _post_count(instance, KIND))  # direct trigger 不进广播注册表

	var event := {"kind": KIND, "log": []}
	instance.event_processor.deliver_to_ability(event, actor.get_id(), ability.id)
	TestFramework.assert_equal(["mine"], event["log"])  # 寄给它的事件照常触发
	TestFramework.assert_equal([], _dispatch(instance))  # 同 kind 的广播到不了它
	GameWorld.destroy_instance(instance.id)


func _test_broadcast_subscription_kinds() -> void:
	var mixed := Ability.new(AbilityConfig.builder().config_id("mixed")
		.component_config(NoInstanceConfig.builder()
			.trigger(TriggerConfig.new(KIND).event_filter(_always))
			.trigger(TriggerConfig.new("other_direct").direct())
			.action(AppendLabelAction.new("mixed"))
			.build())
		.component_config(PreEventConfig.new(PRE_KIND, _pass_through))
		.build(), "")
	TestFramework.assert_equal([KIND, PRE_KIND], mixed.broadcast_subscription_kinds())  # post 与 pre 的广播 kind 都在，direct 的不在
	TestFramework.assert_equal([], Ability.new(_direct_config("direct"), "").broadcast_subscription_kinds())  # 只有 direct trigger 的 ability 为空
	TestFramework.assert_equal([KIND], Ability.new(_broadcast_config("listener"), "").broadcast_subscription_kinds())


# ========== 夹具 ==========

static func _create_instance(instance_id: String) -> GameplayInstance:
	return GameWorld.create_instance(GameplayInstance.new(instance_id))


static func _spawn(instance: GameplayInstance) -> PolicyActor:
	return instance.add_actor(PolicyActor.new()) as PolicyActor


## 广播订阅 KIND 的 ability（带 event_filter 也一样是广播订阅）。
static func _broadcast_config(config_id: String) -> AbilityConfig:
	return AbilityConfig.builder().config_id(config_id).component_config(
		NoInstanceConfig.builder().trigger(TriggerConfig.new(KIND).event_filter(_always)).action(AppendLabelAction.new(config_id)).build()
	).build()


## 只收定向投递的 ability：内置激活 trigger + direct 的 KIND trigger。
static func _direct_config(config_id: String) -> AbilityConfig:
	return AbilityConfig.builder().config_id(config_id).component_config(
		NoInstanceConfig.builder().trigger(TriggerConfig.ABILITY_ACTIVATE).trigger(TriggerConfig.new(KIND).direct()).action(AppendLabelAction.new(config_id)).build()
	).build()


static func _pre_event_config(config_id: String) -> AbilityConfig:
	return AbilityConfig.builder().config_id(config_id).component_config(PreEventConfig.new(PRE_KIND, _pass_through)).build()


static func _always(_event_dict: Dictionary, _me: HandlerContext) -> bool:
	return true


static func _pass_through(_mutable: MutableEvent, _ctx: AbilityLifecycleContext) -> Intent:
	return EventPhase.pass_intent()


static func _post_count(instance: GameplayInstance, kind: String) -> int:
	return (instance.event_processor._post_handlers.get(kind, []) as Array).size()


static func _pre_count(instance: GameplayInstance, kind: String) -> int:
	return (instance.event_processor._pre_handlers.get(kind, []) as Array).size()


## 广播一条 KIND 事件，返回 action 记下的 label。
static func _dispatch(instance: GameplayInstance) -> Array[String]:
	var event := {"kind": KIND, "log": []}
	instance.event_processor.process_post_event(event)
	var labels: Array[String] = []
	labels.assign(event["log"])
	return labels
