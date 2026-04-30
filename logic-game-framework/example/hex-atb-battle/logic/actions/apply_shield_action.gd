## ApplyShieldAction - 对每个目标 grant 指定护盾 buff ability
##
## V1 仅支持 stacking_policy = "independent"：重复施放永远产生独立护盾实例并存，
## 由 ShieldResolver 按 priority desc / grant_index desc / id asc 串行消耗。
##
## 与 ApplyBuffAction 几乎一致，单独成类是为了：
##   1. 语义清晰（grant 的是护盾，不是普通 buff）
##   2. 后续 V2 接 stacking_policy = refresh / add / replace / burst_then_replace 时
##      在本 Action 内查同 config_id 已有护盾并按策略处理（不污染 ApplyBuffAction）
class_name HexBattleApplyShieldAction
extends Action.BaseAction


var _shield_config: AbilityConfig


func _init(target_selector: TargetSelector, shield_config: AbilityConfig) -> void:
	super._init(target_selector)
	type = "apply_shield"
	_shield_config = shield_config


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	if battle == null:
		return ActionResult.create_success_result([], {})

	var source_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)

	for target_id in targets:
		var target_actor := battle.get_actor(target_id)
		if target_actor == null or not (target_actor is CharacterActor):
			continue
		var ability_set := (target_actor as CharacterActor).get_ability_set()
		if ability_set == null:
			continue
		var new_shield := Ability.new(_shield_config, target_id, source_id)
		ability_set.grant_ability(new_shield, battle)

	return ActionResult.create_success_result([], { "shield_config_id": _shield_config.config_id })
