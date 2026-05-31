## Dota2TargetingSystem - aggro 扫描 + 目标有效性（无状态 helper）
##
## README.md（Controller / Intent 模型 节）「Decision Intervals」：lane creep march 时每隔几 tick
## 做一次 aggro 扫描；AttackTargetIntent 有效期间**不**周期换目标（不抖）。本系统只
## 提供"事实查询"，不持状态、不 mutate —— latch 由 controller 的 intent 生命周期负责。
##
## 共享对象无状态（enforcing-lgf）：所有方法 static，无实例字段。
class_name Dota2TargetingSystem
extends RefCounted


## 在 unit.aggro_range 内找最近的存活敌方 unit；无则返回 ""。
## 决定性：world.get_alive_units() 顺序跨 run 稳定 → 同距离时取先遍历到的。
static func find_aggro_target(world: Dota2WorldGameplayInstance, unit: Dota2UnitActor) -> String:
	if world == null or unit == null or unit.is_dead():
		return ""
	var aggro: float = unit.attribute_set.aggro_range
	var aggro_sq := aggro * aggro
	var best_id := ""
	var best_dist_sq := aggro_sq
	for other in world.get_alive_units():
		if other.get_team_id() == unit.get_team_id():
			continue
		var d2: float = unit.position_2d.distance_squared_to(other.position_2d)
		if d2 <= best_dist_sq:
			best_dist_sq = d2
			best_id = other.get_id()
	return best_id


## 目标是否仍是合法的攻击对象（存在 / 存活 / 敌方）。
## controller 据此 latch：只要 valid 就不换目标（避免周期扫描导致抖动）。
static func is_target_valid(world: Dota2WorldGameplayInstance, unit: Dota2UnitActor, target_id: String) -> bool:
	if world == null or unit == null or target_id == "":
		return false
	var target: Dota2BattleActor = world.get_actor(target_id)
	if target == null or target.is_dead():
		return false
	return target.get_team_id() != unit.get_team_id()


## unit 与 target 中心距离（像素）；target 不存在返回 INF。
static func distance_to(world: Dota2WorldGameplayInstance, unit: Dota2UnitActor, target_id: String) -> float:
	var target: Dota2BattleActor = world.get_actor(target_id)
	if target == null:
		return INF
	return unit.position_2d.distance_to(target.position_2d)


## target 是否进入 unit 的基础攻击距离内（含一点容差，避免边界抖）。
const ATTACK_RANGE_TOLERANCE := 1.05

static func is_in_attack_range(world: Dota2WorldGameplayInstance, unit: Dota2UnitActor, target_id: String) -> bool:
	var dist := distance_to(world, unit, target_id)
	if dist == INF:
		return false
	var reach: float = unit.attribute_set.attack_range * ATTACK_RANGE_TOLERANCE
	return dist <= reach
