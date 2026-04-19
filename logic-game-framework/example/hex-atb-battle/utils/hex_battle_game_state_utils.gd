## HexBattleGameStateUtils - 项目层的 GameState 辅助函数
##
## 提供类型安全的 game_state_provider 访问方法。
## 所有函数都是静态的，不保存任何状态。
##
## 使用示例：
## ```gdscript
## var name := HexBattleGameStateUtils.get_actor_display_name(actor_ref, battle)
## ```
class_name HexBattleGameStateUtils


## 获取角色显示名称
## @param actor_id: 角色 ID
## @param game_state_provider: HexWorldGameplayInstance 实例(或其子类如 HexBattle/SkillPreviewWorldGI)
## @return: 角色显示名称，如果无法获取则返回 actor_id 或 "???"
static func get_actor_display_name(actor_id: String, game_state_provider: HexWorldGameplayInstance) -> String:
	if actor_id == "":
		return "???"
	if game_state_provider != null:
		var actor := game_state_provider.get_actor(actor_id)
		if actor != null:
			return actor.get_display_name()
	return actor_id


## 检查角色是否已死亡
## @param actor_id: 角色 ID
## @param game_state_provider: HexWorldGameplayInstance 实例(或其子类如 HexBattle/SkillPreviewWorldGI)
## @return: 角色是否已死亡，如果无法获取角色则返回 false
static func is_actor_dead(actor_id: String, game_state_provider: HexWorldGameplayInstance) -> bool:
	if game_state_provider == null:
		return false
	var actor := game_state_provider.get_actor(actor_id)
	if actor != null:
		return actor.attribute_set.hp <= 0
	return true
