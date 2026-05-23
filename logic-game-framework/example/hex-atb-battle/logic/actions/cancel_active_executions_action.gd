## CancelActiveExecutionsAction - 取消目标当前 active execution instance
##
## 对每个目标 actor 遍历 ability_set, 过滤 ability_tags.has("active"), 调 cancel_all_executions()。
##
## 边界:
## - 已触发过的 timeline action 不回滚; cancel 只让未触发的 keyframe 不再 fire
## - 跳过 caller ability 自身, 避免 Stun buff 把自己干掉 (Stun buff 的 NoInstance lifecycle
##   还没结束)
## - 不影响 NoInstance / PreEvent / buff tick / DOT / deathrattle / post-damage 这类被动响应
##   (它们的 ability 不带 "active" tag)
## - GameWorld.get_actor → ability_set, 因此可在 lifecycle (game_state_provider=null) 跑
##
## V1 用例: HexBattleStunBuff on_apply 取消目标当前 in-flight active skill/strike/move execution。
class_name HexBattleCancelActiveExecutionsAction
extends Action.PrimitiveAction


const ACTIVE_TAG := "active"


func _init(target_selector: TargetSelector) -> void:
	super._init(target_selector)
	type = "cancel_active_executions"


func execute(ctx: ExecutionContext) -> ActionResult:
	var self_ability_id := ""
	if ctx.ability_ref != null:
		self_ability_id = ctx.ability_ref.id
	for target_id in get_targets(ctx):
		var actor := GameWorld.get_actor(target_id)
		var ability_set := IAbilitySetOwner.get_ability_set(actor)
		if ability_set == null:
			continue
		for ability in ability_set.get_abilities():
			if ability.id == self_ability_id:
				continue
			if ability.is_expired():
				continue
			if not ability.has_ability_tag(ACTIVE_TAG):
				continue
			if ability.get_executing_instances().is_empty():
				continue
			ability.cancel_all_executions()
	return ActionResult.create_success_result([])
