## HandlerContext - 处理器上下文
##
## 传递给 Pre 阶段处理器的上下文信息。
## 包含处理器所属的 owner、ability 等信息，以及游戏状态访问。
##
## ========== 使用示例 ==========
##
## @example 在处理器中使用上下文
## ```gdscript
## func _handle_pre_damage(mutable: MutableEvent, ctx: HandlerContext) -> Intent:
##     # 检查是否是自己受到伤害
##     var target_id: String = mutable.original.get("target_actor_id", "")
##     if target_id != ctx.owner_id:
##         return Intent.pass_through()
##
##     # 使用游戏状态
##     var battle: HexBattle = ctx.game_state
##     # ...
## ```
class_name HandlerContext
extends RefCounted


## 处理器所属的 Actor ID
var owner_id: String

## 处理器所属的 Ability ID
var ability_id: String

## 处理器所属的 Ability Config ID
var config_id: String

## 游戏状态提供者（类型由游戏层决定）
var game_state: Variant


func _init(
	p_owner_id: String = "",
	p_ability_id: String = "",
	p_config_id: String = "",
	p_game_state: Variant = null
) -> void:
	owner_id = p_owner_id
	ability_id = p_ability_id
	config_id = p_config_id
	game_state = p_game_state


## 转换为 Dictionary（用于日志/调试）
func to_dict() -> Dictionary:
	return {
		"ownerId": owner_id,
		"abilityId": ability_id,
		"configId": config_id,
	}
