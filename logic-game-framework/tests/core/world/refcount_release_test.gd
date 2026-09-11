extends Node

## 释放测试（循环引用硬关卡）
##
## GDScript RefCounted 没有循环 GC：对象图里只要有一条回指强边，整张图在
## 销毁后仍活着。本测试对图中每个节点取 weakref，销毁 instance 并让
## 测试自己的所有强引用随建图函数返回一并消亡（比逐个置 null 更彻底：循环变量 /
## 临时值同样释放），然后断言 weakref 全部归 null——RefCounted 计数归零即时释放，
## 不需要等 GC。任一断言失败 = 存在引用环。
##
## 五个用例：
##  1. 裸 instance：actor(ability_set + attribute_set) + 四组件 ability
##     (PreEvent / NoInstance / StatModifier / ActivateInstance(GRANTED_SELF + loop timeline))，
##     tick 到 execution 真 fire 过 action，pre / post 各派发一次；destroy_instance 后连同 instance
##     自持的 EventProcessor / EventCollector 与 ability 的 pre / post 注册全部释放。
##  2. start_battle + 录像：BattleProcedure / 注入 world collector 的 BattleRecorder / RecordingContext /
##     订阅闭包，battle_finished 后同样全部释放。
##  3. procedure 子类（协变 _get_world、持有只经调用参数拿 world 的 helper）被调用方直接 finish()——
##     不经 world.tick 收尾，finish 自己交还战斗槽位：销毁 world 后全部释放。
##  4. 开着录像的战斗 tick 里 GameWorld.shutdown()（经 world.tick() 驱动；world 是覆盖 on_end 且不调 super 的子类）：
##     被录范围含不参战的常驻 actor 与战斗中途 spawn 的补录 actor；world 结束时中止战斗（tick 期间零错误、
##     不收尾、不发 battle_finished），recorder 与全部被录 actor 一并释放。
##  5. 事件注册跟 ability / owner 走，调用方仍握着 actor 也得释放：revoke 注销该 ability 的注册；remove_actor
##     注销该 owner 的注册；AbilitySet 被整个换掉（inkmon 每场换集的形状）时旧 ability 不经 revoke、注册留在表里，
##     旧 ability 必须照样释放（handler 闭包只带 id），按 owner 清表后注册释放。
## 用例 2-4 在 world 结束后、仍持有 procedure 时先放掉 world 的局部引用：world 必须当场释放。
## 战斗结束 / world 结束已拆掉 world → procedure 这条强边，这一步单独验反向那条
## （procedure 及其持有的对象只许弱回指 world）。
##
## Ability 的 post 注销闭包（_post_unregisters）不是 Object、取不到 weakref：它只捕获注册表与 kind / id，
## 由 ability 的 weakref 与「revoke 之后 _post_unregisters 已清空」两条断言兜住。
##
## context 对象（AbilityLifecycleContext / ExecutionContext）携带 instance 强引用，只许活在
## 调用栈上：探针在 NoInstance 的 on_apply action、trigger filter（post 派发按 id 重建的 lifecycle context）、
## 事件 action 与 timeline tag action 里把收到的 context 以 weakref 捕出，grant / tick / 派发一返回就断言
## 已释放（不等 destroy_instance）。本测试走到的其余构造点（grant 时交给 apply_effects 的 lifecycle context、
## PreEvent 重建的 context）没有 weakref 探针，由两类 context 的存活计数兜底：每个用例结束后计数必须回到用例开始前。

const LogCounter := preload("res://addons/logic-game-framework/tests/log_counter.gd")

const PRE_KIND := "release_probe_pre"
const POST_KIND := "release_probe_post"
const TAG_TICK := "release_probe_tick"
const TAG_END := "release_probe_end"
const TAG_POST := "release_probe_post"

## 探针捕出的 context 在 refs 里的 key 前缀（后接 ":<actor_id>"）。
const PROBE_APPLY := "apply_action_context"
const PROBE_LIFECYCLE := "lifecycle_context"
const PROBE_NO_INSTANCE := "no_instance_context"
const PROBE_TIMELINE := "timeline_context"


## 带 ability_set + attribute_set 的探针 actor。
## 生命周期 / 录像订阅全走 BattleActor 默认实现——本测试也是那套默认订阅的释放硬关卡。
class ReleaseProbeActor:
	extends BattleActor

	var ability_set: AbilitySet
	var attribute_set: ExampleHeroAttributeSet
	## 测试侧 weakref 汇集处：RecordingContext 与探针捕到的 context 只以 weakref 存入。
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


## 把执行时收到的 ExecutionContext 以 weakref 捕进 owner 的 probe_sink（无状态：key 构造后只读）。
class ContextProbeAction:
	extends Action.BaseAction

	var key: String

	func _init(p_key: String) -> void:
		super._init(TargetSelector.new())
		key = p_key

	func execute(ctx: ExecutionContext) -> ActionResult:
		# 没带 instance 的 context 放了也白放——释放断言就证明不了「带 instance 的 context 不被缓存」。
		TestFramework.assert_true(ctx.instance != null, "%s 应携带 owner 所属 instance" % key)
		var probe_actor := GameWorld.get_actor(ctx.ability_ref.owner_actor_id) as ReleaseProbeActor
		probe_actor.probe_sink["%s:%s" % [key, probe_actor.get_id()]] = weakref(ctx)
		return ActionResult.create_success_result([])


## procedure 子类形状的世界：工厂钩子返回 ProbeProcedure。覆盖 on_end 且不调 super——world 结束时
## 中止战斗不能依赖子类会不会调 super 的钩子（用例 4 在它身上验）。
class ProbeWorld:
	extends WorldGameplayInstance

	func _create_battle_procedure(participants: Array[Actor]) -> BattleProcedure:
		return ProbeProcedure.new(self, participants)

	func on_end() -> void:
		pass


## procedure 子类：协变 _get_world()、持有一个只经调用参数拿 world 的 helper（同 hex logger / dota2 controller）。
## end_world_on_tick 置位后，本 tick 判定结束的同时拆掉整个 GameWorld（用例 4）：world 结束优先，tick() 不得
## 再收尾、发 battle_finished；若 world 结束没有中止战斗，tick() 会走 finish() 发出信号——断言抓得到，而不是空转。
class ProbeProcedure:
	extends BattleProcedure

	var helper := ProbeProcedureHelper.new()
	var end_world_on_tick := false
	## 经 finish() 收尾的次数：中止不得走 finish()——子类在 finish() 里的收尾（如 hex 存战斗日志）只属于正常结束。
	var finish_calls := 0

	func _get_world() -> ProbeWorld:
		return super._get_world() as ProbeWorld

	func finish(result: String = "battle_complete") -> Dictionary:
		finish_calls += 1
		return super.finish(result)

	func tick_once() -> void:
		_current_tick += 1
		helper.observe(_get_world())
		record_current_frame_events()
		if end_world_on_tick:
			mark_finished()
			GameWorld.shutdown()


class ProbeProcedureHelper:
	extends RefCounted

	var observed_actor_count := 0

	func observe(world: WorldGameplayInstance) -> void:
		observed_actor_count = world.get_actor_count() if world != null else 0


func _init() -> void:
	TestFramework.register_test("Release: instance graph fully released after destroy_instance",
		_run_release_case.bind(_build_and_destroy_instance_graph))
	TestFramework.register_test("Release: recorded battle graph fully released after battle_finished",
		_run_release_case.bind(_build_and_finish_recorded_battle))
	TestFramework.register_test("Release: procedure subclass finished directly releases world graph",
		_run_release_case.bind(_build_and_finish_subclass_procedure_directly))
	TestFramework.register_test("Release: world ended inside a recorded battle tick releases recorder and every recorded actor",
		_run_release_case.bind(_build_and_end_world_inside_recorded_battle_tick))
	TestFramework.register_test("Release: event registrations released on revoke, remove_actor and ability-set replacement",
		_run_release_case.bind(_build_and_drop_event_registrations))


# ========== 用例外壳 ==========

## 干净注册表 → 建图（局部强引用随 build 返回消亡）→ weakref 全部归 null → context 存活数回到用例前。
func _run_release_case(build: Callable) -> void:
	GameWorld.shutdown()
	var live_before := _live_context_counts()
	var refs: Dictionary = {}
	build.call(refs)
	_assert_all_released(refs)
	_assert_live_contexts_back_to(live_before)


# ========== 建图（局部强引用随函数返回消亡） ==========

## 用例 1：建图 → execution fire 过 action → pre / post 各派发一次 → 取 weakref → destroy_instance。
func _build_and_destroy_instance_graph(refs: Dictionary) -> void:
	var timeline := _make_loop_timeline()
	var instance := GameWorld.create_instance(GameplayInstance.new())
	var actor := instance.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	actor.probe_sink = refs
	var actor_id := actor.get_id()
	var ability := Ability.new(_build_probe_config(timeline), actor_id)
	# grant 恒投递 AbilityGranted → GRANTED_SELF 自激活 loop timeline
	actor.ability_set.grant_ability(ability)
	TestFramework.assert_equal(1, ability.get_executing_instances().size())
	TestFramework.assert_near(actor.attribute_set.attack, 15.0)
	_assert_contexts_released(refs, [_probe_key(PROBE_APPLY, actor_id)])

	# tick 一个周期：tag@50 与周期末 on_timeline_end 各 fire 一次
	actor.ability_set.tick_executions(100.0)
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_TICK))
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_END))
	_assert_contexts_released(refs, [_probe_key(PROBE_TIMELINE, actor_id)])

	var mutable := instance.event_processor.process_pre_event({"kind": PRE_KIND, "value": 10.0})
	TestFramework.assert_near(float(mutable.get_current_value("value")), 15.0)
	instance.event_processor.process_post_event({"kind": POST_KIND})
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_POST))
	_assert_contexts_released(refs, [
		_probe_key(PROBE_LIFECYCLE, actor_id),
		_probe_key(PROBE_NO_INSTANCE, actor_id),
	])

	_collect_actor_refs(refs, actor, "")
	refs["instance"] = weakref(instance)
	refs["event_processor"] = weakref(instance.event_processor)
	refs["event_collector"] = weakref(instance.event_collector)
	GameWorld.destroy_instance(instance.id)
	_assert_no_handlers_left(instance.event_processor)


## 用例 2：world + 两个 actor → start_battle（录像开启）→ 战斗中产生真实事件 → world.tick 收尾 finish。
func _build_and_finish_recorded_battle(refs: Dictionary) -> void:
	var timeline := _make_loop_timeline()
	var world := GameWorld.create_instance(WorldGameplayInstance.new()) as WorldGameplayInstance
	var caster := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var target := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	caster.probe_sink = refs
	target.probe_sink = refs
	# 一份 config 两个 actor 共享: 与生产的 static var 声明同形, 也是最容易藏回指边的形状
	var probe_config := _build_probe_config(timeline)
	var applied: Array[String] = []
	for actor: ReleaseProbeActor in [caster, target]:
		actor.ability_set.grant_ability(Ability.new(probe_config, actor.get_id()))
		applied.append(_probe_key(PROBE_APPLY, actor.get_id()))
	_assert_contexts_released(refs, applied)

	var finish_sink: Dictionary = {}
	world.battle_finished.connect(func(result: Dictionary) -> void:
		finish_sink["result"] = result)
	world.start()
	var participants: Array[Actor] = [caster, target]
	var procedure := world.start_battle(participants)
	var recorder := procedure.get_recorder()
	TestFramework.assert_true(recorder != null and recorder.get_is_recording(), "录像应已开启")
	TestFramework.assert_true(recorder.get_event_collector() == world.event_collector, "recorder 应注入 world 的 collector")
	_assert_recording_probed(refs, recorder, [caster, target])

	# 战斗中的真实事件：execution tick 打 tag（TagChanged 进录像）、post 派发触发被动
	caster.ability_set.tick_executions(100.0)
	_assert_contexts_released(refs, [_probe_key(PROBE_TIMELINE, caster.get_id())])
	world.event_processor.process_post_event({"kind": POST_KIND})
	var dispatched: Array[String] = []
	for actor: ReleaseProbeActor in [caster, target]:
		dispatched.append(_probe_key(PROBE_LIFECYCLE, actor.get_id()))
		dispatched.append(_probe_key(PROBE_NO_INSTANCE, actor.get_id()))
	_assert_contexts_released(refs, dispatched)
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
	_collect_world_refs(refs, world, procedure)
	var processor := world.event_processor
	GameWorld.destroy_instance(world.id)
	_assert_no_handlers_left(processor)
	world = null
	_assert_world_released(refs)


## 用例 3：procedure 子类 + 录像，调用方直接 finish()（dota2 形状：不经 world.tick 收尾）。
func _build_and_finish_subclass_procedure_directly(refs: Dictionary) -> void:
	var world := GameWorld.create_instance(ProbeWorld.new()) as ProbeWorld
	var caster := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var target := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var probe_config := _build_probe_config(_make_loop_timeline())
	for actor: ReleaseProbeActor in [caster, target]:
		actor.probe_sink = refs
		actor.ability_set.grant_ability(Ability.new(probe_config, actor.get_id()))
	world.start()
	var participants: Array[Actor] = [caster, target]
	var procedure := world.start_battle(participants) as ProbeProcedure
	TestFramework.assert_true(procedure != null, "工厂钩子应返回 ProbeProcedure")
	_assert_recording_probed(refs, procedure.get_recorder(), [caster, target])

	caster.ability_set.tick_executions(100.0)
	procedure.tick_once()
	var record := procedure.finish()
	var frames: Array[Dictionary] = []
	frames.assign(record.get("timeline", []))
	TestFramework.assert_true(not frames.is_empty(), "直接 finish 应产出录到事件的录像")
	TestFramework.assert_false(world.has_active_battle(), "直接 finish 应交还 world 的战斗槽位")
	TestFramework.assert_equal(1, procedure.finish_calls)
	TestFramework.assert_equal(2, procedure.helper.observed_actor_count)

	_collect_actor_refs(refs, caster, "caster.")
	_collect_actor_refs(refs, target, "target.")
	_collect_world_refs(refs, world, procedure)
	refs["procedure.helper"] = weakref(procedure.helper)
	var processor := world.event_processor
	GameWorld.destroy_instance(world.id)
	_assert_no_handlers_left(processor)
	world = null
	_assert_world_released(refs)


## 用例 4：录像开着的战斗 tick 里 GameWorld.shutdown()（经 world.tick() 驱动）。被录范围 = registry 全体
## （含不参战的常驻 actor）+ 战斗中途 spawn 经 actor_added 补录的 actor；weakref 挂在全部被录 actor 上。
func _build_and_end_world_inside_recorded_battle_tick(refs: Dictionary) -> void:
	var world := GameWorld.create_instance(ProbeWorld.new()) as ProbeWorld
	var caster := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var target := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var bystander := world.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var probe_config := _build_probe_config(_make_loop_timeline())
	for actor: ReleaseProbeActor in [caster, target, bystander]:
		actor.probe_sink = refs
		actor.ability_set.grant_ability(Ability.new(probe_config, actor.get_id()))

	var finish_sink: Dictionary = {}
	world.battle_finished.connect(func(result: Dictionary) -> void:
		finish_sink["result"] = result)
	world.start()
	var participants: Array[Actor] = [caster, target]
	var procedure := world.start_battle(participants) as ProbeProcedure
	var recorder := procedure.get_recorder()
	# probe_sink 要在 add_actor 之前挂上：add_actor 内经 actor_added 补录时 setup_recording 就写探针。
	var spawned := ReleaseProbeActor.new()
	spawned.probe_sink = refs
	world.add_actor(spawned)
	spawned.ability_set.grant_ability(Ability.new(probe_config, spawned.get_id()))
	caster.ability_set.tick_executions(100.0)
	procedure.tick_once()
	_assert_recording_probed(refs, recorder, [caster, target, bystander, spawned])
	TestFramework.assert_true(world.has_active_battle() and recorder.get_is_recording(), "战斗应仍在进行、录像开着")

	_collect_actor_refs(refs, caster, "caster.")
	_collect_actor_refs(refs, target, "target.")
	_collect_actor_refs(refs, bystander, "bystander.")
	_collect_actor_refs(refs, spawned, "spawned.")
	_collect_world_refs(refs, world, procedure)
	refs["procedure.helper"] = weakref(procedure.helper)
	var processor := world.event_processor
	# tick 里的报错只中止出错那一帧、不发信号，下面的状态断言看不出来——挂计数器断言零错误。
	procedure.end_world_on_tick = true
	var log_counter := LogCounter.new()
	OS.add_logger(log_counter)
	world.tick(100.0)
	OS.remove_logger(log_counter)
	TestFramework.assert_true(log_counter.errors == 0, "战斗 tick 里拆世界报了 %d 条错误" % log_counter.errors)
	TestFramework.assert_equal(0, GameWorld.get_instance_count())
	TestFramework.assert_false(finish_sink.has("result"), "world 结束优先：不应收尾、发 battle_finished")
	TestFramework.assert_equal(0, procedure.finish_calls)
	TestFramework.assert_false(world.has_active_battle(), "world 结束应清掉进行中的战斗")
	TestFramework.assert_false(recorder.get_is_recording(), "world 结束应中止录像")
	TestFramework.assert_true(recorder.actor_subscriptions.is_empty(), "中止录像应退订全部被录 actor")
	_assert_no_handlers_left(processor)
	world = null
	_assert_world_released(refs)


## 用例 5：三个 actor 各 grant 一个探针 ability（各一条 pre + 一条 post 注册），分别走 revoke / remove_actor /
## 整个换掉 AbilitySet 三种退场，每一步都在调用方仍握着 actor 时断言对应的注册（与 ability）已释放。
func _build_and_drop_event_registrations(refs: Dictionary) -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new())
	var processor := instance.event_processor
	var revoked := instance.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var removed := instance.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var replaced := instance.add_actor(ReleaseProbeActor.new()) as ReleaseProbeActor
	var probe_config := _build_probe_config(_make_loop_timeline())
	for actor: ReleaseProbeActor in [revoked, removed, replaced]:
		actor.probe_sink = refs
		actor.ability_set.grant_ability(Ability.new(probe_config, actor.get_id()))

	# revoke：ability 与它的两条注册一起释放
	var revoked_refs := _revoke_only_ability(processor, revoked)
	for key: String in revoked_refs.keys():
		TestFramework.assert_true((revoked_refs[key] as WeakRef).get_ref() == null, "revoke 之后仍存活: %s" % key)
	TestFramework.assert_equal(0, _registrations_where(processor, &"owner_id", revoked.get_id()).size())

	# remove_actor：调用方仍握着 actor，该 owner 的注册照样释放
	var removed_registration_refs := _weakrefs_of(_registrations_where(processor, &"owner_id", removed.get_id()))
	TestFramework.assert_equal(2, removed_registration_refs.size())
	instance.remove_actor(removed.get_id())
	for ref in removed_registration_refs:
		TestFramework.assert_true(ref.get_ref() == null, "引用环: remove_actor 之后注册仍存活")

	# 整个换掉 AbilitySet：旧 ability 没经 revoke、注册还在表里，但注册不能钉住旧 ability
	var old_ability_ref := weakref(replaced.ability_set.get_abilities()[0])
	var replaced_registration_refs := _weakrefs_of(_registrations_where(processor, &"owner_id", replaced.get_id()))
	TestFramework.assert_equal(2, replaced_registration_refs.size())
	replaced.ability_set = AbilitySet.create(replaced.get_id(), replaced.attribute_set)
	TestFramework.assert_true(old_ability_ref.get_ref() == null, "引用环: 注册表里的 handler 钉住了被换掉的 ability")
	for ref in replaced_registration_refs:
		TestFramework.assert_true(ref.get_ref() != null, "换集不经 revoke，注册应仍在表里")
	processor.remove_handlers_by_owner_id(replaced.get_id())
	for ref in replaced_registration_refs:
		TestFramework.assert_true(ref.get_ref() == null, "引用环: 按 owner 清表之后注册仍存活")

	refs["instance"] = weakref(instance)
	refs["event_processor"] = weakref(processor)
	refs["event_collector"] = weakref(instance.event_collector)
	for actor: ReleaseProbeActor in [revoked, removed, replaced]:
		refs["actor:%s" % actor.get_id()] = weakref(actor)
		refs["ability_set:%s" % actor.get_id()] = weakref(actor.ability_set)
	GameWorld.destroy_instance(instance.id)
	_assert_no_handlers_left(processor)


# ========== 夹具 ==========

static func _make_loop_timeline() -> TimelineData:
	var timeline := TimelineData.new("t-release-probe", 100.0, {"tick": 50.0})
	timeline.loop = true
	return timeline


## 四组件 ability：pre 改值 / post 打 tag / 属性加成 / GRANTED_SELF 自激活 loop timeline。
## NoInstance 的 on_apply action、trigger filter、事件 action 与 timeline tag action 各挂一个 context 探针。
static func _build_probe_config(timeline: TimelineData) -> AbilityConfig:
	var pre_handler := func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
		return EventPhase.modify_intent(ctx.ability.id, [Modification.add("value", 5.0)])
	# static 上下文里的 lambda：只捕常量，不捕 self。
	var capture_lifecycle_context := func(_event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
		TestFramework.assert_true(context.instance != null, "trigger filter 收到的 lifecycle context 应携带 instance")
		var probe_actor := GameWorld.get_actor(context.owner_actor_id) as ReleaseProbeActor
		probe_actor.probe_sink[_probe_key(PROBE_LIFECYCLE, probe_actor.get_id())] = weakref(context)
		return true
	var apply_actions: Array[Action.BaseAction] = [ContextProbeAction.new(PROBE_APPLY)]
	var tick_actions: Array[Action.BaseAction] = [
		LooseTagAction.Apply.new(OwnerSelector.new(), TAG_TICK),
		ContextProbeAction.new(PROBE_TIMELINE),
	]
	var end_actions: Array[Action.BaseAction] = [LooseTagAction.Apply.new(OwnerSelector.new(), TAG_END)]
	return (AbilityConfig.builder()
		.config_id("release_probe")
		.component_config(PreEventConfig.new(PRE_KIND, pre_handler))
		.component_config(NoInstanceConfig.builder()
			.on_apply_actions(apply_actions)
			.trigger(TriggerConfig.new(POST_KIND, capture_lifecycle_context))
			.action(LooseTagAction.Apply.new(OwnerSelector.new(), TAG_POST))
			.action(ContextProbeAction.new(PROBE_NO_INSTANCE))
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


static func _probe_key(kind: String, actor_id: String) -> String:
	return "%s:%s" % [kind, actor_id]


## actor 子图：ability_set / tag_container / attribute_set / 每个 ability / 每个 component / 每个 execution /
## ability 在 owner 所属 processor 上的每条 pre / post 注册。
static func _collect_actor_refs(refs: Dictionary, actor: ReleaseProbeActor, prefix: String) -> void:
	refs[prefix + "actor"] = weakref(actor)
	refs[prefix + "ability_set"] = weakref(actor.ability_set)
	refs[prefix + "tag_container"] = weakref(actor.ability_set.tag_container)
	refs[prefix + "attribute_set"] = weakref(actor.attribute_set)
	var processor := GameWorld.get_instance_of_actor(actor.get_id()).event_processor
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
		# PreEvent 一条 + NoInstance 的 POST_KIND 一条；GRANTED_SELF 是定向投递 kind，不注册
		var registrations := _registrations_where(processor, &"ability_id", ability.id)
		TestFramework.assert_equal(2, registrations.size())
		for registration in registrations:
			refs["%sregistration:%s" % [prefix, registration.get("id")]] = weakref(registration)


## world 形用例共有的 weakref：world / procedure / recorder / world 自持的事件设施。
static func _collect_world_refs(refs: Dictionary, world: WorldGameplayInstance, procedure: BattleProcedure) -> void:
	refs["world"] = weakref(world)
	refs["procedure"] = weakref(procedure)
	refs["recorder"] = weakref(procedure.get_recorder())
	refs["event_processor"] = weakref(world.event_processor)
	refs["event_collector"] = weakref(world.event_collector)


## revoke actor 身上唯一的 ability，返回它与它的注册的 weakref（局部强引用随函数返回消亡）。
static func _revoke_only_ability(processor: EventProcessor, actor: ReleaseProbeActor) -> Dictionary:
	var ability := actor.ability_set.get_abilities()[0]
	var weakrefs := {"ability": weakref(ability)}
	var registrations := _registrations_where(processor, &"ability_id", ability.id)
	TestFramework.assert_equal(2, registrations.size())
	for registration in registrations:
		weakrefs["registration:%s" % registration.get("id")] = weakref(registration)
	TestFramework.assert_equal(1, ability._post_unregisters.size())
	actor.ability_set.revoke_ability(ability.id)
	TestFramework.assert_true(ability._post_unregisters.is_empty(), "revoke 之后 post 注销闭包应已清空")
	return weakrefs


## processor 两张注册表里 field == value 的注册（field 取 owner_id / ability_id）。
static func _registrations_where(processor: EventProcessor, field: StringName, value: String) -> Array[RefCounted]:
	var found: Array[RefCounted] = []
	for table: Dictionary in [processor._pre_handlers, processor._post_handlers]:
		for handlers: Array in table.values():
			for registration: RefCounted in handlers:
				if registration.get(field) == value:
					found.append(registration)
	return found


static func _weakrefs_of(objects: Array[RefCounted]) -> Array[WeakRef]:
	var result: Array[WeakRef] = []
	for object in objects:
		result.append(weakref(object))
	return result


## 被录 actor 都已订阅进 recorder，且 RecordingContext 探针真捕到了（没捕到的 key 不在 refs 里，
## _assert_all_released 就查不到它）。
static func _assert_recording_probed(refs: Dictionary, recorder: BattleRecorder, actors: Array) -> void:
	for actor: ReleaseProbeActor in actors:
		var actor_id := actor.get_id()
		TestFramework.assert_true(recorder.actor_subscriptions.has(actor_id), "被录 actor 应已订阅: %s" % actor_id)
		TestFramework.assert_true(refs.has("recording_context:%s" % actor_id), "探针未捕获 recording_context:%s" % actor_id)


## tick / 派发一返回，探针捕出的 context 就必须已释放：它们带 instance 强引用，只许活在调用栈上。
## 先断言 key 在（探针真跑到了），免得「没捕到」被当成「已释放」而假绿。
static func _assert_contexts_released(refs: Dictionary, keys: Array[String]) -> void:
	for key in keys:
		TestFramework.assert_true(refs.has(key), "探针未捕获 %s" % key)
		if refs.has(key):
			TestFramework.assert_true((refs[key] as WeakRef).get_ref() == null,
				"引用环: %s 在调用返回后仍存活" % key)


## destroy_instance / shutdown 必须把 pre / post 两张注册表一并清空。
##
## processor 归 instance、随 instance 一起释放：整张表的消亡会掩盖幽灵注册，所以在 instance 结束之后、
## 建图函数返回（放掉 processor）之前验——「跨战斗累积幽灵注册」是常驻世界真实踩过的形状。
static func _assert_no_handlers_left(processor: EventProcessor) -> void:
	var leftover := 0
	for table: Dictionary in [processor._pre_handlers, processor._post_handlers]:
		for handlers: Array in table.values():
			leftover += handlers.size()
	TestFramework.assert_equal(0, leftover)


## world 已结束、调用方刚放掉最后一个 world 局部引用而仍持有 procedure：world 必须当场释放。
static func _assert_world_released(refs: Dictionary) -> void:
	TestFramework.assert_true((refs["world"] as WeakRef).get_ref() == null,
		"引用环: procedure 或它持有的对象强回指了 world")


static func _assert_all_released(refs: Dictionary) -> void:
	TestFramework.assert_true(refs.size() >= 10, "weakref 清单异常偏少: %d" % refs.size())
	for key: String in refs.keys():
		var ref: WeakRef = refs[key]
		TestFramework.assert_true(ref.get_ref() == null, "引用环: %s 在销毁后仍存活" % key)


static func _live_context_counts() -> Array[int]:
	return [ExecutionContext.get_live_count(), AbilityLifecycleContext.get_live_count()]


## 未挂探针的 context 构造点兜底：用例结束后两类 context 的存活数必须回到用例开始前。
static func _assert_live_contexts_back_to(before: Array[int]) -> void:
	var after := _live_context_counts()
	TestFramework.assert_true(after == before,
		"context 活过了调用栈: ExecutionContext %d -> %d, AbilityLifecycleContext %d -> %d" % [
			before[0], after[0], before[1], after[1]])
