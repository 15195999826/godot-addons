## RtsPathGoal - 寻路目标抽象 (M5 引入)
##
## 0 A.D. `helpers/PathGoal.h:30-90` 的 GDScript 复刻。把 LongPath / VertexPath / Hierarchical
## 的目标统一成 5 种几何形状,用 enum + 字段组合表达,facade.compute_path_immediate 接受统一抽象。
##
## **M5 阶段只用 POINT** — VertexPath / attack-range 圆 / building 矩形是 M6/M7 才需要,
## CIRCLE / SQUARE / INVERTED_* 占位 enum + 字段保留,helper 留 minimal POINT 实现。
##
## **navcell_contains_goal(i, j)**: navcell 是否包含 goal — POINT 时检查 (i, j) 是否就是
## goal.center 所在的 navcell;M6+ 扩展到 CIRCLE/SQUARE 几何相交。
##
## **决策来源**:
##   - data-structures.md §5 (5 种 type + 字段表 + helper 列表)
##   - 0 A.D. helpers/PathGoal.h:30-90 一一对应
class_name RtsPathGoal
extends RefCounted


# ========== 类型 ==========

enum Type {
	POINT,            ## 单点 (M5 唯一实现)
	CIRCLE,           ## 圆内任意一点 (M6/M7)
	INVERTED_CIRCLE,  ## 圆外任意一点 (M7 attack-range minimum)
	SQUARE,           ## 矩形内任意一点 (M6/M7 building)
	INVERTED_SQUARE,  ## 矩形外任意一点 (M7)
}


# ========== 字段 ==========

var type: int = Type.POINT

## 几何中心 (POINT 即坐标 / CIRCLE 圆心 / SQUARE 矩形中心)。
var center: Vector2 = Vector2.ZERO

## SQUARE: 半宽 / CIRCLE: 半径 / POINT: 不用 (默认 0)。
var hw: float = 0.0

## SQUARE: 半高 / CIRCLE 不用。
var hh: float = 0.0

## SQUARE 的 u 轴 (单位向量,本地坐标系 X)。
var u: Vector2 = Vector2(1, 0)

## SQUARE 的 v 轴 (单位向量,本地坐标系 Y)。
var v: Vector2 = Vector2(0, 1)

## 两 waypoint 间最大距离 (0 = 不限);M5 阶段不用,留字段。
var maxdist: float = 0.0


# ========== 初始化 ==========

func _init(p_type: int = Type.POINT, p_center: Vector2 = Vector2.ZERO) -> void:
	type = p_type
	center = p_center


# ========== Helpers ==========

## 给定 navcell (i, j),其是否包含 goal(POINT 时:其中心 = goal.center 所在 navcell)。
##
## **M5 阶段仅 POINT 实现**;CIRCLE/SQUARE 留 false 占位,M6 VertexPath 启用时再补。
##
## 调方需要传入 grid 来从 (i, j) 转 world (因 RtsPathGoal 不持 grid 引用);M5 单 caller
## 是 LongPathfinder._astar 终止判定,可以直接 == 比较 navcell index 而非走 world,所以这个
## helper 实际只在 M6 才被调用 — 留接口给 hierarchical 暴力扫 goal bounding box 用。
func navcell_contains_point(navcell_world_center: Vector2, navcell_half_size: float) -> bool:
	match type:
		Type.POINT:
			# POINT goal: navcell 包含 goal ⇔ goal.center 在 navcell 边界内
			return absf(center.x - navcell_world_center.x) <= navcell_half_size and absf(center.y - navcell_world_center.y) <= navcell_half_size
		_:
			# M5 阶段 CIRCLE/SQUARE/INVERTED_* 不用,M6 补
			return false


## goal 距离给定点 p 的距离(POINT = 直线距离;其他形状 M6 才用)。
func distance_to_point(p: Vector2) -> float:
	match type:
		Type.POINT:
			return p.distance_to(center)
		_:
			return p.distance_to(center)   # M5 fallback;M6 按形状重写


## 给定 p,goal 上离 p 最近的点(POINT 永远是 center;其他形状 M6 才用)。
func nearest_point_on_goal(p: Vector2) -> Vector2:
	match type:
		Type.POINT:
			return center
		_:
			return center   # M5 fallback;M6 按形状重写
