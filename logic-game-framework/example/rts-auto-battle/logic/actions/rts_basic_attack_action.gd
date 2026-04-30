## RtsBasicAttackAction - RTS 基本攻击执行器
##
## 不继承 LGF Action.BaseAction: BaseAction 需要 ExecutionContext + TargetSelector + AbilityRef
## 这套抽象, M0 阶段 basic attack 没有 timeline / cost / target_selector 之类的 ability 概念,
## 直接用 helper 路径:
##   attacker → resolve damage → pre_damage event(允许 buff/passive 修改) → 应用 hp 扣减
##           → post_damage / attack_resolved 广播 → 死亡判定 → actor_died event
##
## 为什么仍走 EventProcessor 管线: 让 M1 / 后续 feature 加被动技能(吸血 / 反伤 / 减伤)时
## 已有 hook 入口, 不必回头改 attack action 本身。
##
## 调方(procedure 的 per_tick)在 ai.last_decision == "in_range" + actor.can_attack() 时
## 调 RtsBasicAttackAction.execute(attacker, target, world)。
class_name RtsBasicAttackAction
extends RefCounted


## 执行一次攻击。返回应用的最终伤害(供 logger / 调方记账)。
## 若 pre_damage 被 cancelled 返回 0; 若 attacker / target 已死返回 -1。
static func execute(
	attacker: RtsCharacterActor,
	target: RtsCharacterActor,
	world: RtsWorldGameplayInstance,
) -> float:
	if attacker == null or target == null or world == null:
		return -1.0
	if attacker.is_dead() or target.is_dead():
		return -1.0

	var event_processor: EventProcessor = GameWorld.event_processor
	var event_collector: EventCollector = GameWorld.event_collector

	# ===== 计算原始伤害 =====
	var raw_damage: float = max(1.0, attacker.attribute_set.atk - target.attribute_set.def)

	# ===== Pre 阶段 =====
	# pre_damage event 让 buff / passive 修改 / 取消伤害(M0 PreEvent handler 全空, 一律 PASS)。
	var pre_event := RtsBattleEvents.make_pre_damage(attacker.get_id(), target.get_id(), raw_damage)
	var mutable: MutableEvent = event_processor.process_pre_event(pre_event, world)
	if mutable.cancelled:
		return 0.0

	var final_damage: float = mutable.get_current_value("damage")

	# ===== 应用伤害 =====
	var hp_before: float = target.attribute_set.hp
	var hp_after: float = max(0.0, hp_before - final_damage)
	target.attribute_set.set_hp_base(hp_after)

	# ===== 广播 attack_resolved (logger 消费, AC3 兵种行为断言用) =====
	var resolved := RtsBattleEvents.make_attack_resolved(
		attacker.get_id(),
		target.get_id(),
		attacker.position_2d,
		target.position_2d,
		int(attacker.unit_class),
		final_damage,
	)
	event_collector.push(resolved)

	# ===== 死亡判定 =====
	if hp_after <= 0.0 and not target.is_dead():
		target.mark_dead()
		var died := RtsBattleEvents.make_actor_died(target.get_id(), attacker.get_id())
		event_collector.push(died)

	# ===== Post 阶段 =====
	var post_event := RtsBattleEvents.make_post_damage(
		attacker.get_id(),
		target.get_id(),
		final_damage,
		hp_after,
	)
	event_processor.process_post_event(post_event, world.get_alive_actor_ids(), world)

	return final_damage
