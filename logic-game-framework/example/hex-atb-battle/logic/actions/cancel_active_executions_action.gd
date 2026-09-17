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
## - 不打断在飞的 Move: Move 的 tag 是 action + move、不带 "active" —— 已起手的那一步 (200ms) 照常走完,
##   cant_act 只拦下一次起手。前端凭 move_start 播整段位移, 逻辑侧中途取消移动会让表现与棋盘错位
## - 经 GameWorld.get_actor 取 ability_set、不读 ctx.instance; 被取消 execution 的 on_cancel 由 execution 按 owner 反查 instance
##
## V1 用例: HexBattleStunBuff on_apply 取消目标当前 in-flight 的主动技能 (含普攻 strike) execution。
class_name HexBattleCancelActiveExecutionsAction
extends Action.BaseAction


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
		var ability_set := BattleActor.ability_set_of(actor)
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
