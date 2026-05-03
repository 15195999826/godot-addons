## RtsFootprintShape - UI 选择形状 (M0 引入,跟 obstruction 解耦)
##
## 0 A.D. ICmpFootprint 的 GDScript 复刻 — 表示玩家鼠标点击建筑时"哪些坐标算选中"的形状。
## **跟 obstruction shape 独立**: footprint 是 UI 维度,obstruction 是寻路维度,两者中心可错位。
##
## **典型 case**:
##   - 兵营 sprite 锚点在中心 → footprint 跟 sprite 锚点 (center_offset = ZERO),
##     寻路 obstruction 几何中心也跟 sprite (obstruction_offset = ZERO);
##   - 异形建筑 (sprite 几何中心跟 collider 错位) → footprint center_offset 调整,
##     让玩家点 sprite 视觉中心能选中。
##
## **M0 范围**: data 字段 + contains / get_world_aabb helper。frontend visualizer 选择圈
##              渲染调用此类的 get_world_aabb (M0.6)。
##
## **0 A.D. 对照**: `simulation2/components/ICmpFootprint.h`
##
## **决策来源**:
##   - data-structures.md §3.1 (RtsFootprintShape data class)
##   - milestones/M0-footprint-split.md §M0.2 步骤 3
##   - F5 决策 A: center_offset 相对 owner.position (UI 跟 sprite 走), 不是相对 obstruction.center
class_name RtsFootprintShape
extends RefCounted


## Footprint 形状类型枚举。
enum Type {
	CIRCLE,   # 圆: size.x = 半径; size.y 不用
	SQUARE,   # 矩形: size.x = 半宽 (沿 +x), size.y = 半高 (沿 +y)
}


# ========== 字段 ==========

## Footprint 类型 (Type.CIRCLE / Type.SQUARE)。
var type: int = Type.CIRCLE

## 相对 owner.position (= sprite 渲染锚点) 的偏移 (px)。
##
## ZERO = footprint 中心跟 sprite 锚点重合 (M0 默认; F5 决策 A); 需让 UI 选择圈跟 obstruction
## 错位时 (例如 sprite 中心跟 collider 错位且玩家想跟着 sprite 选) 才需调整。
var center_offset: Vector2 = Vector2.ZERO

## 形状尺寸:
##   - Type.CIRCLE: x = 半径 (px); y 不用
##   - Type.SQUARE: x = 半宽 (沿 +x); y = 半高 (沿 +y)
var size: Vector2 = Vector2(16.0, 16.0)


# ========== 查询 ==========

## 检查 world_pos 是否落在以 owner_pos + center_offset 为中心的 footprint 内。
##
## 用于:
##   - 玩家鼠标点击命中检测 (frontend selection)
##   - placement / cancel 选择圈交互
func contains(world_pos: Vector2, owner_pos: Vector2) -> bool:
	var local: Vector2 = world_pos - (owner_pos + center_offset)
	match type:
		Type.CIRCLE:
			return local.length_squared() <= size.x * size.x
		Type.SQUARE:
			return absf(local.x) <= size.x and absf(local.y) <= size.y
	return false


## 返回包围 footprint 的世界坐标 AABB (Rect2)。
##
## 用于 frontend visualizer 选择圈渲染 (画 highlight box) — M0.6 落地链路。
##
## **注意**: SQUARE 直接返回精确 AABB; CIRCLE 返回外接 AABB (size = 2 × radius)。
##           CIRCLE 视觉上玩家看到的是矩形高亮 (跟现有 RTS 选择圈风格一致); 若需画圆形 outline
##           由 visualizer 自行根据 size.x 半径单独画。
func get_world_aabb(owner_pos: Vector2) -> Rect2:
	var c: Vector2 = owner_pos + center_offset
	match type:
		Type.CIRCLE:
			var r: float = size.x
			return Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0)
		Type.SQUARE:
			return Rect2(c.x - size.x, c.y - size.y, size.x * 2.0, size.y * 2.0)
	return Rect2()
