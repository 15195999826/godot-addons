## HexBattleDamageUtils - 伤害流程公共工具
##
## 提取 DamageAction 和 ReflectDamageAction 共享的
## 「push 伤害事件 → 扣血 → 日志 → 死亡检测 → 死亡事件广播 → 移除角色」流程。
##
## 注意：**不包含 post damage 广播**。
## 调用方需要在回调等后续逻辑完成后，自行调用
## [code]process_post_event(damage_event_dict, alive_actor_ids, battle)[/code]。
## 这是因为 DamageAction 需要在 post 之前执行 on_hit/on_critical/on_kill 回调。
##
## 所有函数都是静态的，不保存任何状态。
class_name HexBattleDamageUtils


## apply_damage 的返回结果
class DamageResult:
	## push 后的伤害事件字典（供回调、post 广播等后续流程使用）
	var damage_event_dict: Dictionary = {}
	## 本次调用产生的所有事件字典（含 damage_event_dict 和可能的 death_event）
	var all_events: Array[Dictionary] = []
	## 目标是否死亡
	var target_killed: bool = false


## 对单个目标应用伤害并处理死亡
##
## 执行流程（原子操作）：
## 1. Push 伤害事件到 event_collector
## 2. 扣血：target.attribute_set.set_hp_base(hp - damage)
## 3. 日志：battle.logger.damage_dealt(...)
## 4. 死亡检测：check_death() → push death_event → process_post_event(death) → remove_actor
##
## 不包含 post damage 广播，由调用方自行处理。
##
## @param damage_event: 强类型伤害事件（由调用方构造）
## @param alive_actor_ids: 调用时缓存的存活 actor ID 列表
## @param ctx: 执行上下文
## @param battle: 战斗实例
## @return: DamageResult
static func apply_damage(
	damage_event: BattleEvents.DamageEvent,
	alive_actor_ids: Array[String],
	ctx: ExecutionContext,
	battle: HexBattle,
) -> DamageResult:
	var result := DamageResult.new()
	var event_processor := GameWorld.event_processor
	var target_id := damage_event.target_actor_id
	var source_actor_id := damage_event.source_actor_id
	var damage := damage_event.damage
	var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
	var damage_type_str := BattleEvents._damage_type_to_string(damage_event.damage_type)

	# ========== Push 伤害事件 ==========
	var damage_dict: Dictionary = ctx.event_collector.push(damage_event.to_dict())
	result.damage_event_dict = damage_dict
	result.all_events.append(damage_dict)

	var target_actor := battle.get_actor(target_id)
	if target_actor != null:
		# ========== 扣血 ==========
		target_actor.attribute_set.set_hp_base(target_actor.attribute_set.hp - damage)

		var suffix := " (反伤)" if damage_event.is_reflected else ""
		print("  [伤害] %s 受到 %.0f 伤害, HP: %.0f%s" % [
			target_name, damage, target_actor.attribute_set.hp, suffix
		])

		if battle.logger != null:
			battle.logger.damage_dealt(
				source_actor_id, target_id, damage, damage_type_str,
				damage_event.is_reflected
			)

		# ========== 死亡检测 ==========
		if target_actor.check_death():
			print("  [死亡] %s 已阵亡" % target_name)

			if battle.logger != null:
				battle.logger.actor_died(target_id, source_actor_id)

			var death_event := BattleEvents.DeathEvent.create(target_id, source_actor_id)
			var death_dict: Dictionary = ctx.event_collector.push(death_event.to_dict())
			result.all_events.append(death_dict)
			result.target_killed = true

			if alive_actor_ids.size() > 0:
				event_processor.process_post_event(death_dict, alive_actor_ids, battle)

			battle.remove_actor(target_id)

	return result


## 广播 post damage 事件
##
## 从 apply_damage 中分离出来，让调用方控制时机。
## DamageAction 需要在 post 之前执行回调，ReflectDamageAction 则直接 post。
static func broadcast_post_damage(
	damage_event_dict: Dictionary,
	alive_actor_ids: Array[String],
	battle: HexBattle,
) -> void:
	if alive_actor_ids.size() > 0:
		GameWorld.event_processor.process_post_event(damage_event_dict, alive_actor_ids, battle)
