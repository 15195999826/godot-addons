## RtsMoveRequest - 单位移动请求抽象 (M7 引入)
##
## 0 A.D. `CCmpUnitMotion::MoveRequest` (`CCmpUnitMotion.h:200-220`) 的 GDScript 复刻。
## 把 4 种 motion 触发方式(无 / 走到点 / 接近 entity / 跟随 entity 带 offset)统一成一个
## RefCounted data class,RtsUnitMotion 持一个 `_move_request` 字段记录"现在要去哪"。
##
## **4 种 type**:
##   - `NONE` — 没有目标(idle / stop 后);has_target() == false
##   - `POINT` — 走到点附近,距离 ∈ `[min_range, max_range]`;玩家右键 / 巡逻 / move_units_command
##   - `ENTITY` — 接近某 entity 到指定距离;attack target / gather resource / build foundation
##   - `OFFSET` — 跟随某 entity 保持 offset(M9 编队 slot 用,M7 阶段留接口)
##
## **range 语义**(0 A.D. 复刻):
##   - `min_range`:目标距离下限(0 = 可贴上;远程兵 attack 时 min_range = 0,近战 min_range = 0)
##   - `max_range`:目标距离上限(到达条件:`distance ≤ max_range`)
##   - `min_range > 0` 用于 INVERTED_CIRCLE goal(远程兵 retreat 时保持距离 ≥ min_range)
##
## **不变量**:
##   - type == NONE 时 entity_id / position / min_range / max_range 全为默认值(语义上不应被读)
##   - type == POINT 时 entity_id 应 == ""
##   - type == ENTITY / OFFSET 时 entity_id 非空
##
## **决策来源**:
##   - data-structures.md §8.1 (RtsMoveRequest 字段表 + 4 种 type)
##   - milestones/M7-unit-motion.md §M7a.1
class_name RtsMoveRequest
extends RefCounted


# ========== 类型 ==========

enum Type {
	NONE,    ## 没有目标(idle / stop)
	POINT,   ## 走到点附近,距离 ∈ [min_range, max_range]
	ENTITY,  ## 接近某 entity 到指定距离
	OFFSET,  ## 跟随某 entity 保持 offset(M9 编队 slot 用)
}


# ========== 字段 ==========

## 请求类型;NONE = 无目标。
var type: int = Type.NONE

## ENTITY / OFFSET 用 — 目标 actor id;POINT / NONE 时为 ""。
var entity_id: String = ""

## POINT 用 — 目标坐标;OFFSET 用 — 相对 entity 的 offset(本地坐标)。
var position: Vector2 = Vector2.ZERO

## 距离下限(0 = 可贴上);INVERTED_CIRCLE goal 用 min_range > 0 让远程兵保持距离。
var min_range: float = 0.0

## 距离上限;到达条件 `distance ≤ max_range`。
var max_range: float = 0.0


# ========== 工厂 ==========

## 走到点附近;距离落入 [min_r, max_r]。
static func to_point(pos: Vector2, min_r: float, max_r: float) -> RtsMoveRequest:
	var req := RtsMoveRequest.new()
	req.type = Type.POINT
	req.position = pos
	req.min_range = min_r
	req.max_range = max_r
	return req


## 接近 entity 到指定距离;eid 必须非空。
static func to_entity(eid: String, min_r: float, max_r: float) -> RtsMoveRequest:
	Log.assert_crash(eid != "", "RtsMoveRequest", "to_entity: eid must be non-empty")
	var req := RtsMoveRequest.new()
	req.type = Type.ENTITY
	req.entity_id = eid
	req.min_range = min_r
	req.max_range = max_r
	return req


## 跟随 entity 保持 offset(本地坐标);M9 编队用,M7 阶段留接口。
static func with_offset(eid: String, off: Vector2) -> RtsMoveRequest:
	Log.assert_crash(eid != "", "RtsMoveRequest", "with_offset: eid must be non-empty")
	var req := RtsMoveRequest.new()
	req.type = Type.OFFSET
	req.entity_id = eid
	req.position = off
	return req
