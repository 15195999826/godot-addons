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
# + CooldownCondition + TimedCooldownCost(cd_ms)。当前 28 个技能逐文件手抄这 4 行
# (这正是让 strike 漏 silence 这类漂移无法被结构区分的根因)。新技能应改用下面的
# helper; 既有技能的迁移留待专门一轮 (见 docs/README.md 已知债务: 28 技能迁移到 condition bundle helper)。
#
# 用法: ActiveUseConfig.builder().timeline_id(...).on_tag(...) |> standard_active_conditions(builder, cd_ms)
# 注意 builder 链式返回 self, helper 直接在传入的 builder 上 apply 后返回它。

## 标准主动技能门控: cant_act + silence + cooldown condition + timed cooldown cost。
static func apply_standard_active_gating(builder, cooldown_ms: float):
	return (builder
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(CooldownCondition.new())
		.cost(TimedCooldownCost.new(cooldown_ms)))


## basic-attack 门控 (silence-exempt): cant_act + cooldown, 不含 silence。
## 普攻不受沉默是 ARPG/MOBA 惯例 (强调: 这是有意豁免, 非遗漏)。Strike 用。
static func apply_basic_attack_gating(builder, cooldown_ms: float):
	return (builder
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(CooldownCondition.new())
		.cost(TimedCooldownCost.new(cooldown_ms)))
