## TargetSelector - 目标选择器基类
##
## 用于在 Action 执行时选择目标 Actor。
## 框架层只提供基类和过滤组合能力，具体选择逻辑由项目层实现。
## select() 返回 Array[String]，每个元素是 actor_id。
##
## 项目层扩展示例:
##   class AllEnemies extends TargetSelector:
##       func select(ctx: ExecutionContext) -> Array[String]:
##           var battle: MyBattle = ctx.game_state_provider
##           return battle.get_enemy_ids(ctx.ability_ref.owner_actor_id)
##
## 过滤示例:
##   MySelectors.all_enemies().filtered(
##       func(id: String, ctx: ExecutionContext) -> bool:
##           var battle: MyBattle = ctx.game_state_provider
##           return battle.get_actor(id).attribute_set.hp > 0
##   )
class_name TargetSelector
extends RefCounted


## 选择目标（子类必须重写）
## 返回目标 actor_id 列表
func select(_ctx: ExecutionContext) -> Array[String]:
	return []


## 在当前选择结果上应用过滤条件，返回新的选择器
## filter_fn 签名: func(actor_id: String, ctx: ExecutionContext) -> bool
func filtered(filter_fn: Callable) -> TargetSelector:
	return Filtered.new(self, filter_fn)


# ============================================================
# 过滤组合器
# ============================================================

## 在源选择器结果上应用过滤函数
class Filtered extends TargetSelector:
	var _source: TargetSelector
	var _filter: Callable

	func _init(source: TargetSelector, filter_fn: Callable) -> void:
		_source = source
		_filter = filter_fn

	func select(ctx: ExecutionContext) -> Array[String]:
		var result: Array[String] = []
		for id in _source.select(ctx):
			if _filter.call(id, ctx):
				result.append(id)
		return result
