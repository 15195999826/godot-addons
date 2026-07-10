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


# ========== 标准门控 bundle helper ==========
#
# 标准主动技能门控四件套 = NoTagCondition(cant_act) + NoTagCondition(cant_use_skill)
# + CooldownCondition + TimedCooldownCost(cd_ms)。全部 active 技能已统一走 helper
# (2026-07-03 线 3 轮 D 迁移完成), 门控声明单点化 —— strike 漏 silence 这类漂移
# 从此可结构区分 (basic attack 的 silence 豁免 = 显式调 apply_basic_attack_gating)。
#
# 用法(链头包装, helper 在传入 builder 上 apply 后返回它, 后续继续链):
#   .active_use(
#       HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
#       .timeline(...)
#       .on_tag(...)
#       .build()
#   )

## 标准主动技能门控: cant_act + silence + cooldown condition + timed cooldown cost。
## 签名必须强类型: 无标注时返回值退化 Variant, 调用方后续链式 on_timeline_start([...])
## 变动态派发, 数组字面量不再协变成 Array[Action.BaseAction], 运行时类型错。
static func apply_standard_active_gating(
	builder: ActiveUseConfig.ActiveUseConfigBuilder,
	cooldown_ms: float,
) -> ActiveUseConfig.ActiveUseConfigBuilder:
	return (builder
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(CooldownCondition.new())
		.cost(TimedCooldownCost.new(cooldown_ms)))


## basic-attack 门控 (silence-exempt): cant_act + cooldown, 不含 silence。
## 普攻不受沉默是 ARPG/MOBA 惯例 (强调: 这是有意豁免, 非遗漏)。Strike 用。
static func apply_basic_attack_gating(
	builder: ActiveUseConfig.ActiveUseConfigBuilder,
	cooldown_ms: float,
) -> ActiveUseConfig.ActiveUseConfigBuilder:
	return (builder
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(CooldownCondition.new())
		.cost(TimedCooldownCost.new(cooldown_ms)))
