## HexBattleTargetSelectors - 项目层目标选择器
##
## 提供 HexBattle 项目中常用的目标选择器。
## 框架层 TargetSelector 只提供基类 + 过滤组合能力，
## 具体选择逻辑在此实现。
class_name HexBattleTargetSelectors


# ============================================================
# 通用选择器
# ============================================================

## 从当前事件获取目标（event.target_actor_id 或 event.target_actor_ids）
class CurrentTarget extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		var event := ctx.get_current_event()
		if event.is_empty():
			return []
		if event.has("target_actor_ids") and event["target_actor_ids"] is Array:
			var result: Array[String] = []
			for t in event["target_actor_ids"]:
				if t is String:
					result.append(t)
			return result
		if event.has("target_actor_id") and event["target_actor_id"] is String:
			return [event["target_actor_id"]]
		return []


## 选择 Ability 的 owner
class AbilityOwner extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		if ctx.ability_ref != null and not ctx.ability_ref.owner_actor_id.is_empty():
			return [ctx.ability_ref.owner_actor_id]
		return []


## 从当前事件获取来源（event.source_actor_id）
class EventSource extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		var event := ctx.get_current_event()
		if event.is_empty():
			return []
		var source_id: String = event.get("source_actor_id", "")
		if source_id.is_empty():
			return []
		return [source_id]


## 选择 Ability Owner 的所有敌方存活单位
class AllEnemies extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		if ctx.ability_ref == null or ctx.ability_ref.owner_actor_id.is_empty():
			return []
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return []
		var owner := battle.get_actor(ctx.ability_ref.owner_actor_id)
		if owner == null:
			return []
		var owner_team := owner.get_team_id()
		var result: Array[String] = []
		for actor in battle.get_alive_actors():
			if actor.get_team_id() != owner_team:
				result.append(actor.get_id())
		return result


## 固定目标选择器（用于测试或预设目标）
class Fixed extends TargetSelector:
	var _targets: Array[String]

	func _init(targets: Array[String]) -> void:
		_targets = targets

	func select(_ctx: ExecutionContext) -> Array[String]:
		return _targets


# ============================================================
# 工厂方法
# ============================================================

## 从当前事件获取目标
static func current_target() -> CurrentTarget:
	return CurrentTarget.new()


## 选择 Ability owner
static func ability_owner() -> AbilityOwner:
	return AbilityOwner.new()


## 从当前事件获取来源
static func event_source() -> EventSource:
	return EventSource.new()


## 所有敌方存活单位
static func all_enemies() -> AllEnemies:
	return AllEnemies.new()


## 固定目标
static func fixed(targets: Array[String]) -> Fixed:
	return Fixed.new(targets)
