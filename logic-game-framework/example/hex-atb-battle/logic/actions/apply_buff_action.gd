## ApplyBuffAction - 对每个目标 grant 指定 buff ability
##
## 职责极简：对 target_selector 选出的每个 CharacterActor，实例化 buff_config 并 grant 给它。
##
## Grant 同时广播 ABILITY_GRANTED_EVENT，带 GRANTED_SELF trigger 的 component 自激活（如 DOT buff 启动 loop）。
## 不做任何幂等/合并逻辑 —— 同 target 被重复 grant 同 config 的 buff 时，会产生多个独立 buff 实例并存。
## 如果需要"叠层 / 拒绝重复 / 刷新时间"语义，由 buff 自己通过额外 component 或 PreEvent 处理。
class_name HexBattleApplyBuffAction
extends Action.BaseAction


var _buff_config: AbilityConfig


func _init(target_selector: TargetSelector, buff_config: AbilityConfig) -> void:
	super._init(target_selector)
	type = "apply_buff"
	_buff_config = buff_config


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
		var new_buff := Ability.new(_buff_config, target_id, source_id)
		ability_set.grant_ability(new_buff, battle)

	return ActionResult.create_success_result([], { "buff_config_id": _buff_config.config_id })
