## RtsPassabilityClassConfig - Passability class 配置
##
## 对应 0 A.D. simulation/data/pathfinder.xml 的一个 <PassabilityClass> 段。
## 每个 class 占 NavcellGrid bit 中的 1 bit, 用于多 class passability 查询
## (e.g. ground 单位 vs air 单位 vs ship 单位 各看不同的 mask)。
##
## 决策来源:
##   - data-structures §1.1 (字段定义对齐 0 A.D. pathfinder.xml schema)
##   - 本 Epic 实际只用 default + air 两 class, 留 14 bit 给将来 (mod / 扩展)
class_name RtsPassabilityClassConfig
extends Resource


## 唯一 ID, e.g. "default" / "ground" / "air" / "ship"
@export var class_name_id: String = ""

## 0..15, 自动分配 (RtsPassabilityClassRegistry.register 时填; -1 表示未注册)
@export var bit_index: int = -1

## 单位 px (cell_size = 32, 默认 14 贴近现有 RtsUnitClassConfig.collision_radius)
@export var clearance: float = 14.0

## 0 = 不能下水; > 0 = 必须有深度上限 (我们当前没水机制, 留接口)
@export var max_water_depth: float = 0.0

## > 0 = 必须在水里 (船类用)
@export var min_water_depth: float = 0.0

## 离岸最小距离 (留接口)
@export var min_shore_distance: float = 0.0
