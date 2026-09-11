extends Node

## BattleActor 骨架单测
##
## 覆盖三家 actor（hex / dota2 / inkmon）合并到 core 后的公共合同：
## 死亡锁存的一次性、纯数据 actor（两个 getter 返回 null）全程不崩、
## _on_id_assigned 把 id 同步进 ability_set + tag_container + attribute_set、
## 以及 AbilitySet.tick_runtime 的 blocking 语义。

const TAG_INTRINSIC := "intrinsic"
const TAG_TICKED := "battle_actor_probe_ticked"


## 带 hp 的最小 attribute set（不借 example 的具体职业属性表）。
class ProbeAttributeSet:
	extends BaseGeneratedAttributeSet

	func _init(p_actor_id: String = "") -> void:
		super(p_actor_id)
		_raw.apply_config({
			"hp": { "baseValue": 10.0, "minValue": 0.0 },
		})

	func set_hp_base(value: float) -> void:
		_raw.set_base("hp", value)


## 无 hp 属性的 attribute set：验证「有 attribute_set 但没血条」不被判成尸体。
class NoHpAttributeSet:
	extends BaseGeneratedAttributeSet

	func _init(p_actor_id: String = "") -> void:
		super(p_actor_id)
		_raw.apply_config({
			"attack": { "baseValue": 3.0 },
		})


## 全套战斗 actor（两个 set 都有）。
class ProbeBattleActor:
	extends BattleActor

	var ability_set: AbilitySet
	var attribute_set: BaseGeneratedAttributeSet

	func _init(p_attribute_set: BaseGeneratedAttributeSet = null) -> void:
		type = "probe_battle"
		attribute_set = p_attribute_set if p_attribute_set != null else ProbeAttributeSet.new()
		ability_set = ProbeAbilitySet.new("", attribute_set)

	func get_ability_set() -> AbilitySet:
		return ability_set

	func get_attribute_set() -> BaseGeneratedAttributeSet:
		return attribute_set


## 纯数据 actor：继承 BattleActor 只为共享形状，两个 getter 保持默认 null。
class ProbeDataActor:
	extends BattleActor

	func _init() -> void:
		type = "probe_data"


## 打了 intrinsic 标的 ability 不阻塞行动（复现 hex / inkmon 的项目规则）。
class ProbeAbilitySet:
	extends AbilitySet

	func _is_blocking_execution(ability: Ability) -> bool:
		return not ability.has_ability_tag(TAG_INTRINSIC)


## 选中 ability 拥有者本人（无状态，只读 ctx）。
class OwnerSelector:
	extends TargetSelector

	func select(ctx: ExecutionContext) -> Array[String]:
		return [ctx.ability_ref.owner_actor_id]


## revoke 拥有者身上 config_id 的全部 ability（config_id 构造后只读，action 无状态）。
class RevokeByConfigAction:
	extends Action.BaseAction

	var config_id: String

	func _init(p_config_id: String) -> void:
		super._init(TargetSelector.new())
		config_id = p_config_id

	func execute(ctx: ExecutionContext) -> ActionResult:
		var owner_set := BattleActor.ability_set_of(ctx.instance.get_actor(ctx.ability_ref.owner_actor_id))
		owner_set.revoke_abilities_by_config_id(config_id)
		return ActionResult.create_success_result([])


func _init() -> void:
	TestFramework.register_test("BattleActor check_death latches once", _test_check_death_latches_once)
	TestFramework.register_test("BattleActor check_death ignores actors without hp", _test_check_death_without_hp)
	TestFramework.register_test("BattleActor mark_dead reports first time only", _test_mark_dead)
	TestFramework.register_test("BattleActor set_death_latch can unlatch", _test_set_death_latch)
	TestFramework.register_test("BattleActor with null sets survives every call", _test_data_actor_null_safe)
	TestFramework.register_test("BattleActor _on_id_assigned syncs owner id", _test_id_assignment_syncs_owner)
	TestFramework.register_test("BattleActor ability_set_of returns null for plain Actor", _test_ability_set_of)
	TestFramework.register_test("AbilitySet.tick_runtime blocks on the tick an execution ends", _test_tick_runtime_blocking)
	TestFramework.register_test("AbilitySet.tick_runtime ignores non-blocking abilities", _test_tick_runtime_non_blocking)
	TestFramework.register_test("AbilitySet tick pass survives revoking an earlier ability", _test_tick_survives_mid_pass_revoke)
	TestFramework.register_test("BattleActor team id syncs both int and string views", _test_team_id)
	TestFramework.register_test("BattleActor serializes attributes and death latch", _test_serialize_with_sets)
	TestFramework.register_test("BattleActor subscribes attributes + abilities + lifecycle", _test_setup_recording_full)
	TestFramework.register_test("GameWorld.get_instance_of_actor resolves owner instance", _test_get_instance_of_actor)


# ========== 死亡锁存 ==========

func _test_check_death_latches_once() -> void:
	var actor := ProbeBattleActor.new()
	TestFramework.assert_false(actor.is_dead())
	TestFramework.assert_false(actor.check_death(), "满血不应判死")

	(actor.attribute_set as ProbeAttributeSet).set_hp_base(0.0)
	TestFramework.assert_true(actor.check_death(), "首次归零应返回 true")
	TestFramework.assert_true(actor.is_dead())
	TestFramework.assert_false(actor.check_death(), "锁存后再问不应重复报首次")


## hp 没归零就不该锁存——避免「读不到血条」被当成死亡。
func _test_check_death_without_hp() -> void:
	var actor := ProbeBattleActor.new(NoHpAttributeSet.new())
	TestFramework.assert_false(actor.has_hp())
	TestFramework.assert_near(actor.get_current_hp(), 0.0)
	TestFramework.assert_false(actor.check_death(), "没有 hp 属性的 actor 不该被判死")
	TestFramework.assert_false(actor.is_dead())


func _test_mark_dead() -> void:
	var actor := ProbeBattleActor.new()
	TestFramework.assert_true(actor.mark_dead())
	TestFramework.assert_true(actor.is_dead())
	TestFramework.assert_false(actor.mark_dead(), "已死再标记不应报首次")
	TestFramework.assert_false(actor.is_event_responsive({}, EventPhase.PHASE_PRE), "死者不再响应 PreEvent")
	TestFramework.assert_false(actor.is_event_responsive({}, EventPhase.PHASE_POST), "死者也不再响应 post 事件（默认没有豁免）")


## 复活是项目层规则, core 只提供解闩入口 (否则项目层只能直写基类私有字段)。
func _test_set_death_latch() -> void:
	var actor := ProbeBattleActor.new()
	actor.set_death_latch(true)
	TestFramework.assert_true(actor.is_dead())
	actor.set_death_latch(false)
	TestFramework.assert_false(actor.is_dead())
	TestFramework.assert_true(actor.is_event_responsive({}, EventPhase.PHASE_PRE))
	TestFramework.assert_true(actor.is_event_responsive({}, EventPhase.PHASE_POST))
	TestFramework.assert_true(actor.mark_dead(), "解闩后再死应重新算首次")


# ========== 纯数据 actor 的 null 安全 ==========

func _test_data_actor_null_safe() -> void:
	var actor := ProbeDataActor.new()
	TestFramework.assert_true(actor.get_ability_set() == null)
	TestFramework.assert_true(actor.get_attribute_set() == null)
	TestFramework.assert_false(actor.has_hp())
	TestFramework.assert_near(actor.get_current_hp(), 0.0)
	TestFramework.assert_false(actor.check_death())
	TestFramework.assert_true(actor.is_event_responsive({}, EventPhase.PHASE_PRE))
	TestFramework.assert_true(actor.get_attribute_snapshot().is_empty())
	TestFramework.assert_true(actor.get_ability_snapshot().is_empty())
	TestFramework.assert_true(actor.get_tag_snapshot().is_empty())

	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_null_safe"))
	instance.add_actor(actor)
	TestFramework.assert_true(actor.is_id_valid(), "_on_id_assigned 不应因两个 set 为 null 中断")

	var ctx := RecordingContext.new(actor.get_id(), BattleRecorder.new({}, instance.event_collector))
	TestFramework.assert_true(_drain(actor.setup_recording(ctx)) == 1,
		"没有两个 set 时仍应订阅 actor 生命周期这一条")

	var data := actor.serialize()
	TestFramework.assert_true((data["attribute_set"] as Dictionary).is_empty())
	TestFramework.assert_false(data["is_dead"])
	GameWorld.destroy_instance(instance.id)


# ========== id 分配 ==========

func _test_id_assignment_syncs_owner() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_id_sync"))
	var actor := instance.add_actor(ProbeBattleActor.new()) as ProbeBattleActor
	var actor_id := actor.get_id()
	TestFramework.assert_true(actor_id != "")
	TestFramework.assert_equal(actor_id, actor.ability_set.owner_actor_id)
	TestFramework.assert_equal(actor_id, actor.ability_set.tag_container.owner_id)
	TestFramework.assert_equal(actor_id, actor.attribute_set.actor_id)
	GameWorld.destroy_instance(instance.id)


func _test_ability_set_of() -> void:
	var battle_actor := ProbeBattleActor.new()
	TestFramework.assert_true(BattleActor.ability_set_of(battle_actor) == battle_actor.ability_set)
	TestFramework.assert_true(BattleActor.ability_set_of(ProbeDataActor.new()) == null)
	TestFramework.assert_true(BattleActor.ability_set_of(Actor.new()) == null, "非 BattleActor 返回 null")
	TestFramework.assert_true(BattleActor.ability_set_of(null) == null)


# ========== tick_runtime ==========

## blocking 在 tick_executions **之前**算：本 tick 跑完的 execution 仍占这一帧，
## 否则角色会在收招那一帧既施法又充能。
func _test_tick_runtime_blocking() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_tick_runtime"))
	var actor := instance.add_actor(ProbeBattleActor.new()) as ProbeBattleActor
	actor.ability_set.grant_ability(Ability.new(_build_probe_config(), actor.get_id()))
	TestFramework.assert_true(actor.ability_set.has_executing_instances(), "GRANTED_SELF 应已自激活")

	TestFramework.assert_true(actor.ability_set.tick_runtime(100.0, 100.0),
		"execution 在本 tick 内跑完，本 tick 仍算阻塞")
	TestFramework.assert_false(actor.ability_set.has_executing_instances(), "execution 应已结束")
	TestFramework.assert_false(actor.ability_set.tick_runtime(100.0, 200.0),
		"下一 tick 才解除阻塞")
	GameWorld.destroy_instance(instance.id)


func _test_tick_runtime_non_blocking() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_tick_runtime_intrinsic"))
	var actor := instance.add_actor(ProbeBattleActor.new()) as ProbeBattleActor
	var tags: Array[String] = [TAG_INTRINSIC]
	actor.ability_set.grant_ability(Ability.new(_build_probe_config(tags), actor.get_id()))
	TestFramework.assert_true(actor.ability_set.has_executing_instances(),
		"intrinsic ability 同样在执行中")
	TestFramework.assert_false(actor.ability_set.tick_runtime(50.0, 50.0),
		"_is_blocking_execution 为 false 的 ability 不冻结行动")
	# 关键：不阻塞 ≠ 不推进。若 tick_executions 被误挂在 blocking 而不是 has_any 上,
	# intrinsic ability 的 timeline 会永久冻结——而只断言「还在执行中」看不出这个。
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_TICKED))
	TestFramework.assert_true(actor.ability_set.has_executing_instances(), "50ms 还没跑完")
	GameWorld.destroy_instance(instance.id)


## 一轮 tick_executions 遍历 ability 的快照：中间的 ability 本轮 revoke 掉排在它前面的那个，
## 排在它后面的 ability 本轮照常推进（遍历活数组时数组左移，最后一个会被跳过）。
func _test_tick_survives_mid_pass_revoke() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_mid_pass_revoke"))
	var actor := instance.add_actor(ProbeBattleActor.new()) as ProbeBattleActor
	var revoked_config := "battle_actor_probe_revoked"
	actor.ability_set.grant_ability(Ability.new(AbilityConfig.builder().config_id(revoked_config).build(), actor.get_id()))
	var revoke_actions: Array[Action.BaseAction] = [RevokeByConfigAction.new(revoked_config)]
	actor.ability_set.grant_ability(Ability.new(_build_timeline_config("battle_actor_probe_revoker", revoke_actions), actor.get_id()))
	actor.ability_set.grant_ability(Ability.new(_build_probe_config(), actor.get_id()))

	actor.ability_set.tick_executions(50.0)
	TestFramework.assert_false(actor.ability_set.has_ability(revoked_config), "排在前面的 ability 应已 revoke")
	# 排在后面的 ability 本轮仍应推进
	TestFramework.assert_equal(1, actor.ability_set.get_loose_tag_stacks(TAG_TICKED))
	GameWorld.destroy_instance(instance.id)


# ========== 队伍 / 序列化 / 录像 / 实例反查 ==========

## set_team_id 要同时写 int 与 Actor 基类的字符串 team——录像的 _get_team_int 读前者,
## serialize_base 的 "team" 读后者, 掉一半就是回放里敌我不分。
func _test_team_id() -> void:
	var actor := ProbeBattleActor.new()
	TestFramework.assert_equal(-1, actor.get_team_id())
	TestFramework.assert_equal(-1, actor.team)
	actor.set_team_id(1)
	TestFramework.assert_equal(1, actor.get_team_id())
	TestFramework.assert_equal("1", actor.get_team())
	TestFramework.assert_equal(1, actor.team)


func _test_serialize_with_sets() -> void:
	var actor := ProbeBattleActor.new()
	(actor.attribute_set as ProbeAttributeSet).set_hp_base(4.0)
	actor.set_display_name("probe")
	actor.mark_dead()
	var data := actor.serialize()
	TestFramework.assert_equal("probe", data["displayName"])
	TestFramework.assert_true(data["is_dead"], "死亡闩要进序列化")
	var attrs: Dictionary = data["attribute_set"]
	TestFramework.assert_true(attrs.has("hp"), "属性 raw 应完整落盘: %s" % [attrs.keys()])
	TestFramework.assert_near(float((attrs["hp"] as Dictionary)["base"]), 4.0)


func _test_setup_recording_full() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_recording"))
	var actor := instance.add_actor(ProbeBattleActor.new()) as ProbeBattleActor
	var ctx := RecordingContext.new(actor.get_id(), BattleRecorder.new({}, instance.event_collector))
	# 期望条数从三个 RecordingUtils 现算, 免得把数字抄死; 探针订阅当场退订 ——
	# 它们捕获的 ctx → recorder 不退订会活到进程结束, 泄漏直方图会当场报红。
	var expected := _drain(RecordingUtils.record_attribute_changes(actor.attribute_set, ctx)) \
		+ _drain(RecordingUtils.record_ability_set_changes(actor.ability_set, ctx)) \
		+ _drain(RecordingUtils.record_actor_lifecycle(actor, ctx))
	# 属性 + ability_set + 生命周期三类都要在；少任何一类都会让回放整类事件消失。
	TestFramework.assert_equal(expected, _drain(actor.setup_recording(ctx)))
	TestFramework.assert_true(expected > 1, "完整 actor 不能只订生命周期一条")
	GameWorld.destroy_instance(instance.id)


## 退订一批订阅并返回它们的条数。
static func _drain(unsubscribes: Array[Callable]) -> int:
	for unsubscribe in unsubscribes:
		unsubscribe.call()
	return unsubscribes.size()


func _test_get_instance_of_actor() -> void:
	var instance := GameWorld.create_instance(GameplayInstance.new("battle_actor_instance_lookup"))
	var actor := instance.add_actor(ProbeBattleActor.new()) as ProbeBattleActor
	TestFramework.assert_true(GameWorld.get_instance_of_actor(actor.get_id()) == instance)
	TestFramework.assert_true(GameWorld.get_instance_of_actor("") == null)
	TestFramework.assert_true(GameWorld.get_instance_of_actor("no_such_instance:x") == null)
	TestFramework.assert_true(GameWorld.get_instance_of_actor("malformed_without_separator") == null)
	GameWorld.destroy_instance(instance.id)


# ========== 夹具 ==========

## grant 即自激活一条 100ms timeline 的 ability；40ms 处打一个 tag 证明 timeline 真在走。
static func _build_probe_config(tags: Array[String] = []) -> AbilityConfig:
	var tick_actions: Array[Action.BaseAction] = [
		LooseTagAction.Apply.new(OwnerSelector.new(), TAG_TICKED)
	]
	return _build_timeline_config("battle_actor_probe", tick_actions, tags)


## grant 即自激活一条 100ms timeline 的 ability；40ms 处跑 tick_actions。
static func _build_timeline_config(config_id: String, tick_actions: Array[Action.BaseAction], tags: Array[String] = []) -> AbilityConfig:
	return (AbilityConfig.builder()
		.config_id(config_id)
		.ability_tags(tags)
		.component_config(ActivateInstanceConfig.builder()
			.trigger(TriggerConfig.GRANTED_SELF)
			.timeline(TimelineData.new("t-" + config_id, 100.0, {"ticked": 40.0}))
			.on_tag("ticked", tick_actions)
			.build())
		.build())
