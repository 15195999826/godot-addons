## RtsBattleGrid - RTS 战场 grid wrapper(包 ultra-grid-map plugin 的 GridMapModel)
##
## 决策来源:
##   - D3-B (2D grid + A*, 不用 navmesh polygon)
##   - D3-F (走 ultra-grid-map plugin, 不动插件本身)
##   - D3-G (cell_size = 32, 标准单位 collision_radius = 14)
##
## 职责:
##   - 封装 GridMapModel (SQUARE grid_type, cell_size = 32) 给 RTS 例子用
##   - 提供 world ↔ cell 坐标转换 (cell 用 plugin 的 HexCoord 类, 即使 SQUARE grid 也是)
##   - Pathing map 写入: 建筑 footprint 标 is_blocking; 单位**不写**(WC3 风)
##   - 单位 footprint 反向索引: cell → set<actor_id>, 服务 Phase 2 spatial 查询的简版前置
##   - 跨 layer is_passable: GROUND 看 is_blocking; AIR 直接 true (Phase 2 P2.8 完整实现)
##
## 与 hex example 的差异: hex 用 UGridMap autoload (单地图全局), RTS 一战斗一个 grid 实例
## (procedure 持有, 战斗结束随 procedure 释放)。Phase 2 P2.7 加 frontend 接入时仍是这个结构。
##
## M1 (2026-05-04): 内部加 RtsNavcellGrid (PackedInt32Array 16-bit 位掩码 multi-class
## passability) 作平行存储, attach_passability_registry 注入后接管 is_passable / is_blocking
## 查询; place_building / remove_building / mark_obstacle_cell 走双写 (model + NavcellGrid)
## 保留 backward compat (smoke 直读 grid.model.is_tile_blocking 的断言不破; M5 删除 facade
## 时一并清理 model 路径)。
##
## 不变量:
##   - cell 坐标用 HexCoord (plugin 约定)
##   - world 坐标用 Vector2
##   - 单位 footprint 不写 pathing, 只更新反向索引; 建筑 footprint 写 pathing
##   - cell 不存在时 is_passable_for_layer 视为阻挡(地图边界)
##   - NavcellGrid attached 时 default class mask bit 与 model.is_tile_blocking 同步 (双写)
class_name RtsBattleGrid
extends RefCounted


# ========== 常量 ==========

## 默认 cell_size (D3-G)
const DEFAULT_CELL_SIZE: float = 32.0


# ========== 字段 ==========

## 包内的 GridMapModel 实例
var model: GridMapModel = null

## 当前 cell_size (像素)
var cell_size: float = DEFAULT_CELL_SIZE

## actor_id → 当前 footprint cell 列表 (HexCoord array)
## 单位每次 update_actor_position 时刷新; 建筑 place_building 时一次性写入。
var _actor_footprint: Dictionary = {}

## cell.to_key() → Dictionary[actor_id, true] (用 Dictionary 模拟 Set)
## 反向索引: 给定一个 cell, 知道有哪些 actor footprint 包含它。
## Phase 2 P2.2 spatial hash 出现前, push-out / 邻域查询走这个简版索引。
var _cell_occupants: Dictionary = {}

## M1: NavcellGrid 平行存储 16-bit 位掩码; attach_passability_registry 时按 model 尺寸 lazy
## 创建; null 时 fallback 走 model.is_tile_blocking (老 smoke 不通过 procedure 创建 grid 时 OK)
var _navcell_grid: RtsNavcellGrid = null

## M1: registry 引用; null = NavcellGrid 未启用 (procedure._init 后必然 attach)
var _passability_registry: RtsPassabilityClassRegistry = null

## M1: default class mask cache (registry attach 时填); 走 NavcellGrid 路径时按此 mask 查
var _default_class_mask: int = 0

## M1: NavcellGrid 0-indexed 偏移 (HexCoord.q + _half_cols → nav i; r + _half_rows → nav j)
## model 用偏移坐标 [-half..+half], NavcellGrid 用 0-indexed [0..columns-1], 需要映射。
var _half_cols: int = 0
var _half_rows: int = 0


# ========== 初始化 ==========

## 构造一个 RTS 战场 grid。
##   - map_size: world 像素尺寸 (用于决定 cell 数量)
##   - p_cell_size: 单 cell 像素 (默认 32, D3-G)
##   - origin: world 左上角对应的 cell (0,0) 起点 (默认 0)
func _init(
	map_size: Vector2 = Vector2(500.0, 500.0),
	p_cell_size: float = DEFAULT_CELL_SIZE,
	origin: Vector2 = Vector2.ZERO,
) -> void:
	cell_size = p_cell_size

	var config := GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.SQUARE
	config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
	config.tile_size = Vector2(p_cell_size, p_cell_size)
	config.origin = origin
	# 生成足够覆盖 map_size 的 cells (中心对称, half_*2+1 = total)
	# 例: map_size=(500,500), cell_size=32 → half_cols=ceil(500/32)=16 → cells [-16..16] = 33×33
	# 负向 cell 是冗余但无害; world (0..500) 落在正向 cell 上。
	_half_cols = int(ceilf(map_size.x / p_cell_size))
	_half_rows = int(ceilf(map_size.y / p_cell_size))
	config.columns = _half_cols * 2 + 1
	config.rows = _half_rows * 2 + 1

	model = GridMapModel.new()
	model.initialize(config)


# ========== M1: NavcellGrid 注入 ==========

## 注入 PassabilityClassRegistry; 同时 lazy 创建匹配 model 尺寸的 NavcellGrid。
##
## 注入后 is_passable_for_layer / is_blocking / mark_obstacle_cell / place_building /
## remove_building 自动走 NavcellGrid 路径 (双写 model 保 backward compat)。
##
## 多次注入安全 (idempotent — 同 registry 不重建 NavcellGrid; 不同 registry 视为重置, 重建)。
func attach_passability_registry(registry: RtsPassabilityClassRegistry) -> void:
	if registry == null:
		return
	if _passability_registry == registry and _navcell_grid != null:
		return
	_passability_registry = registry
	_default_class_mask = registry.get_mask("default")
	# 按 model 尺寸建 NavcellGrid; columns/rows 是奇数 (half_*2+1)
	var cfg: GridMapConfig = model.get_config()
	_navcell_grid = RtsNavcellGrid.new(cfg.columns, cfg.rows)
	# M3.3: 设 NavcellGrid origin 让"world ↔ navcell index" 跟 RtsBattleGrid 的 _coord_to_ij 偏移
	# 一致。NavcellGrid (0, 0) 对应 model HexCoord (-half_cols, -half_rows) 的 world top-left =
	# (-half_cols*32, -half_rows*32)。这让 ObstructionManager 用 world / cell_size 索引 NavcellGrid
	# 时拿到的 (i, j) 跟 RtsBattleGrid._coord_to_ij(coord) 同一坐标系。
	_navcell_grid.set_origin_world(Vector2(-_half_cols, -_half_rows) * cell_size)
	# Sync 已有 model.is_tile_blocking 状态到 NavcellGrid (frontend/_ready 在 procedure._init
	# 之前调 mark_obstacle_cell 设 obstacle 时, NavcellGrid 还未 attach, 所以 model 路径已写
	# 但 NavcellGrid 还 0-state). attach 时把 model already-blocking 的 cells 同步过来。
	for coord in model.get_all_coords():
		if not model.is_tile_blocking(coord):
			continue
		var ij := _coord_to_ij(coord)
		if ij.x >= 0 and ij.x < cfg.columns and ij.y >= 0 and ij.y < cfg.rows:
			_navcell_grid.or_data(ij.x, ij.y, _default_class_mask)


## 当前是否已挂 NavcellGrid (M1 后基本恒为 true; 老 smoke 不走 procedure 时 false)。
func has_navcell_grid() -> bool:
	return _navcell_grid != null


## 取 NavcellGrid 直接引用 (M2+ ObstructionManager rasterize / hierarchical 写入用)。
func get_navcell_grid() -> RtsNavcellGrid:
	return _navcell_grid


## HexCoord (model 偏移坐标 [-half..+half]) → NavcellGrid (i, j) 0-indexed。
## 调方应保证 model.has_tile(coord) (否则结果可能 NavcellGrid 越界, 但 NavcellGrid is_passable
## 已防越界返 false)。
func _coord_to_ij(coord: HexCoord) -> Vector2i:
	return Vector2i(coord.q + _half_cols, coord.r + _half_rows)


# ========== 坐标转换 ==========

## world 坐标 → cell 坐标(HexCoord, 即使是 SQUARE grid 也是)
func world_to_coord(world_pos: Vector2) -> HexCoord:
	return model.world_to_coord(world_pos)


## cell 坐标 → world 坐标(返回 cell 中心, 不是左上角)
##
## ultra-grid-map 的 coord_to_pixel for SQUARE 返回左上角(top-left); 这里加 cell_size/2
## 偏移返回中心, 让寻路 waypoint 落在 cell 中央, 视觉/碰撞更自然。
func coord_to_world(coord: HexCoord) -> Vector2:
	var top_left := model.coord_to_world(coord)
	return top_left + Vector2(cell_size, cell_size) * 0.5


## cell 是否存在(地图边界外返回 false)
func has_tile(coord: HexCoord) -> bool:
	return model.has_tile(coord)


# ========== Layer-aware passable ==========

## Layer 视角下该 cell 是否可通行。
##   - GROUND: NavcellGrid attached 时走 NavcellGrid.is_passable(default_mask), 否则 fallback
##     model.is_tile_blocking 取反
##   - AIR: 永远 true (Phase 1 接口预留, 完整地形限制在 Phase 2 P2.8)
##
## cell 不存在视为阻挡(地图边界)。
func is_passable_for_layer(coord: HexCoord, layer: int) -> bool:
	if not model.has_tile(coord):
		return false
	if layer == MovementLayer.Layer.AIR:
		return true
	return not is_blocking(coord)


## 该 cell 是否阻挡 (default class 视角); NavcellGrid attached 时走 NavcellGrid 路径,
## 否则 fallback model.is_tile_blocking。
##
## 边界外视为阻挡 (跟 0 A.D. is_passable 边界外 false 一致)。
func is_blocking(coord: HexCoord) -> bool:
	if not model.has_tile(coord):
		return true
	if _navcell_grid != null:
		var ij := _coord_to_ij(coord)
		return not _navcell_grid.is_passable(ij.x, ij.y, _default_class_mask)
	return model.is_tile_blocking(coord)


## 把单个 cell 标 obstacle (default class bit); 双写 model + NavcellGrid (attached 时)。
## 给 frontend 地图装饰 / scenario harness 等"非建筑 footprint"路径用。
func mark_obstacle_cell(coord: HexCoord) -> void:
	if not model.has_tile(coord):
		return
	model.set_tile_blocking(coord, true)
	if _navcell_grid != null:
		var ij := _coord_to_ij(coord)
		_navcell_grid.or_data(ij.x, ij.y, _default_class_mask)


## 清单个 cell 的 obstacle 标记; 双写 (但调方负责保 cell 没其它建筑占用; place_building 路径
## 走 remove_building 自动处理)。
func unmark_obstacle_cell(coord: HexCoord) -> void:
	if not model.has_tile(coord):
		return
	model.set_tile_blocking(coord, false)
	if _navcell_grid != null:
		var ij := _coord_to_ij(coord)
		_navcell_grid.and_data(ij.x, ij.y, _default_class_mask)


# ========== Pathing map 写入 (建筑 only) ==========

## 把建筑 footprint cells 标 is_blocking, 同时记录反向索引。
## 调方负责传入子类 RtsBuildingActor.get_footprint_cells(grid)。
##
## M1: 双写 model.set_tile_blocking + NavcellGrid.or_data (attached 时); model 路径
## 保留给老 smoke 直读 grid.model.is_tile_blocking 的断言不破。
func place_building(actor_id: String, footprint_cells: Array) -> void:
	for c in footprint_cells:
		var coord := c as HexCoord
		if coord == null or not model.has_tile(coord):
			continue
		model.set_tile_blocking(coord, true)
		if _navcell_grid != null:
			var ij := _coord_to_ij(coord)
			_navcell_grid.or_data(ij.x, ij.y, _default_class_mask)
		_add_occupant(coord, actor_id)
	_actor_footprint[actor_id] = footprint_cells.duplicate()


## 撤除建筑: 清 is_blocking + 反向索引
##
## M1: 双写 model.set_tile_blocking(false) + NavcellGrid.and_data (attached 时)。
func remove_building(actor_id: String) -> void:
	var cells: Array = _actor_footprint.get(actor_id, []) as Array
	for c in cells:
		var coord := c as HexCoord
		if coord == null:
			continue
		# 仅当本 actor 是唯一占用者时才解 is_blocking; 否则让其他 building 保留阻挡
		_remove_occupant(coord, actor_id)
		if _cell_occupants.get(coord.to_key(), {}).is_empty():
			model.set_tile_blocking(coord, false)
			if _navcell_grid != null:
				var ij := _coord_to_ij(coord)
				_navcell_grid.and_data(ij.x, ij.y, _default_class_mask)
	_actor_footprint.erase(actor_id)


# ========== Footprint 反向索引 (单位用, 不写 pathing) ==========

## 注册单位的 footprint(单位不写 pathing, 只更新反向索引)。
## Phase 1 单位都是 1×1 footprint, 调方传 [center_cell] 即可。
func register_actor(actor_id: String, footprint_cells: Array) -> void:
	# 先清旧的(若存在), 避免泄漏
	if _actor_footprint.has(actor_id):
		_clear_occupants(actor_id)
	for c in footprint_cells:
		var coord := c as HexCoord
		if coord == null:
			continue
		_add_occupant(coord, actor_id)
	_actor_footprint[actor_id] = footprint_cells.duplicate()


## 单位移动到新 cell 时刷新反向索引(footprint 列表变化才需要刷, 没变可跳过)
func update_actor_position(actor_id: String, new_footprint_cells: Array) -> void:
	register_actor(actor_id, new_footprint_cells)


## 单位移除(死亡 / 销毁)
func unregister_actor(actor_id: String) -> void:
	_clear_occupants(actor_id)
	_actor_footprint.erase(actor_id)


## 查询 cell 上的所有 actor_id (返回新数组, 调方可改不影响内部状态)。
## 给 P2.2 spatial hash 之前的临时邻域查询用。
func get_occupants_at(coord: HexCoord) -> Array[String]:
	var key: String = coord.to_key()
	var bucket: Dictionary = _cell_occupants.get(key, {}) as Dictionary
	var result: Array[String] = []
	for k in bucket.keys():
		result.append(k as String)
	return result


# ========== 内部 ==========

func _add_occupant(coord: HexCoord, actor_id: String) -> void:
	var key: String = coord.to_key()
	var bucket: Dictionary = _cell_occupants.get(key, {}) as Dictionary
	bucket[actor_id] = true
	_cell_occupants[key] = bucket


func _remove_occupant(coord: HexCoord, actor_id: String) -> void:
	var key: String = coord.to_key()
	if not _cell_occupants.has(key):
		return
	var bucket: Dictionary = _cell_occupants[key] as Dictionary
	bucket.erase(actor_id)
	if bucket.is_empty():
		_cell_occupants.erase(key)


func _clear_occupants(actor_id: String) -> void:
	var cells: Array = _actor_footprint.get(actor_id, []) as Array
	for c in cells:
		var coord := c as HexCoord
		if coord == null:
			continue
		_remove_occupant(coord, actor_id)
