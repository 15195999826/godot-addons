## Dota2LaneConfig - ARAM 单中路 + 队伍常量 + 波次定义
##
## m1-contract.md Scene Goal：一条水平中路，左右两队从两端刷 lane creep 对进。
## 这是静态布局数据；WaveSpawner 读它定位出生点 / 波次组成，controller 读它拿
## march 目标航点。坐标连续 Vector2（像素），无 hex grid、无 ATB。
class_name Dota2LaneConfig
extends RefCounted


# ========== 队伍常量 ==========

const TEAM_LEFT := 0
const TEAM_RIGHT := 1


# ========== 地图 / 中路几何 ==========

## sim-nav 适配器用此尺寸建 nav_map；中路沿 y = LANE_Y 水平铺开。
const MAP_SIZE := Vector2(1320.0, 520.0)
const LANE_Y := 260.0

## 出生点（队伍基地端）。左队从左端往右推，右队从右端往左推。
const LEFT_SPAWN := Vector2(150.0, LANE_Y)
const RIGHT_SPAWN := Vector2(1170.0, LANE_Y)

## march 终点航点（敌方基地端）。M1 单航点：一路推到对面出生点。
const LEFT_GOAL := RIGHT_SPAWN
const RIGHT_GOAL := LEFT_SPAWN


# ========== 波次 ==========

## M1：每队 1 波（共两波）。波内单位沿 lane 纵向小幅错开避免出生即互相硬阻挡。
const MAX_WAVES := 1
const SPAWN_SPACING_X := 34.0
const SPAWN_SPACING_Y := 26.0


## 每波兵种组成（出场顺序 = 数组序）。M1：3 近战 + 1 远程。
## 用 static func 而非 const —— const 数组引用别类 enum 不是常量表达式。
static func get_wave_composition() -> Array[Dota2UnitTypeConfig.UnitType]:
	return [
		Dota2UnitTypeConfig.UnitType.LANE_MELEE,
		Dota2UnitTypeConfig.UnitType.LANE_MELEE,
		Dota2UnitTypeConfig.UnitType.LANE_MELEE,
		Dota2UnitTypeConfig.UnitType.LANE_RANGED,
	]


## 取某队出生点。
static func get_spawn_point(team_id: int) -> Vector2:
	if team_id == TEAM_LEFT:
		return LEFT_SPAWN
	return RIGHT_SPAWN


## 取某队 march 终点航点（敌方基地端）。
static func get_lane_goal(team_id: int) -> Vector2:
	if team_id == TEAM_LEFT:
		return LEFT_GOAL
	return RIGHT_GOAL


## 行进方向单位向量（左队朝 +x，右队朝 -x）。
static func get_march_dir(team_id: int) -> Vector2:
	return Vector2(1.0, 0.0) if team_id == TEAM_LEFT else Vector2(-1.0, 0.0)


## 波内第 slot_index 个单位的出生坐标：从基地端沿反 march 方向退一点 + 纵向错开，
## 让一波兵不在同一点叠出生（sim-nav 硬阻挡会卡死同点单位）。
static func get_unit_spawn_pos(team_id: int, slot_index: int) -> Vector2:
	var base := get_spawn_point(team_id)
	var back := -get_march_dir(team_id) * (SPAWN_SPACING_X * float(slot_index))
	var lane_offset := SPAWN_SPACING_Y * (float(slot_index) - 1.5)
	return base + back + Vector2(0.0, lane_offset)
