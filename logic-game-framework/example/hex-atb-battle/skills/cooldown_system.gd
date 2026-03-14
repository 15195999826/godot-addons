## 冷却系统 - 条件和消耗
##
## 实现技能冷却的条件检查和消耗支付
## 注意：此模块假设 AbilitySet 是 BattleAbilitySet 类型
class_name HexBattleCooldownSystem


# ========== 冷却就绪条件 ==========

## 检查技能是否不在冷却中
class CooldownCondition:
	extends Condition
	
	func get_condition_type() -> String:
		return "cooldown_ready"
	
	func check(ctx: AbilityLifecycleContext, _event: Dictionary, _game_state: Variant) -> bool:
		var battle_ability_set := ctx.ability_set as BattleAbilitySet
		Log.assert_crash(battle_ability_set != null, "CooldownCondition", "requires BattleAbilitySet")
		return not battle_ability_set.is_on_cooldown(ctx.ability.config_id)
	
	func get_fail_reason(_ctx: AbilityLifecycleContext, _event: Dictionary, _game_state: Variant) -> String:
		return "技能冷却中"


# ========== 定时冷却消耗 ==========

## 支付冷却时间
class TimedCooldownCost:
	extends Cost
	
	var _duration: float
	
	func _init(duration: float) -> void:
		type = "timed_cooldown"
		_duration = duration
	
	func can_pay(_ctx: AbilityLifecycleContext, _event: Dictionary, _game_state: Variant) -> bool:
		# 冷却消耗总是可以支付（条件检查在 CooldownCondition 中）
		return true
	
	func pay(ctx: AbilityLifecycleContext, _event: Dictionary, _game_state: Variant) -> void:
		var battle_ability_set := ctx.ability_set as BattleAbilitySet
		Log.assert_crash(battle_ability_set != null, "TimedCooldownCost", "requires BattleAbilitySet")
		battle_ability_set.start_cooldown(ctx.ability.config_id, _duration)
	
	func get_fail_reason(_ctx: AbilityLifecycleContext, _event: Dictionary, _game_state: Variant) -> String:
		return "冷却消耗失败"


# ========== 便捷别名 ==========

## 创建冷却条件
static func create_cooldown_condition() -> CooldownCondition:
	return CooldownCondition.new()


## 创建定时冷却消耗
static func create_timed_cooldown_cost(duration: float) -> TimedCooldownCost:
	return TimedCooldownCost.new(duration)
