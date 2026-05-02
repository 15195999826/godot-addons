## RtsTargetSelectors - RTS 项目层目标选择器
##
## 框架层 TargetSelector 只提供基类 + 过滤组合能力, 具体选择逻辑在此实现。
## 与 hex example 的 HexBattleTargetSelectors 同构 — 但 RTS basic attack 没有 event
## 链(目标来自 AI 计算的 current_target_id 字段, 不是从触发事件读), 所以选择器走
## actor 字段查询路径。
##
## P1.4 此文件目前仅含 CurrentUnitTarget; Phase 2 会随 Activity / AutoTarget 扩展。
class_name RtsTargetSelectors


# ============================================================
# 通用选择器
# ============================================================

## 取 ability owner 的 current_target_id (RtsBattleActor.current_target_id 字段)。
## RTS basic attack 在 procedure 主循环里调时, ability_ref.owner_actor_id 已经写为 attacker id;
## 此选择器读 attacker.current_target_id (P1.5 后由 RtsUnitController 维护; P2.8 起建筑也写)。
##
## P2.8: attacker / target 都接受 RtsBattleActor (单位 + 建筑); RtsBasicAttackAction 后续按
## get_atk()/get_def() 等 virtual accessor 取数值。
class CurrentUnitTarget extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		if ctx.ability_ref == null:
			return []
		var owner_id: String = ctx.ability_ref.owner_actor_id
		if owner_id.is_empty():
			return []
		var world := ctx.game_state_provider as RtsWorldGameplayInstance
		if world == null:
			return []
		var attacker := world.get_actor(owner_id) as RtsBattleActor
		if attacker == null or attacker.is_dead():
			return []
		var target_id: String = attacker.current_target_id
		if target_id.is_empty():
			return []
		# 验证 target 仍存活, 避免对死单位 push 事件
		var target := world.get_actor(target_id) as RtsBattleActor
		if target == null or target.is_dead():
			return []
		var result: Array[String] = []
		result.append(target_id)
		return result


# ============================================================
# 工厂方法
# ============================================================

## 取 attacker 的 current_target_id 单目标
static func current_unit_target() -> CurrentUnitTarget:
	return CurrentUnitTarget.new()
