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
## 不变量:
##   - cell 坐标用 HexCoord (plugin 约定)
##   - world 坐标用 Vector2
##   - 单位 footprint 不写 pathing, 只更新反向索引; 建筑 footprint 写 pathing
##   - cell 不存在时 is_passable_for_layer 视为阻挡(地图边界)
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
	var half_cols: int = int(ceilf(map_size.x / p_cell_size))
	var half_rows: int = int(ceilf(map_size.y / p_cell_size))
	config.columns = half_cols * 2 + 1
	config.rows = half_rows * 2 + 1

	model = GridMapModel.new()
	model.initialize(config)


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
##   - GROUND: not is_blocking
##   - AIR: 永远 true (Phase 1 接口预留, 完整地形限制在 Phase 2 P2.8)
##
## cell 不存在视为阻挡(地图边界)。
func is_passable_for_layer(coord: HexCoord, layer: int) -> bool:
	if not model.has_tile(coord):
		return false
	if layer == MovementLayer.Layer.AIR:
		return true
	return not model.is_tile_blocking(coord)


# ========== Pathing map 写入 (建筑 only) ==========

## 把建筑 footprint cells 标 is_blocking, 同时记录反向索引。
## 调方负责传入子类 RtsBuildingActor.get_footprint_cells(grid)。
func place_building(actor_id: String, footprint_cells: Array) -> void:
	for c in footprint_cells:
		var coord := c as HexCoord
		if coord == null or not model.has_tile(coord):
			continue
		model.set_tile_blocking(coord, true)
		_add_occupant(coord, actor_id)
	_actor_footprint[actor_id] = footprint_cells.duplicate()


## 撤除建筑: 清 is_blocking + 反向索引
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
