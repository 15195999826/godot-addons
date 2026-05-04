## RtsPathGoal - 寻路目标抽象 (M5 引入,M6b 扩 CIRCLE/SQUARE/INVERTED 几何)
##
## 0 A.D. `helpers/PathGoal.h:30-90` 的 GDScript 复刻。把 LongPath / VertexPath / Hierarchical
## 的目标统一成 5 种几何形状,用 enum + 字段组合表达,facade.compute_path_immediate 接受统一抽象。
##
## **M5 阶段只用 POINT**;**M6b** 扩 CIRCLE / SQUARE / INVERTED_CIRCLE / INVERTED_SQUARE 的
## `nearest_point_on_goal` / `distance_to_point` 几何 — VertexPathfinder._compute_virtual_goal
## 用 nearest_point_on_goal(req.start) 算"goal 边界离 start 最近"的 vertex。
##
## **navcell_contains_point(navcell_world_center, navcell_half_size)**: navcell 是否包含 goal —
## POINT 检查 navcell 边界内;M6+ 扩 CIRCLE/SQUARE 几何相交(暂未启用)。
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


## goal 距离给定点 p 的距离。
##
## - POINT: 直线距离 (p → center)
## - CIRCLE: max(0, |p - center| - radius) — p 在圆内距离=0,p 在圆外距离=圆边到 p
## - INVERTED_CIRCLE: max(0, radius - |p - center|) — p 在圆内距离=圆边到 p,p 在圆外距离=0
## - SQUARE: p 投影到 OBB local 坐标 clamp 到 [-hw,hw]×[-hh,hh] 后转 world → 距离
## - INVERTED_SQUARE: p 在 OBB 内 → OBB 边到 p 最近距离;p 在 OBB 外 → 0
func distance_to_point(p: Vector2) -> float:
	match type:
		Type.POINT:
			return p.distance_to(center)
		Type.CIRCLE:
			return maxf(0.0, p.distance_to(center) - hw)
		Type.INVERTED_CIRCLE:
			return maxf(0.0, hw - p.distance_to(center))
		Type.SQUARE:
			return p.distance_to(_clamp_to_square(p))
		Type.INVERTED_SQUARE:
			# p 在 OBB 内时距离 = OBB 边到 p 的最近距离;p 在 OBB 外时距离 = 0
			var local: Vector2 = _to_local(p)
			if absf(local.x) <= hw and absf(local.y) <= hh:
				return minf(minf(hw - absf(local.x), hh - absf(local.y)), 0.0) * -1.0
			return 0.0
		_:
			return p.distance_to(center)


## 给定 p,goal 上离 p 最近的点(M6b VertexPathfinder._compute_virtual_goal 调用)。
##
## - POINT: 永远 center
## - CIRCLE: 圆周上离 p 最近点 = center + (p-center).normalized() * radius
##   - p == center 时方向不定,fallback 用 (radius, 0) 避免 NaN(deterministic)
## - INVERTED_CIRCLE: 同 CIRCLE(圆周上离 p 最近点;p 在圆内 = 离 p 最近的圆周点 = center + dir * radius)
## - SQUARE: p 投到 OBB local clamp 到 [-hw,hw]×[-hh,hh] 后转 world(p 在 OBB 内 = p 自身)
## - INVERTED_SQUARE: 同 SQUARE 几何 nearest;p 在 OBB 内 → OBB 边上离 p 最近的点
func nearest_point_on_goal(p: Vector2) -> Vector2:
	match type:
		Type.POINT:
			return center
		Type.CIRCLE, Type.INVERTED_CIRCLE:
			var diff: Vector2 = p - center
			var dist: float = diff.length()
			# WHY: dist=0 时方向不定,固定 (1,0) 让结果 deterministic 不依赖浮点 0/0 → NaN
			var dir: Vector2 = Vector2(1.0, 0.0) if dist <= 0.00001 else diff / dist
			return center + dir * hw
		Type.SQUARE:
			return _clamp_to_square(p)
		Type.INVERTED_SQUARE:
			var local: Vector2 = _to_local(p)
			# p 在 OBB 外 → clamp 后即 nearest;p 在 OBB 内 → push 到最近边
			if absf(local.x) > hw or absf(local.y) > hh:
				return _clamp_to_square(p)
			# p 在 OBB 内,推到最近边(选 |local.x|/hw 跟 |local.y|/hh 哪个比例大)
			var rx: float = absf(local.x) / hw if hw > 0.0 else 0.0
			var ry: float = absf(local.y) / hh if hh > 0.0 else 0.0
			if rx >= ry:
				local.x = signf(local.x) * hw if local.x != 0.0 else hw
			else:
				local.y = signf(local.y) * hh if local.y != 0.0 else hh
			return center + u * local.x + v * local.y
		_:
			return center


# ========== 内部 helper ==========

## p 投影到 OBB local 坐标系。
func _to_local(p: Vector2) -> Vector2:
	var diff: Vector2 = p - center
	return Vector2(diff.dot(u), diff.dot(v))


## p 投影到 OBB local clamp 到 [-hw,hw]×[-hh,hh] 后转回 world。SQUARE nearest-point 公式。
func _clamp_to_square(p: Vector2) -> Vector2:
	var local: Vector2 = _to_local(p)
	local.x = clampf(local.x, -hw, hw)
	local.y = clampf(local.y, -hh, hh)
	return center + u * local.x + v * local.y
