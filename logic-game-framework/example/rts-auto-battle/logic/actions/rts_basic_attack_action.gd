## RtsBasicAttackAction - RTS 基本攻击 Action (P1.4 修 S2; P2.8 扩到建筑攻击/被攻击)
##
## P1.4 重写: 从静态 helper (extends RefCounted) 改为标准 LGF Action (extends Action.BaseAction)。
## 与 hex example/damage_action.gd 同构 — 走 ExecutionContext + TargetSelector + Pre/Atomic/Post 三段。
##
## P2.8 改动:
##   - attacker / target 类型都放宽到 RtsBattleActor (单位 + 建筑都走此 action)
##   - 数值通过 attacker.get_atk() / get_def() / target.get_attribute_set().get_current_value("hp")
##     accessor 取, 不再强制 .attribute_set.atk 路径 — 让建筑 (无 RtsUnitAttributeSet.atk) 也能用
##   - target_layer_mask 防御性检查: attacker 武器命不到 target.movement_layer → 跳过
##     (AutoTargetSystem 已过滤, 但 action 层做最后一道防线 — e.g. 玩家手动指挥时也走此 action)
##
## 与 hex damage_action 的差异:
##   - 伤害公式 = max(1, atk - def) (RTS M0 简化, 不走 BattleEvents.DamageType / FloatResolver)
##   - 没有 on_hit / on_critical / on_kill 链 (Phase 1 没接 buff / passive); Phase 2 加被动技能时
##     可参照 hex damage_action 模式追加。
##   - 直接修改 target.get_attribute_set().set_hp_base(hp_after) 后人工 push attack_resolved +
##     actor_died event (M0 既有合同, 给 logger / AC3 用)。
##
## 调方 (RtsAutoBattleProcedure 主循环) 在 attacker.can_attack() + 持目标时:
##
##   var ability_ref := AbilityRef.create("basic_attack_inst", "basic_attack", attacker.get_id())
##   var ctx := ExecutionContext.create([], world, GameWorld.event_collector, ability_ref)
##   action.execute(ctx)
##   attacker.start_attack_cooldown()  # P1.6 走 tag-duration
##
## 决策来源:
##   - phase-1-foundation.md P1.4 (S2 修复)
##   - phase-2-core-systems.md §P2.8 (target_layer_mask + 单位攻击建筑)
class_name RtsBasicAttackAction
extends Action.BaseAction


# ========== 初始化 ==========

func _init(target_selector: TargetSelector) -> void:
	super._init(target_selector)
	type = "rts_basic_attack"


# ========== 执行 ==========

func execute(ctx: ExecutionContext) -> ActionResult:
	var source_id: String = ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if source_id.is_empty():
		return ActionResult.create_failure_result("no source actor (ability_ref missing)")

	var world := ctx.game_state_provider as RtsWorldGameplayInstance
	if world == null:
		return ActionResult.create_failure_result("game_state_provider not RtsWorldGameplayInstance")

	var attacker := world.get_actor(source_id) as RtsBattleActor
	if attacker == null or attacker.is_dead():
		return ActionResult.create_failure_result("attacker missing or dead")

	var targets := get_targets(ctx)
	if targets.is_empty():
		return ActionResult.create_success_result([])

	var event_processor: EventProcessor = GameWorld.event_processor
	var event_collector: EventCollector = ctx.event_collector
	var all_events: Array[Dictionary] = []
	var alive_actor_ids := world.get_alive_actor_ids()

	for target_id in targets:
		var target := world.get_actor(target_id) as RtsBattleActor
		if target == null or target.is_dead():
			continue

		# P2.8: 防御性 layer mask 检查 — AutoTargetSystem 已过滤, 但 action 层兜底
		# (e.g. 玩家手动指挥 attacker 打不可命中目标时, 静默跳过而非崩)。
		if not RtsWeaponConfig.can_hit(attacker, target):
			continue

		var event_results := _execute_single_target(
			source_id, target_id, attacker, target,
			event_processor, event_collector,
			alive_actor_ids, world,
		)
		all_events.append_array(event_results)

	return ActionResult.create_success_result(all_events)


# ========== 内部 ==========

## 执行单个 target 的 Pre → Apply → Post 三段。返回此次产生的事件列表。
##
## P2.8: attacker / target 都放宽到 RtsBattleActor; 数值通过 virtual accessor 取。
func _execute_single_target(
	source_id: String,
	target_id: String,
	attacker: RtsBattleActor,
	target: RtsBattleActor,
	event_processor: EventProcessor,
	event_collector: EventCollector,
	alive_actor_ids: Array[String],
	world: RtsWorldGameplayInstance,
) -> Array[Dictionary]:
	var events_produced: Array[Dictionary] = []

	# ===== 计算原始伤害 =====
	var raw_damage: float = max(1.0, attacker.get_atk() - target.get_def())

	# ===== Pre 阶段 =====
	# pre_damage event 让 buff / passive 修改 / 取消伤害(M0 PreEvent handler 全空, 一律 PASS)。
	var pre_event := RtsBattleEvents.make_pre_damage(source_id, target_id, raw_damage)
	var mutable: MutableEvent = event_processor.process_pre_event(pre_event, world)
	if mutable.cancelled:
		return events_produced

	var final_damage: float = mutable.get_current_value("damage")

	# ===== 应用伤害 (atomic: 应用 hp 扣减 + push event 必须连续) =====
	# P2.8: 走 get_attribute_set().get_raw() 公共路径 — RtsUnitAttributeSet / RtsBuildingAttributeSet 都
	# extend BaseGeneratedAttributeSet, hp 通过 _raw.get_current_value("hp") 取, set_hp_base 写。
	var target_attrs := target.get_attribute_set()
	if target_attrs == null:
		return events_produced
	var raw_attrs: RawAttributeSet = target_attrs.get_raw()
	if raw_attrs == null:
		return events_produced
	var hp_before: float = raw_attrs.get_current_value("hp")
	var hp_after: float = max(0.0, hp_before - final_damage)
	target_attrs.set_hp_base(hp_after)

	# ===== 广播 attack_resolved (logger 消费, AC3 兵种行为断言用) =====
	# P2.8: attacker_unit_class 字段对单位走 unit_class enum, 对建筑走 -1 (logger 兼容; 见 RtsBattleEvents).
	var attacker_class_int: int = -1
	if attacker is RtsUnitActor:
		attacker_class_int = int((attacker as RtsUnitActor).unit_class)
	var resolved := RtsBattleEvents.make_attack_resolved(
		source_id, target_id,
		attacker.position_2d, target.position_2d,
		attacker_class_int, final_damage,
	)
	event_collector.push(resolved)
	events_produced.append(resolved)

	# ===== 死亡判定 =====
	if hp_after <= 0.0 and not target.is_dead():
		target.mark_dead()
		var died := RtsBattleEvents.make_actor_died(target_id, source_id)
		event_collector.push(died)
		events_produced.append(died)

	# ===== Post 阶段 =====
	var post_event := RtsBattleEvents.make_post_damage(
		source_id, target_id, final_damage, hp_after,
	)
	event_processor.process_post_event(post_event, alive_actor_ids, world)

	return events_produced
