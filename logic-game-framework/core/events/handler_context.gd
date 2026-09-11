## HandlerContext - 处理器上下文
##
## 传递给 Pre 阶段处理器的上下文信息：处理器所属的 owner / ability / config 的 id。
## 只携带 id、不携带 instance：PreEventConfig 的用户 handler 拿到的是按 owner 重建的
## AbilityLifecycleContext（含 instance）；直接注册 PreHandlerRegistration 的底层 handler
## 需要世界状态时按 owner_id 反查。
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
##     # 需要世界状态时按 owner id 反查
##     var battle: HexWorldGameplayInstance = GameWorld.get_instance_of_actor(ctx.owner_id)
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


func _init(
	p_owner_id: String = "",
	p_ability_id: String = "",
	p_config_id: String = ""
) -> void:
	owner_id = p_owner_id
	ability_id = p_ability_id
	config_id = p_config_id


## 转换为 Dictionary（用于日志/调试）
func to_dict() -> Dictionary:
	return {
		"ownerId": owner_id,
		"abilityId": ability_id,
		"configId": config_id,
	}
