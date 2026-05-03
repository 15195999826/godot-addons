## RtsObstructionShape - Obstruction shape 基类 (M0 引入,M2 ObstructionManager 时挂上去)
##
## 0 A.D. ObstructionManager 内部 Shape 概念的 GDScript 复刻。表示一个"占地"实体在寻路系统
## 中的几何 + 属性元数据 (位置 / flags / control group / tag)。
##
## **M0 范围**: 只引入 data 字段,不挂任何算法逻辑。M2 RtsObstructionManager 落地时:
##   - 把 instance 注册进 manager (分配 tag)
##   - rasterize 进 RtsNavcellGrid
##   - 提供 spatial query (test_*_shape / get_obstructions_in_range / distance_to_*)
##
## **子类**:
##   - RtsObstructionShapeStatic - OBB 矩形 (建筑 / 资源点; M0 引入)
##   - RtsObstructionShapeUnit   - 圆 (单位; M2 引入)
##
## **0 A.D. 对照**: `simulation2/components/CCmpObstructionManager.cpp` Shape 基类
##
## **决策来源**:
##   - data-structures.md §2.1
##   - milestones/M0-footprint-split.md §M0.2 步骤 1
class_name RtsObstructionShape
extends RefCounted


## Shape 类型枚举。
enum Type {
	UNIT,    # 圆 (单位); M2 引入 RtsObstructionShapeUnit
	STATIC,  # OBB 矩形 (建筑 / 静态障碍物); M0 引入 RtsObstructionShapeStatic
}


# ========== 字段 ==========

## Shape 类型 (Type.UNIT / Type.STATIC), 由子类 _init 显式设置。
var type: int = Type.UNIT

## Owner entity 的 actor_id (RtsActor.get_id())。
## M0 工厂构造时为空; sync_obstruction_shape() (M0.5) 或注册到 ObstructionManager 时 (M2) 由调方填。
var entity_id: String = ""

## 世界坐标 (px) 中心点。M0 工厂构造时为 ZERO; 在 sync_obstruction_shape() 中由调方填
## (= position_2d + obstruction_offset)。
var center: Vector2 = Vector2.ZERO

## EFlags 位掩码 — 取值见 [RtsObstructionFlags] (M2 引入完整 6 个 flag 常量)。
##
## **典型组合**:
##   - 单位 (RtsObstructionShapeUnit): `BLOCK_MOVEMENT`
##   - 建筑 (RtsObstructionShapeStatic): `BLOCK_PATHFINDING | BLOCK_FOUNDATION`
##   - 树 / 资源点: `BLOCK_PATHFINDING | DELETE_UPON_CONSTRUCTION`
var flags: int = 0

## 控制组 (= formation_id 或 owner_id, "" = 无 group)。
##
## M6 VertexPathfinder group filter (同 group 不互相算障碍) 与 M7 Motion obstruction filter 用。
## **注意**: 此字段在 M6/M7 已是 API 输入,不是 M8 才用 (D9 / codex 反馈)。
## M2 写入,M6/M7 读取,M8 仅打开 push pass 开关。
var control_group: String = ""

## 次组 (建筑可能跟两个 group, 例如领土 + owner)。"" = 无第二 group。
var control_group_2: String = ""

## ObstructionManager 分配的 tag (M2 引入), 用于 O(1) 反查 / determinism sort key。
##
## 0 = invalid / 未注册; 1+ 单调递增。
## (data-structures.md §12.4 — get_obstructions_in_range 必须按 tag 升序返回)
var tag: int = 0
