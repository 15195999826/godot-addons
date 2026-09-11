## HexBattleGameStateUtils - 项目层的 GameplayInstance 辅助函数
##
## 把 ExecutionContext.instance 收窄成 hex 世界类型，并提供类型安全的 actor 查询。
## 所有函数都是静态的，不保存任何状态。
##
## 使用示例：
## ```gdscript
## var battle := HexBattleGameStateUtils.world(ctx)
## var name := HexBattleGameStateUtils.get_actor_display_name(actor_id, battle)
## ```
class_name HexBattleGameStateUtils


## ctx.instance 收窄为 HexWorldGameplayInstance（或其子类如 HexDemoWorldGameplayInstance / SkillPreviewWorldGI）。
## 类型不符（含 null：owner 未注册进 GameWorld）属接线错误——响亮报错并返回 null。
## 允许 instance 缺席、要静默降级的读点改写 `var battle: HexWorldGameplayInstance = ctx.instance` 再判空。
static func world(ctx: ExecutionContext) -> HexWorldGameplayInstance:
	var battle := ctx.instance as HexWorldGameplayInstance
	if battle == null:
		Log.assert_crash(false, "HexBattleGameStateUtils",
			"ctx.instance 不是 HexWorldGameplayInstance: %s" % ctx.instance)
	return battle


## 获取角色显示名称
## @param actor_id: 角色 ID
## @param battle: HexWorldGameplayInstance 实例(或其子类如 HexDemoWorldGameplayInstance / SkillPreviewWorldGI)
## @return: 角色显示名称，如果无法获取则返回 actor_id 或 "???"
static func get_actor_display_name(actor_id: String, battle: HexWorldGameplayInstance) -> String:
	if actor_id == "":
		return "???"
	if battle != null:
		var actor := battle.get_actor(actor_id)
		if actor != null:
			return actor.get_display_name()
	return actor_id
