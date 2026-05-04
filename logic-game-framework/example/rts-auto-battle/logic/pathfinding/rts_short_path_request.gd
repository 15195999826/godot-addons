## RtsShortPathRequest - 短路径(VertexPathfinder)寻路请求 (M6 引入)
##
## 0 A.D. `ShortPathRequest` (helpers/Pathfinding.h:243) 的 GDScript 复刻。封装 short
## pathfinder 的入参:start / clearance / range / goal / pass_mask / avoid_moving_units /
## control_group。
##
## **跟 LongPathRequest 区别**:
##   - `range` (搜索框尺寸) — 默认 1792 px = 56 navcells × 32 px;限制 vertex pathfinder
##     仅在该框内搜索,避免 search box 退化成全图
##   - `clearance` (单位避让半径) — `RtsLineOfSight.segment_clear` 的 buffer 入参
##   - `avoid_moving_units` (M6c 启用) — false 时 MOVING flag 单位不算障碍(让"挤过"队伍)
##   - `control_group` (M6c 启用) — 同 group obstruction 跳过(队伍内不互相挡)
##
## **M6a 阶段**:`avoid_moving_units` / `control_group` 字段填好但 vertex pathfinder 暂不消费
## (M6c 加 dynamic units / group filter 时启用)。
##
## **决策来源**:
##   - data-structures.md §7.1 (字段表)
##   - interfaces.md §5.2 (调用约定)
##   - milestones/M6-vertex-pathfinder.md §M6a.2
class_name RtsShortPathRequest
extends RefCounted


# ========== 常量 ==========

## 默认搜索范围 (px) = 56 navcells × 32 px。
const DEFAULT_RANGE_PX: float = 1792.0


# ========== 字段 ==========

## Caller 跟踪用的递增 id;M6 同步阶段保留字段不消费。
var ticket: int = 0

## 起点世界坐标 (px)。
var start: Vector2 = Vector2.ZERO

## 单位避让半径 (px) — segment_clear / OBB corner buffer 都用此值。
var clearance: float = 0.0

## 搜索框尺寸 (px);默认 1792 = 56 navcells × 32 px。
var range_px: float = DEFAULT_RANGE_PX

## 目标 PathGoal (POINT/CIRCLE/SQUARE/INVERTED_*)。
##
## **M6a 阶段**:仅 POINT 实现(virtual goal 简化为 goal.center);M6b 加 CIRCLE/SQUARE 几何。
var goal: RtsPathGoal = null

## 单 passability class mask (`default` 或 `air`)。
var pass_mask: int = 0

## MOVING flag 单位是否算障碍 (M6c 启用;M6a 不消费此字段)。
var avoid_moving_units: bool = true

## 同 control_group obstruction 跳过 (M6c 启用;M6a 不消费此字段)。
var control_group: String = ""

## Notify entity actor id;M6 同步阶段不用。
var notify_entity: String = ""


# ========== 初始化 ==========

func _init(
	p_start: Vector2 = Vector2.ZERO,
	p_goal: RtsPathGoal = null,
	p_clearance: float = 0.0,
	p_range_px: float = DEFAULT_RANGE_PX,
	p_pass_mask: int = 0,
	p_avoid_moving_units: bool = true,
	p_control_group: String = "",
	p_notify_entity: String = "",
	p_ticket: int = 0,
) -> void:
	start = p_start
	goal = p_goal
	clearance = p_clearance
	range_px = p_range_px
	pass_mask = p_pass_mask
	avoid_moving_units = p_avoid_moving_units
	control_group = p_control_group
	notify_entity = p_notify_entity
	ticket = p_ticket
