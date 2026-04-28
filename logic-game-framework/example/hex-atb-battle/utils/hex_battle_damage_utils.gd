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
## 1. 护盾结算：HexBattleShieldResolver.resolve() 算 actual_life_damage + 消耗记录，提交容量变更
## 2. 把吸收信息写回 damage_event（shield_absorbed / actual_life_damage / consumption_records）
## 3. Push 伤害事件到 event_collector
## 4. 扣血：target.attribute_set.set_hp_base(hp - actual_life_damage)
## 5. 日志：battle.logger.damage_dealt(...)
## 6. 触发破裂回调：对每个 broken=true 的护盾 push shield_broken event → call on_break → expire ability
## 7. 死亡检测：check_death() → push death_event → process_post_event(death) → remove_actor
##
## 关键顺序约束：on_break 必须在 remove_actor 之前调用，否则爆炸类回调拿不到 owner 上下文。
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
	battle: HexWorldGameplayInstance,
) -> DamageResult:
	var result := DamageResult.new()
	var event_processor := GameWorld.event_processor
	var target_id := damage_event.target_actor_id
	var source_actor_id := damage_event.source_actor_id
	var modified_damage := damage_event.damage
	var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
	var damage_type_str := BattleEvents._damage_type_to_string(damage_event.damage_type)

	var target_actor := battle.get_actor(target_id)

	# ========== 护盾结算（在 push event / 扣血之前） ==========
	var shield_result: HexBattleShieldResolver.Result = null
	if target_actor != null:
		shield_result = HexBattleShieldResolver.resolve(
			target_actor, modified_damage, damage_type_str
		)
		damage_event.shield_absorbed = shield_result.shield_absorbed
		damage_event.actual_life_damage = shield_result.life_damage
		damage_event.consumption_records = shield_result.consumption_records.duplicate(true)
	else:
		damage_event.shield_absorbed = 0.0
		damage_event.actual_life_damage = modified_damage
		damage_event.consumption_records = []

	var actual_life_damage := damage_event.actual_life_damage
	var shield_absorbed := damage_event.shield_absorbed

	# ========== Push 伤害事件 ==========
	var damage_dict: Dictionary = ctx.event_collector.push(damage_event.to_dict())
	result.damage_event_dict = damage_dict
	result.all_events.append(damage_dict)

	if target_actor != null:
		# ========== 扣血（按实际生命伤害） ==========
		# 走 HexBattleActor.get_attribute_set() 拿基类视图: 平权处理 character + environment。
		var target_attrs := target_actor.get_attribute_set()
		target_attrs.set_hp_base(target_attrs.hp - actual_life_damage)

		var suffix := " (反伤)" if damage_event.is_reflected else ""
		var absorb_text := ""
		if shield_absorbed > 0.0:
			absorb_text = " (护盾吸收 %.0f)" % shield_absorbed
		print("  [伤害] %s 受到 %.0f 伤害, HP: %.0f%s%s" % [
			target_name, actual_life_damage, target_attrs.hp, absorb_text, suffix
		])

		if battle.logger != null:
			battle.logger.damage_dealt(
				source_actor_id, target_id, actual_life_damage, damage_type_str,
				damage_event.is_reflected
			)

		# ========== 护盾破裂回调（在死亡 / remove_actor 之前） ==========
		if shield_result != null and not shield_result.consumption_records.is_empty():
			_process_broken_shields(
				shield_result.consumption_records,
				target_id,
				source_actor_id,
				damage_type_str,
				ctx,
				battle,
				result
			)

		# ========== 死亡检测 ==========
		# 死者留在 world 里(actor.is_dead() 仍为 true), 不调 world.remove_actor:
		# - WorldView 的 unit view 不被回收, BattleAnimator 后续 actor_state_changed
		#   (is_alive=false) signal 能找到 view 触发 _play_death_animation 死亡 tween。
		# - "死亡" != "离开 world"。死亡只是行为禁止(不行动/不被选作目标/不占格),
		#   离开 world 是重启战斗 / 永久退场时的另外动作。
		# - 存活判定(get_alive_actor_ids / _check_battle_end / AI 候选)全走 is_dead(),
		#   不依赖 world.has_actor, 留尸体不污染战斗逻辑。
		# - grid 占用仍要清: 否则活人 move_occupant 到尸体格会触发 apply_move_action
		#   的 UNEXPECTED 兜底 push_error。
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

			_clear_grid_footprint(battle, target_actor)

	return result


## 死亡后清掉死者在 grid 上的占用 / 预订, 让活人可以走到尸体格上。
## 不动 actor 本身, 不动 world registry —— 这是 "死了但还在 world" 的中间态。
## 接 HexBattleActor: 平权处理 character + environment。
static func _clear_grid_footprint(battle: HexWorldGameplayInstance, dead_actor: HexBattleActor) -> void:
	if battle == null or battle.grid == null or dead_actor == null:
		return
	var pos := dead_actor.hex_position
	if pos != null and pos.is_valid():
		battle.grid.remove_occupant(pos)
	for coord in battle.grid.get_all_coords():
		if battle.grid.get_reservation(coord) == dead_actor.get_id():
			battle.grid.cancel_reservation(coord)


## 对每个 broken=true 的消耗记录：push shield_broken event → 调 on_break 回调 → expire ability
##
## V1 基础 Ward 的 on_break 为空，本函数仅产生 shield_broken event 用于回放可见。
## 回调签名：func(record: Dictionary, ctx: ExecutionContext, battle: HexWorldGameplayInstance) -> void
## 回调内部如要 push 新事件，自行调用 ctx.event_collector.push 或触发新的 damage 流程。
static func _process_broken_shields(
	consumption_records: Array[Dictionary],
	target_id: String,
	attacker_id: String,
	damage_type_str: String,
	ctx: ExecutionContext,
	battle: HexWorldGameplayInstance,
	result: DamageResult
) -> void:
	var ability_set: AbilitySet = null
	var target_actor := battle.get_actor(target_id)
	if target_actor != null and "ability_set" in target_actor:
		ability_set = target_actor.get("ability_set") as AbilitySet
	if ability_set == null:
		return

	for record in consumption_records:
		if not record.get("broken", false):
			continue
		var shield_ability_id: String = record.get("shield_ability_id", "") as String
		if shield_ability_id.is_empty():
			continue

		# 1. push shield_broken 事件（回放可见）
		var broken_event := BattleEvents.ShieldBrokenEvent.create(
			target_id,
			attacker_id,
			shield_ability_id,
			record.get("shield_config_id", "") as String,
			damage_type_str,
			record.get("absorbed", 0.0) as float
		)
		var broken_dict: Dictionary = ctx.event_collector.push(broken_event.to_dict())
		result.all_events.append(broken_dict)

		# 2. 调用 on_break 回调（用户可在内部 push 新事件，并返回事件 dict 数组以并入本次 ActionResult）
		var ability := ability_set.find_ability_by_id(shield_ability_id)
		if ability != null:
			var shield_component: HexBattleShieldComponent = null
			for component in ability.get_all_components():
				if component is HexBattleShieldComponent:
					shield_component = component as HexBattleShieldComponent
					break
			if shield_component != null and shield_component.on_break.is_valid():
				var callback_return: Variant = shield_component.on_break.call(record, ctx, battle)
				if callback_return is Array:
					for ev in (callback_return as Array):
						if ev is Dictionary:
							result.all_events.append(ev as Dictionary)
			# 3. expire 该 ability（让 AbilitySet 在下次 _process_abilities 时 revoke）
			if not ability.is_expired():
				ability.expire(HexBattleShieldComponent.EXPIRE_REASON_BROKEN)


## 广播 post damage 事件
##
## 从 apply_damage 中分离出来，让调用方控制时机。
## DamageAction 需要在 post 之前执行回调，ReflectDamageAction 则直接 post。
static func broadcast_post_damage(
	damage_event_dict: Dictionary,
	alive_actor_ids: Array[String],
	battle: HexWorldGameplayInstance,
) -> void:
	if alive_actor_ids.size() > 0:
		GameWorld.event_processor.process_post_event(damage_event_dict, alive_actor_ids, battle)
