## RtsBuildingActor - RTS 建筑 Actor (P2.5 落地工厂 + production)
##
## RtsBattleActor 的子类: 表示城堡战争里的"会写 pathing map 的硬阻挡实体"
## (水晶塔 / 兵营 / 防御塔 / 资源建筑等)。决策 E 锁定走 building_kind: String 工厂模式
## (照抄 hex EnvironmentActor + StoneWall 的同构), 不为 CrystalTower 单独建子类。
##
## P2.5 落地: 持 RtsBuildingAttributeSet + AbilitySet + footprint_size + production 字段。
## 工厂方法在 logic/buildings/rts_buildings.gd, 产出已配好 attribute_set / ability_set /
## footprint_size / production_period_ms 的实例 (调方再 set position_2d / team_id / add_actor)。
##
## 决策来源: architecture-baseline.md §4 (子类家族) + 决策 E
class_name RtsBuildingActor
extends RtsBattleActor


# ========== 字段 ==========

## 建筑种类标识符 (供 replay / frontend 区分视觉; "crystal_tower" / "barracks" / "archer_tower")。
## 由工厂方法在 _init 时赋值, 不在 RtsBuildings 之外修改。
var building_kind: String = ""

## 强类型 attribute_set: hp / max_hp / production_speed_multiplier。
## 调方读 hp 走 get_attribute_set() 接口; 调方读 production 走专属字段直接访问。
var attribute_set: RtsBuildingAttributeSet = null

## footprint cell 尺寸 (cells × cells, AABB)。Phase 2 P2.5: 兵营 (2,2), 水晶塔 (2,2),
## 防御塔 (1,1)。get_footprint_cells(grid) 按此尺寸算 AABB cells, 中心对齐 position_2d。
var footprint_size: Vector2i = Vector2i(1, 1)

## 是否水晶塔 (供 P2.6 胜负判定快速过滤; P2.5 仅记录, 不参与判定)。
var is_crystal_tower: bool = false

## 生产周期 (ms); <= 0 表示不生产。production_system tick 累积 _production_progress_ms,
## 达到此周期 → 触发 spawn + 减一周期 (溢出量保留, 让 spawn 节奏稳定)。
var production_period_ms: float = 0.0

## 生产的单位兵种 (RtsUnitClassConfig.UnitClass; production_period_ms <= 0 时未使用)。
var spawn_unit_kind: int = -1

## 生产单位的初始 stance (RtsUnitActor.Stance; 默认 AGGRESSIVE)。
var spawn_unit_stance: int = 2

## P2.5 production_system 内部状态: 累积时间 (ms)。
## 每次 production_system.tick(dt_ms) 累加 dt_ms × production_speed_multiplier;
## 达到 production_period_ms → 触发 spawn callback + 减一周期。
var _production_progress_ms: float = 0.0


# ========== 初始化 ==========

## P2.5: 调方应通过 RtsBuildings.create_*() 工厂方法创建实例 — 工厂会:
##   1. 用此构造器传 building_kind
##   2. set footprint_size / is_crystal_tower / production_period_ms / spawn_unit_kind
##   3. 实例化 attribute_set + ability_set
##   4. set max_hp / hp
##
## 直接 RtsBuildingActor.new("foo") 调用是合法的 (单元测试 / 占位 stub), 但 attribute_set
## 仍为 null — check_death 此时返回 false, 调方需要血量需自行 wire。
func _init(p_building_kind: String = "") -> void:
	building_kind = p_building_kind
	type = "Building"
	_display_name = p_building_kind


# ========== RtsBattleActor 合同实现 ==========

## Building 写 pathing map (WC3 风: 单位不写, 建筑写)。
## A* 永远绕开建筑 footprint cells; 单位通过自身 collision_radius + push-out 互避。
func writes_to_pathing_map() -> bool:
	return true


## 强类型 attribute_set 暴露给基类视图 (check_death / 公共 hp 查询)。
func get_attribute_set() -> BaseGeneratedAttributeSet:
	return attribute_set


## 按 footprint_size 计算覆盖的 AABB cells, 中心对齐 position_2d。
##
## 例: footprint_size=(2,2), position_2d=(160,160), cell_size=32:
##     center_cell = (5, 5); 2×2 AABB → cells [(4,4),(5,4),(4,5),(5,5)] (左上偏置)
##
## footprint_size=(1,1) 退化为基类默认 (单 cell)。footprint_size=(2,2) AABB 取
## center_cell - (1, 1) 到 center_cell - (0, 0) (左上 inclusive 偏置, 与 cell_size=32
## RtsBattleMap 标 obstacle cells 一致).
func get_footprint_cells(grid) -> Array:
	if grid == null:
		return []
	# 基类用 untyped `grid` 参数 (向后兼容); 这里取出 HexCoord 时显式标 type 让推导通过。
	var center: HexCoord = grid.world_to_coord(position_2d)
	# 1×1 退化
	if footprint_size.x <= 1 and footprint_size.y <= 1:
		return [center]
	# AABB: 偶数尺寸时左上偏置 (footprint = [center-1, center])
	# 奇数尺寸时居中 (footprint = [center - half, center + half])
	var half_x_lo: int = footprint_size.x / 2
	var half_x_hi: int = footprint_size.x - 1 - half_x_lo
	var half_y_lo: int = footprint_size.y / 2
	var half_y_hi: int = footprint_size.y - 1 - half_y_lo
	var result: Array = []
	# HexCoord 在 SQUARE grid 里 q=col, r=row (plugin 约定 cell 坐标始终用 HexCoord 类即使非 hex)。
	for dy in range(-half_y_lo, half_y_hi + 1):
		for dx in range(-half_x_lo, half_x_hi + 1):
			var coord: HexCoord = HexCoord.new(center.q + dx, center.r + dy)
			result.append(coord)
	return result


# ========== 录像支持 ==========

func _get_config_id() -> String:
	return building_kind


func get_attribute_snapshot() -> Dictionary:
	if attribute_set == null:
		return {}
	return attribute_set.snapshot()
