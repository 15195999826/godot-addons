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
## 防御塔 (1,1)。
##
## **M0.4 注**: 仍保留作 frontend 视觉与 M0 fallback (obstruction_shape == null 时
## get_footprint_cells 用此字段); M2 引入 ObstructionManager 后由 obstruction_shape 完全替代,
## 此字段才删除。
var footprint_size: Vector2i = Vector2i(1, 1)

## M0.4 — Obstruction shape (寻路占地, OBB). 工厂 RtsBuildings 在 _create_from_kind 时填,
## 调方在 set position_2d 之后调 sync_obstruction_shape() 把 center 设到
## position_2d + stats.obstruction_offset (M0.5 落地 6 个 call sites).
##
## **M0.4 阶段**: 此字段仍可能为 null (M0.5 工厂注入前所有路径都走旧 fallback);
## get_footprint_cells 会在 null 时回退到 footprint_size 旧路径,保 smoke 0 漂移.
var obstruction_shape: RtsObstructionShapeStatic = null

## M0.4 — Footprint shape (UI 选择). 工厂在 _create_from_kind 时填. M0.6 frontend
## visualizer 选择圈渲染调 footprint_shape.get_world_aabb(actor.position_2d).
##
## **M0.4 阶段**: 此字段仍可能为 null (M0.5 工厂注入前); frontend 现有选择圈逻辑不动,
## M0.6 切到 footprint_shape 时再处理 null 兜底.
var footprint_shape: RtsFootprintShape = null

## 是否水晶塔 (供 P2.6 胜负判定快速过滤; P2.5 仅记录, 不参与判定)。
var is_crystal_tower: bool = false

## M2.1 Phase C — 是否 worker drop-off 点 (RtsReturnAndDropActivity 找己方最近 is_drop_off 建筑)。
##
## 由 RtsBuildings._create_from_kind 从 RtsBuildingConfig.StatBlock.is_drop_off 写入
## (crystal_tower stats 设 true; barracks / archer_tower 默认 false)。
var is_drop_off: bool = false

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


# ========== P2.8: 建筑武器字段 (供能攻击的塔) ==========

## 攻击力 (建筑没 attribute_set 的 atk 字段, 直接挂 plain float; 由工厂从 BuildingConfig 注入)。
##
## 默认 0 = 不攻击 (兵营 / 水晶塔); archer_tower 在 P2.8 落地为 anti-air, atk > 0。
var atk_value: float = 0.0

## 防御力 (M1 范围内建筑不被实际计算 def 减伤, 但保留字段对齐)
var def_value: float = 0.0

## 攻击距离 (像素, 平方比较)
var attack_range_value: float = 0.0

## 攻击频率 (次/秒)
var attack_speed_value: float = 0.0


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


# ========== P2.8 攻击协议 override (从 plain float 字段拿数值; building 无 attribute_set.atk) ==========

func get_atk() -> float:
	return atk_value


func get_def() -> float:
	return def_value


func get_attack_range() -> float:
	return attack_range_value


func get_attack_speed() -> float:
	return attack_speed_value


## 按建筑占地几何计算覆盖的 AABB cells (左上偏置, 偶数尺寸时上半左半).
##
## **M0.4 算法**:
##   - obstruction_shape != null (M0.5 之后): 用 obstruction_shape.center 当 grid 中心,
##     按 obstruction_shape.{width, height} ÷ cell_size 推 cells_w / cells_h.
##     这是 Bug 1 修复路径 — 寻路占地中心跟着 obstruction_shape 走, 跟 sprite 锚点
##     (position_2d) 解耦, 让 sprite 视觉中心和寻路逻辑中心可错位.
##   - obstruction_shape == null (M0.5 工厂注入前 / 单元测试 stub):
##     fallback 到旧路径 — 用 position_2d 当中心, 按 footprint_size: Vector2i 推 cells.
##     M0.4 阶段所有调用方仍走 fallback (obstruction_shape 为 null), 保 smoke 0 漂移.
##
## 例 (新旧两路径同样的 footprint_size=(2,2), position_2d=(160,160), cell_size=32):
##   - 新路径: obstruction_shape.center=(160,160), w=h=64, cells_w=cells_h=2,
##     center_cell=(5,5), 偶数左上偏置 → cells [(4,4),(5,4),(4,5),(5,5)]
##   - 旧路径: position_2d=(160,160), footprint_size=(2,2) → 同样的 cells (bit-identical)
##
## 偏置方向严格保留旧"左上偏置" (上半左半, codex P1 #1 锚点不变), 不改方向.
## 保持与 RtsBuildingPlacement._compute_footprint_cells / RtsBattleMap obstacle cells
## 标记完全一致.
func get_footprint_cells(grid) -> Array:
	if grid == null:
		return []
	# 基类用 untyped `grid` 参数 (向后兼容); 这里取出 HexCoord 时显式标 type 让推导通过。
	if obstruction_shape != null:
		# 新路径 (M0.4): 用 obstruction_shape.center 算 cells (Bug 1 修复).
		# Lazy sync 兜底: M0.5 工厂注入后, 若调方漏调 sync_obstruction_shape() (常见于 tests / diag),
		# obstruction_shape.center 会留在 ZERO 而 position_2d 已 set, 这里救场一次, 避免 cells
		# 围绕 (0,0) 算. M0.7 step 1 加 Log.assert_crash 在 place_building 入口仍会捕获生产路径.
		if obstruction_shape.center == Vector2.ZERO and position_2d != Vector2.ZERO:
			sync_obstruction_shape()
		# delegate 给 Placement core helper, 跟 RtsBuildingPlacement / ghost preview 共享同一份算法,
		# 严格保留旧"左上偏置" (M0.5 抽 core 避免双份漂移)
		return RtsBuildingPlacement._compute_footprint_cells_from_shape(
			obstruction_shape as RtsObstructionShapeStatic, grid)
	# Fallback (M0.4 字段加完前的旧路径; M0.5 工厂注入后 obstruction_shape 非 null 不走此分支)
	var center: HexCoord = grid.world_to_coord(position_2d)
	return RtsBuildingPlacement._compute_footprint_cells_core(center, footprint_size.x, footprint_size.y)


## M0.4 — 把 obstruction_shape.center 设为 position_2d + stats.obstruction_offset.
##
## 必须在 actor.position_2d 设置之后、place_building 之前调用一次, 由 M0.5 6 个 call sites
## 接入 (rts_place_building_command / rts_auto_battle_procedure / demo_rts_frontend
## / demo_rts_pathfinding / rts_scenario_harness / rts_match_preset).
##
## **不变量**: factory 时 obstruction_shape.center == ZERO (因 factory 不知道最终 position);
## 调方写完 position_2d 后必须调本方法把 center 同步到 position_2d + obstruction_offset.
## 否则 obstruction_shape.center 仍 ZERO, 寻路会以为建筑在 (0,0) (M0.7 加 assert 兜底).
##
## obstruction_shape == null 时静默返回 (M0.4 阶段未注入工厂的旧路径); building_kind 不识别时
## RtsBuildingConfig.get_stats 自身 Log.assert_crash.
##
## **M0.5 自动填**: 顺手把 entity_id (来自 actor.get_id) + control_group (来自 team_id) 填上,
## 让调方少写 3 行 boilerplate. 仅当 actor 已 add_actor (get_id 非空) 时填 entity_id;
## team_id < 0 (未 set) 时 control_group 留空字符串 (factory 早期场景).
func sync_obstruction_shape() -> void:
	if obstruction_shape == null:
		return
	var stats: RtsBuildingConfig.StatBlock = RtsBuildingConfig.get_stats(building_kind)
	obstruction_shape.center = position_2d + stats.obstruction_offset
	var actor_id: String = get_id()
	if actor_id != "":
		obstruction_shape.entity_id = actor_id
	if team_id >= 0:
		obstruction_shape.control_group = str(team_id)


# ========== 录像支持 ==========

func _get_config_id() -> String:
	return building_kind


func get_attribute_snapshot() -> Dictionary:
	if attribute_set == null:
		return {}
	return attribute_set.snapshot()
