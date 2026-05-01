## RtsBasicAttackAction - RTS 基本攻击 Action (P1.4 修复 S2)
##
## P1.4 重写: 从静态 helper (extends RefCounted) 改为标准 LGF Action (extends Action.BaseAction)。
## 与 hex example/damage_action.gd:38 同构 — 走 ExecutionContext + TargetSelector + Pre/Atomic/Post 三段。
##
## 与 hex damage_action 的差异:
##   - 伤害公式 = max(1, atk - def) (RTS M0 简化, 不走 BattleEvents.DamageType / FloatResolver)
##   - 没有 on_hit / on_critical / on_kill 链 (Phase 1 没接 buff / passive); Phase 2 加被动技能时
##     可参照 hex damage_action 模式追加。
##   - 不走 HexBattleDamageUtils.apply_damage 工具(那个 hex 专属); 直接修改 attribute_set.hp_base 后
##     人工 push attack_resolved + actor_died event(M0 既有合同, 给 logger / AC3 用)。
##
## 调方 (RtsAutoBattleProcedure 主循环) 在 controller.wants_to_attack() + actor.can_attack() 时:
##
##   var ability_ref := AbilityRef.create("basic_attack_inst", "basic_attack", attacker.get_id())
##   var ctx := ExecutionContext.create([], world, GameWorld.event_collector, ability_ref)
##   action.execute(ctx)   # action 是 procedure 持的共享实例(每场战斗 1 个, target_selector 复用)
##   attacker.start_attack_cooldown()  # P1.6 走 tag-duration
##
## 决策来源:
##   - phase-1-foundation.md P1.4 (S2 修复)
##   - architecture-baseline.md §10 (S2 偏离修复对照)
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

	var attacker := world.get_actor(source_id) as RtsUnitActor
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
		var target := world.get_actor(target_id) as RtsUnitActor
		if target == null or target.is_dead():
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
func _execute_single_target(
	source_id: String,
	target_id: String,
	attacker: RtsUnitActor,
	target: RtsUnitActor,
	event_processor: EventProcessor,
	event_collector: EventCollector,
	alive_actor_ids: Array[String],
	world: RtsWorldGameplayInstance,
) -> Array[Dictionary]:
	var events_produced: Array[Dictionary] = []

	# ===== 计算原始伤害 =====
	var raw_damage: float = max(1.0, attacker.attribute_set.atk - target.attribute_set.def)

	# ===== Pre 阶段 =====
	# pre_damage event 让 buff / passive 修改 / 取消伤害(M0 PreEvent handler 全空, 一律 PASS)。
	var pre_event := RtsBattleEvents.make_pre_damage(source_id, target_id, raw_damage)
	var mutable: MutableEvent = event_processor.process_pre_event(pre_event, world)
	if mutable.cancelled:
		return events_produced

	var final_damage: float = mutable.get_current_value("damage")

	# ===== 应用伤害 (atomic: 应用 hp 扣减 + push event 必须连续) =====
	var hp_before: float = target.attribute_set.hp
	var hp_after: float = max(0.0, hp_before - final_damage)
	target.attribute_set.set_hp_base(hp_after)

	# ===== 广播 attack_resolved (logger 消费, AC3 兵种行为断言用) =====
	var resolved := RtsBattleEvents.make_attack_resolved(
		source_id, target_id,
		attacker.position_2d, target.position_2d,
		int(attacker.unit_class), final_damage,
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
