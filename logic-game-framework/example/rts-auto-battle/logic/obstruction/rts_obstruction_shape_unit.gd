## RtsObstructionShapeUnit - 圆形 obstruction (单位; M2 引入)
##
## 表示一个单位 (RtsActor.kind == "unit") 在寻路系统中的占地 — 圆形,半径 = clearance。
## 0 A.D. 的 `UnitShape` (`CCmpObstructionManager.cpp`) 复刻。
##
## **几何**:
##   - center (基类): Vector2 (世界坐标; 通常 = actor.position_2d)
##   - clearance: float (半径 px; M2 阶段取自 RtsUnitClassConfig.collision_radius;
##                       M3 引入 per-class buffer 后从 RtsMotionComponent.clearance 取)
##   - moving: bool (单位是否在移动; 跟 base.flags 的 MOVING bit 双写, 留作 unit motion 状态机便利字段)
##
## **典型 flags**: `RtsObstructionFlags.BLOCK_MOVEMENT` (单位间互避; 不进 NavcellGrid pathfinding bit)。
##
## **M2 范围**: data 字段 + _init 设 type。注册 / 移动 / rasterize 由 M2.3 RtsObstructionManager 接管。
##
## **0 A.D. 对照**:
##   - `CCmpObstructionManager.cpp` `UnitShape` (`m_X / m_Z / m_R` → 我们 center.x / center.y / clearance)
##   - `m_Moving` flag → 我们 moving + base.flags (MOVING bit) 双写
##
## **决策来源**:
##   - data-structures.md §2.1 (RtsObstructionShapeUnit)
##   - milestones/M2-obstruction-manager.md §0 + §1.1
class_name RtsObstructionShapeUnit
extends RtsObstructionShape


# ========== 几何字段 ==========

## 圆半径 (px)。M2 阶段取自 RtsUnitClassConfig.collision_radius; M3 引入 clearance buffer 后切到
## RtsMotionComponent.clearance。
var clearance: float = 0.0

## 单位是否在移动 (跟 base.flags 的 MOVING bit 双写)。
##
## **双写约定**: 由 RtsObstructionManager.set_unit_moving_flag 同步两边; 外部读取以 base.flags 为准
## (寻路 / filter 看的是 flags 位掩码), 此字段是状态机便利标记。
var moving: bool = false


# ========== 初始化 ==========

func _init() -> void:
	type = Type.UNIT
