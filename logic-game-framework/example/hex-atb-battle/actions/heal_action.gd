## HealAction - 治疗 Action
##
## ========== 设计原则 ==========
##
## Action 是原子操作单元：push 事件 + 应用状态 + post 事件 必须连续执行。
## 与 DamageAction 遵循相同的设计，确保状态同步的原子性。
##
## ========== 执行流程 ==========
##
## 1. 产生治疗事件 + 立即应用治疗（原子操作）：
##    - ctx.event_collector.push(heal_event)  ← 事件入队（录像用）
##    - target.attribute_set.set_hp_base(new_hp) ← 立即加血
##
## 2. 处理回调：on_heal / on_overheal
##
## 3. Post 阶段：触发治疗相关被动响应
##
## ========== 支持的回调 ==========
##
## - on_heal: 每次治疗时触发
## - on_overheal: 过量治疗时触发（治疗量超过目标缺失生命值）
##
class_name HexBattleHealAction
extends Action.BaseAction


var _heal_amount: FloatResolver

# 回调列表
var _on_heal_callbacks: Array[Action.BaseAction] = []
var _on_overheal_callbacks: Array[Action.BaseAction] = []


func _init(
	target_selector: TargetSelector,
	heal_amount: FloatResolver
) -> void:
	super._init(target_selector)
	type = "heal"
	_heal_amount = heal_amount


## 重写 _freeze 以冻结回调 Action
func _freeze() -> void:
	super._freeze()
	for callback in _on_heal_callbacks:
		callback._freeze()
	for callback in _on_overheal_callbacks:
		callback._freeze()


# ============================================================
# 回调注册（链式调用）
# ============================================================

## 注册治疗回调
func on_heal(action: Action.BaseAction) -> HexBattleHealAction:
	_on_heal_callbacks.append(action)
	return self


## 注册过量治疗回调
func on_overheal(action: Action.BaseAction) -> HexBattleHealAction:
	_on_overheal_callbacks.append(action)
	return self


# ============================================================
# 执行
# ============================================================

func execute(ctx: ExecutionContext) -> ActionResult:
	var source_actor_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	var heal_amount := _heal_amount.resolve(ctx)
	
	var target_ids: Array[String] = []
	for t in targets:
		target_ids.append(t)
	var source_id_for_log := source_actor_id if source_actor_id != "" else "???"
	print("  [HealAction] %s 对 [%s] 治疗 %.0f HP" % [source_id_for_log, ", ".join(target_ids), heal_amount])
	
	var all_events: Array[Dictionary] = []
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var event_processor := GameWorld.event_processor
	var alive_actor_ids := battle.get_alive_actor_ids()
	
	for target_id in targets:
		var overheal := _calculate_overheal(target_id, heal_amount, ctx)
		
		var event := BattleEvents.HealEvent.create(
			target_id,
			heal_amount,
			source_actor_id
		)
		var heal_event: Dictionary = ctx.event_collector.push(event.to_dict())
		
		if overheal > 0:
			heal_event["overheal"] = overheal
		
		all_events.append(heal_event)
		
		var target_actor := battle.get_actor(target_id)
		if target_actor != null:
			var old_hp: float = target_actor.attribute_set.hp
			var max_hp: float = target_actor.attribute_set.max_hp
			var new_hp := minf(old_hp + heal_amount, max_hp)
			target_actor.attribute_set.set_hp_base(new_hp)
			
			var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
			print("  [治疗] %s 恢复 %.0f HP, HP: %.0f -> %.0f" % [
				target_name, heal_amount, old_hp, new_hp
			])
			
			if battle.logger != null:
				battle.logger.heal_applied(source_actor_id, target_id, heal_amount)
		
		var callback_events := _process_callbacks(heal_event, overheal, ctx)
		all_events.append_array(callback_events)
		
		if alive_actor_ids.size() > 0:
			event_processor.process_post_event(heal_event, alive_actor_ids, battle)
	
	return ActionResult.create_success_result(all_events, { "heal_amount": heal_amount })


# ============================================================
# 回调处理
# ============================================================

func _process_callbacks(heal_event: Dictionary, overheal: float, ctx: ExecutionContext) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var callback_ctx := ExecutionContext.create_callback_context(ctx, heal_event)
	
	# on_heal: 每次治疗都触发
	for callback in _on_heal_callbacks:
		var result := callback.execute(callback_ctx)
		callback._verify_unchanged()
		if result != null and result.event_dicts:
			events.append_array(result.event_dicts)
	
	# on_overheal: 仅过量治疗时触发
	if overheal > 0:
		for callback in _on_overheal_callbacks:
			var result := callback.execute(callback_ctx)
			callback._verify_unchanged()
			if result != null and result.event_dicts:
				events.append_array(result.event_dicts)
	
	return events


func _calculate_overheal(target_actor_id: String, heal_amount: float, ctx: ExecutionContext) -> float:
	if ctx.game_state_provider == null:
		return 0.0
	
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var target_actor := battle.get_actor(target_actor_id)
	if target_actor != null:
		var current_hp: float = target_actor.attribute_set.hp
		var max_hp: float = target_actor.attribute_set.max_hp
		
		if max_hp > 0:
			var missing_hp: float = max_hp - current_hp
			if heal_amount > missing_hp:
				return heal_amount - missing_hp
	
	return 0.0
