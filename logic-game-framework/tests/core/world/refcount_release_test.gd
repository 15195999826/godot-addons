extends Node

## 释放测试（循环引用硬关卡）
##
## GDScript RefCounted 没有循环 GC：对象图里只要有一条回指强边，整张图在
## destroy_instance 后仍活着。本测试对图中每个节点取 weakref，销毁 instance 并让
## 测试自己的所有强引用随建图函数返回一并消亡（比逐个置 null 更彻底：循环变量 /
## 临时值同样释放），然后断言 weakref 全部归 null——RefCounted 计数归零即时释放，
## 不需要等 GC。任一断言失败 = 存在引用环。
##
## 两个用例：
##  1. 裸 instance：actor(ability_set + attribute_set) + 四组件 ability
##     (PreEvent / NoInstance / StatModifier / ActivateInstance(GRANTED_SELF + loop timeline))，
##     tick 到 execution 真 fire 过 action，pre / post 各派发一次。
##  2. start_battle + 录像：BattleProcedure / BattleRecorder / RecordingContext / 订阅闭包，
##     battle_finished 后同样全部释放。
##
## EventProcessor / EventCollector 归 GameWorld 持有：用 GameWorld.init() 换新，
## 让旧实例失去唯一持有者后断言释放。

const PRE_KIND := "release_probe_pre"
const POST_KIND := "release_probe_post"
const TAG_TICK := "release_probe_tick"
const TAG_END := "release_probe_end"
const TAG_POST := "release_probe_post"


## 带 ability_set + attribute_set 的探针 actor。
## 生命周期 / 录像订阅全走 BattleActor 默认实现——本测试也是那套默认订阅的释放硬关卡。
class ReleaseProbeActor:
	extends BattleActor

	var ability_set: AbilitySet
	var attribute_set: ExampleHeroAttributeSet
	## 测试侧 weakref 汇集处：setup_recording 收到的 RecordingContext 只以 weakref 存入。
	var probe_sink: Dictionary = {}

	func _init() -> void:
		type = "release_probe"
		attribute_set = ExampleHeroAttributeSet.new()
		ability_set = AbilitySet.create("", attribute_set)

	func get_ability_set() -> AbilitySet:
		return ability_set

	func get_attribute_set() -> BaseGeneratedAttributeSet:
		return attribute_set

	func setup_recording(ctx: RecordingContext) -> Array[Callable]:
		probe_sink["recording_context:%s" % get_id()] = weakref(ctx)
		return super.setup_recording(ctx)


## 选中 ability 拥有者本人（无状态，只读 ctx）。
class OwnerSelector:
	extends TargetSelector

	func select(ctx: ExecutionContext) -> Array[String]:
		return [ctx.ability_ref.owner_actor_id]


func _init() -> void:
	TestFramework.register_test("Release: instance graph fully released after destroy_instance", _test_instance_graph_released)
	TestFramework.register_test("Release: recorded battle graph fully released after battle_finished", _test_recorded_battle_released)


# ========== 用例 ==========

func _test_instance_graph_released() -> void:
	GameWorld.init()
	var refs: Dictionary = {}
	_build_and_destroy_instance_graph(refs)
	_assert_no_pre_handlers_left()
	GameWorld.init()
	_assert_all_released(refs)


func _test_recorded_battle_released() -> void:
	GameWorld.init()
	var refs: Dictionary = {}
	_build_and_finish_recorded_battle(refs)
	_assert_no_pre_handlers_left()
	GameWorld.init()
	_assert_all_released(refs)


# ========== 建图（局部强引用随函数返回消亡） ==========

## 用例 1：建图 → execution fire 过 action → pre / post 各派发一次 → 取 weakref → destroy_instance。
func _build_and_destroy_instance_graph(refs: Dictionary) -> void:
	var timeline := _make_loop_timeline()
	var instance := GameWorld.create_instance(func() -> GameplayInstance:
		return GameplayInstance.new())
	var actor := instance.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var actor_id := actor.get_id()
	var ability := Ability.new(_build_probe_config(timeline), actor_id)
	# 传 provider → grant 广播 AbilityGranted → GRANTED_SELF 自激活 loop timeline
	actor.ability_set.grant_ability(ability, instance)
	TestFramework.assert_equal(1, ability.get_executing_instances().size())
	TestFramework.assert_near(actor.attribute_set.attack, 15.0)

	# tick 一个周期：tag@50 与周期末 on_timeline_end 各 fire 一次
	actor.ability_set.tick_executions(100.0, instance)
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_TICK))
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_END))

	var mutable := GameWorld.event_processor.process_pre_event({"kind": PRE_KIND, "value": 10.0}, instance)
	TestFramework.assert_near(float(mutable.get_current_value("value")), 15.0)
	var audience: Array[String] = [actor_id]
	GameWorld.event_processor.process_post_event({"kind": POST_KIND}, audience, instance)
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_POST))

	_collect_actor_refs(refs, actor, "")
	refs["instance"] = weakref(instance)
	refs["event_processor"] = weakref(GameWorld.event_processor)
	refs["event_collector"] = weakref(GameWorld.event_collector)
	GameWorld.destroy_instance(instance.id)


## 用例 2：world + 两个 actor → start_battle（录像开启）→ 战斗中产生真实事件 → finish。
func _build_and_finish_recorded_battle(refs: Dictionary) -> void:
	var timeline := _make_loop_timeline()
	var world := GameWorld.create_instance(func() -> GameplayInstance:
		return WorldGameplayInstance.new()) as WorldGameplayInstance
	var caster := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var target := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	caster.probe_sink = refs
	target.probe_sink = refs
	# 一份 config 两个 actor 共享: 与生产的 static var 声明同形, 也是最容易藏回指边的形状
	var probe_config := _build_probe_config(timeline)
	for actor: ReleaseProbeActor in [caster, target]:
		actor.ability_set.grant_ability(Ability.new(probe_config, actor.get_id()), world)

	var finish_sink: Dictionary = {}
	world.battle_finished.connect(func(result: Dictionary) -> void:
		finish_sink["result"] = result)
	world.start()
	var participants: Array[Actor] = [caster, target]
	var procedure := world.start_battle(participants)
	var recorder := procedure.get_recorder()
	TestFramework.assert_true(recorder != null and recorder.get_is_recording(), "录像应已开启")

	# 战斗中的真实事件：execution tick 打 tag（TagChanged 进录像）、post 派发触发被动
	caster.ability_set.tick_executions(100.0, world)
	var audience: Array[String] = [caster.get_id(), target.get_id()]
	GameWorld.event_processor.process_post_event({"kind": POST_KIND}, audience, world)
	procedure.mark_finished()
	world.tick(100.0)  # tick_once 录帧 → should_end → finish → battle_finished

	TestFramework.assert_true(finish_sink.has("result"), "battle_finished 未发出")
	# 用 assign 而非直接赋值：battle_finished 没发时上面的断言只记录不中断，
	# 这里拿到的是无类型空 Array，直接赋给 Array[Dictionary] 会抛类型转换错，
	# 把「断言失败」这条干净信息换成引擎报错。
	var frames: Array[Dictionary] = []
	frames.assign(finish_sink.get("result", {}).get("timeline", []))
	TestFramework.assert_true(not frames.is_empty(), "录像应至少录到一帧事件")
	TestFramework.assert_true(not world.has_active_battle(), "finish 后 world 不应再持有 procedure")

	_collect_actor_refs(refs, caster, "caster.")
	_collect_actor_refs(refs, target, "target.")
	refs["world"] = weakref(world)
	refs["procedure"] = weakref(procedure)
	refs["recorder"] = weakref(recorder)
	refs["event_processor"] = weakref(GameWorld.event_processor)
	refs["event_collector"] = weakref(GameWorld.event_collector)
	GameWorld.destroy_instance(world.id)


# ========== 夹具 ==========

static func _make_loop_timeline() -> TimelineData:
	var timeline := TimelineData.new("t-release-probe", 100.0, {"tick": 50.0})
	timeline.loop = true
	return timeline


## 四组件 ability：pre 改值 / post 打 tag / 属性加成 / GRANTED_SELF 自激活 loop timeline。
static func _build_probe_config(timeline: TimelineData) -> AbilityConfig:
	var pre_handler := func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
		return EventPhase.modify_intent(ctx.ability.id, [Modification.add("value", 5.0)])
	var tick_actions: Array[Action.BaseAction] = [LooseTagAction.Apply.new(OwnerSelector.new(), TAG_TICK)]
	var end_actions: Array[Action.BaseAction] = [LooseTagAction.Apply.new(OwnerSelector.new(), TAG_END)]
	return (AbilityConfig.builder()
		.config_id("release_probe")
		.component_config(PreEventConfig.new(PRE_KIND, pre_handler))
		.component_config(NoInstanceConfig.builder()
			.trigger(TriggerConfig.new(POST_KIND))
			.action(LooseTagAction.Apply.new(OwnerSelector.new(), TAG_POST))
			.build())
		.component_config(StatModifierConfig.builder()
			.modifier("attack", AttributeModifier.Type.ADD_BASE, 3.0)
			.build())
		.component_config(ActivateInstanceConfig.builder()
			.trigger(TriggerConfig.GRANTED_SELF)
			.timeline(timeline)
			.on_tag("tick", tick_actions)
			.on_timeline_end(end_actions)
			.build())
		.build())


## actor 子图：ability_set / tag_container / attribute_set / 每个 ability / 每个 component / 每个 execution。
static func _collect_actor_refs(refs: Dictionary, actor: ReleaseProbeActor, prefix: String) -> void:
	refs[prefix + "actor"] = weakref(actor)
	refs[prefix + "ability_set"] = weakref(actor.ability_set)
	refs[prefix + "tag_container"] = weakref(actor.ability_set.tag_container)
	refs[prefix + "attribute_set"] = weakref(actor.attribute_set)
	# 锁形状：整类 weakref 消失（ability 被提前 revoke、execution 被清空）时
	# refs 仍能凑过 size 下限而全绿——那样探针就不再探它该探的东西了。
	var abilities := actor.ability_set.get_abilities()
	TestFramework.assert_equal(1, abilities.size())
	for ability in abilities:
		refs["%sability:%s" % [prefix, ability.id]] = weakref(ability)
		# key 带序号：同一 ability 挂两个同类型 component 时按 type 建 key 会互相覆盖，
		# 后加入的顶掉先加入的 weakref → 成环的那个查不出来，硬关卡假绿。
		var components := ability.get_all_components()
		TestFramework.assert_equal(4, components.size())
		for i in components.size():
			refs["%scomponent:%d:%s" % [prefix, i, components[i].type]] = weakref(components[i])
		var executions := ability.get_all_execution_instances()
		TestFramework.assert_true(not executions.is_empty(), "GRANTED_SELF 应已自激活 execution")
		for execution in executions:
			refs["%sexecution:%s" % [prefix, execution.id]] = weakref(execution)


## destroy_instance / end() 必须把 actor 的 pre handler 注册一并注销。
##
## 必须在换 GameWorld.event_processor 之前验：换掉整个 processor 会连 _pre_handlers
## 整张表一起丢，幽灵注册在那之后无从查起——而「跨战斗累积幽灵注册」正是
## 常驻世界（GameWorld 是长命 autoload）真实踩过的形状。
static func _assert_no_pre_handlers_left() -> void:
	var processor := GameWorld.event_processor
	var leftover := 0
	for event_kind: String in processor._pre_handlers.keys():
		leftover += (processor._pre_handlers[event_kind] as Array).size()
	TestFramework.assert_equal(0, leftover)


static func _assert_all_released(refs: Dictionary) -> void:
	TestFramework.assert_true(refs.size() >= 10, "weakref 清单异常偏少: %d" % refs.size())
	for key: String in refs.keys():
		var ref: WeakRef = refs[key]
		TestFramework.assert_true(ref.get_ref() == null, "引用环: %s 在销毁后仍存活" % key)
