## Dota2AttackCooldown - 基础攻击冷却（Ability 执行路径，非 controller ad-hoc 状态）
##
## controller-intent-model.md：cooldown / cast timing 是 Ability/AbilitySet 执行状态，
## 不是 controller 自管字段。基础攻击 Ability 用：
##   condition = NoTagCondition(COOLDOWN_TAG)  —— cooldown 期间不可再激活
##   cost      = TimedCooldownCost             —— 激活时上 attack_interval_ms 时长 tag
## attack_interval_ms 从 owner 的 Dota2UnitAttributeSet 实时读（attack speed buff 未来
## 改它即自动生效）。tag 走 ability_set.add_auto_duration_tag，ability_set.tick 自动清。
class_name Dota2AttackCooldown
extends RefCounted


const COOLDOWN_TAG := "dota2_basic_attack_cd"


## 激活时按 owner 当前 attack_interval_ms 上一条自动过期 cooldown tag。
class TimedCooldownCost extends Cost:
	func _init() -> void:
		type = "dota2_attack_cooldown"

	func can_pay(_ctx: AbilityLifecycleContext, _event_dict: Dictionary, _game_state: Variant) -> bool:
		return true

	func pay(ctx: AbilityLifecycleContext, _event_dict: Dictionary, _game_state: Variant) -> void:
		if ctx.ability_set == null:
			return
		var interval_ms := 1000.0
		var attrs: Dota2UnitAttributeSet = ctx.attribute_set as Dota2UnitAttributeSet
		if attrs != null:
			interval_ms = attrs.attack_interval_ms
		ctx.ability_set.add_auto_duration_tag(COOLDOWN_TAG, interval_ms)

	func get_fail_reason(_ctx: AbilityLifecycleContext, _event_dict: Dictionary, _game_state: Variant) -> String:
		return ""
