extends Node

## GameplayInstance 上下文合同
##
## context 里的 instance 一律按 owner 的 actor id 反查（GameWorld.get_instance_of_actor），
## 不经调用链递、不缓存。逐个钉住填充点都拿到 owner 所属的那个 instance：
## AbilitySet 派发（trigger filter / NoInstance action）、NoInstance lifecycle（on_apply 用
## AbilitySet 建的 context、on_remove 用 Ability 自建的 context）、execution 的 start / tag /
## cancel action（cancel 由 revoke 触发，调用方什么也不递）、PreEvent handler 的重建 context；
## owner 没注册时老实给 null——而 grant 照样恒投递 AbilityGranted，GRANTED_SELF 照样自激活。

const PROBE_KIND := "instance_context_probe"
const PRE_KIND := "instance_context_pre"
const NO_INSTANCE := "<null>"


class ProbeActor:
	extends BattleActor

	var ability_set: AbilitySet
	## lifecycle action 的事件链起点是 core 内部建的 dict，测试握不到——改记到 owner 身上。
	var seen: Dictionary = {}

	func _init() -> void:
		type = "instance_context_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set


## 把 ctx.instance 的 id 写进原始触发事件（事件链起点就是测试握着的那个 dict）。
## 只记 id 不记引用：测试长期持有这个 dict，存 instance 会平白延长它的生命周期。
class RecordToEventAction:
	extends Action.BaseAction

	var key: String

	func _init(p_key: String) -> void:
		super._init(TargetSelector.new())
		key = p_key

	func execute(ctx: ExecutionContext) -> ActionResult:
		var event := ctx.get_original_event()
		event[key] = ctx.instance.id if ctx.instance != null else NO_INSTANCE
		return ActionResult.create_success_result([])


## 把 ctx.instance 的 id 记到 owner actor 的 seen 上（给握不到事件 dict 的 lifecycle 路径用）。
class RecordToOwnerAction:
	extends Action.BaseAction

	var key: String

	func _init(p_key: String) -> void:
		super._init(TargetSelector.new())
		key = p_key

	func execute(ctx: ExecutionContext) -> ActionResult:
		var probe_actor := GameWorld.get_actor(ctx.ability_ref.owner_actor_id) as ProbeActor
		probe_actor.seen[key] = ctx.instance.id if ctx.instance != null else NO_INSTANCE
		return ActionResult.create_success_result([])


func _init() -> void:
	TestFramework.register_test("Instance: dispatch context and NoInstance action see owner instance", _test_dispatch_sees_owner_instance)
	TestFramework.register_test("Instance: lifecycle actions see owner instance on apply and remove", _test_lifecycle_sees_owner_instance)
	TestFramework.register_test("Instance: execution start/tag/cancel actions resolve owner instance", _test_execution_sees_owner_instance)
	TestFramework.register_test("Instance: pre handler context sees owner instance", _test_pre_handler_sees_owner_instance)
	TestFramework.register_test("Instance: unregistered owner gets null yet grant still self-activates", _test_unregistered_owner)


func _test_dispatch_sees_owner_instance() -> void:
	var actor := _spawn("instance_ctx_dispatch")
	var config := (AbilityConfig.builder()
		.config_id("instance_ctx_dispatch")
		.component_config(NoInstanceConfig.builder()
			.trigger(TriggerConfig.new(PROBE_KIND, _filter_recording_instance("filter_instance")))
			.action(RecordToEventAction.new("action_instance"))
			.build())
		.build())
	actor.ability_set.grant_ability(Ability.new(config, actor.get_id()))

	var probe := {"kind": PROBE_KIND}
	actor.ability_set.receive_event(probe)
	var expected := actor.get_gameplay_instance_id()
	TestFramework.assert_equal(expected, probe.get("filter_instance", ""))
	TestFramework.assert_equal(expected, probe.get("action_instance", ""))
	GameWorld.destroy_instance(expected)


func _test_lifecycle_sees_owner_instance() -> void:
	var actor := _spawn("instance_ctx_lifecycle")
	var apply_actions: Array[Action.BaseAction] = [RecordToOwnerAction.new("apply_instance")]
	var remove_actions: Array[Action.BaseAction] = [RecordToOwnerAction.new("remove_instance")]
	var config := (AbilityConfig.builder()
		.config_id("instance_ctx_lifecycle")
		.component_config(NoInstanceConfig.builder()
			.on_apply_actions(apply_actions)
			.on_remove_actions(remove_actions)
			.build())
		.build())
	var ability := Ability.new(config, actor.get_id())
	actor.ability_set.grant_ability(ability)
	actor.ability_set.revoke_ability(ability.id)

	var expected := actor.get_gameplay_instance_id()
	TestFramework.assert_equal(expected, actor.seen.get("apply_instance", ""))
	TestFramework.assert_equal(expected, actor.seen.get("remove_instance", ""))
	GameWorld.destroy_instance(expected)


func _test_execution_sees_owner_instance() -> void:
	var actor := _spawn("instance_ctx_execution")
	var start_actions: Array[Action.BaseAction] = [RecordToEventAction.new("start_instance")]
	var tag_actions: Array[Action.BaseAction] = [RecordToEventAction.new("tag_instance")]
	var cancel_actions: Array[Action.BaseAction] = [RecordToEventAction.new("cancel_instance")]
	var config := (AbilityConfig.builder()
		.config_id("instance_ctx_execution")
		.component_config(ActivateInstanceConfig.builder()
			.trigger(TriggerConfig.new(PROBE_KIND))
			.timeline(TimelineData.new("t-instance-context-execution", 100.0, {"hit": 50.0}))
			.on_timeline_start(start_actions)
			.on_tag("hit", tag_actions)
			.on_cancel(cancel_actions)
			.build())
		.build())
	var ability := Ability.new(config, actor.get_id())
	actor.ability_set.grant_ability(ability)

	var probe := {"kind": PROBE_KIND}
	actor.ability_set.receive_event(probe)
	actor.ability_set.tick_executions(60.0)
	# revoke → expire → cancel_all_executions()：调用方什么也不递，cancel action 靠 execution 自己反查
	actor.ability_set.revoke_ability(ability.id)

	var expected := actor.get_gameplay_instance_id()
	for key: String in ["start_instance", "tag_instance", "cancel_instance"]:
		TestFramework.assert_equal(expected, probe.get(key, ""))
	GameWorld.destroy_instance(expected)


func _test_pre_handler_sees_owner_instance() -> void:
	var actor := _spawn("instance_ctx_pre")
	var config := (AbilityConfig.builder()
		.config_id("instance_ctx_pre")
		.component_config(PreEventConfig.new(PRE_KIND, _pre_handler_recording_instance()))
		.build())
	actor.ability_set.grant_ability(Ability.new(config, actor.get_id()))

	var event := {"kind": PRE_KIND}
	GameWorld.event_processor.process_pre_event(event)
	var expected := actor.get_gameplay_instance_id()
	TestFramework.assert_equal(expected, event.get("pre_instance", ""))
	GameWorld.destroy_instance(expected)


## owner 反查不到 → instance 为 null（不猜、不回退到别的 instance）；
## 而 grant 的 AbilityGranted 投递与 owner 是否注册无关，GRANTED_SELF 照样自激活。
func _test_unregistered_owner() -> void:
	var owner_id := "no_such_instance:ghost"
	var ability_set := AbilitySet.create(owner_id)
	var config := (AbilityConfig.builder()
		.config_id("instance_ctx_unregistered")
		.component_config(NoInstanceConfig.builder()
			.trigger(TriggerConfig.new(PROBE_KIND, _filter_recording_instance("filter_instance")))
			.action(RecordToEventAction.new("action_instance"))
			.build())
		.component_config(ActivateInstanceConfig.builder()
			.trigger(TriggerConfig.GRANTED_SELF)
			.timeline(TimelineData.new("t-instance-context-granted", 100.0, {}))
			.build())
		.build())
	var ability := Ability.new(config, owner_id)
	ability_set.grant_ability(ability)
	TestFramework.assert_equal(1, ability.get_executing_instances().size())

	var probe := {"kind": PROBE_KIND}
	ability_set.receive_event(probe)
	TestFramework.assert_equal(NO_INSTANCE, probe.get("filter_instance", ""))
	TestFramework.assert_equal(NO_INSTANCE, probe.get("action_instance", ""))


# ========== 夹具 ==========

static func _spawn(instance_id: String) -> ProbeActor:
	var instance := GameWorld.create_instance(func() -> GameplayInstance:
		return GameplayInstance.new(instance_id))
	return instance.add_actor(ProbeActor.new()) as ProbeActor


## trigger filter：把 lifecycle context 里的 instance id 记进事件本身，并放行。
static func _filter_recording_instance(key: String) -> Callable:
	return func(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
		event_dict[key] = context.instance.id if context.instance != null else NO_INSTANCE
		return true


## pre handler：把重建出的 context 里的 instance id 记进原始事件，放行。
static func _pre_handler_recording_instance() -> Callable:
	return func(mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
		mutable.original["pre_instance"] = ctx.instance.id if ctx.instance != null else NO_INSTANCE
		return EventPhase.pass_intent()
