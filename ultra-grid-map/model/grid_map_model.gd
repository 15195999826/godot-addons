## GridMapModel - 网格地图核心模型
##
## 整合 GridLayout + GridMath + 占用管理的统一模型类
## 支持所有 4 种网格类型: HEX, RECT_SIX_DIR, SQUARE, RECT
##
## 使用方式:
##   var config := GridMapConfig.new()
##   config.grid_type = GridMapConfig.GridType.HEX
##   config.draw_mode = GridMapConfig.DrawMode.RADIUS
##   config.radius = 5
##   config.size = 32.0
##   
##   var model := GridMapModel.new()
##   model.initialize(config)
##
## 参考: HexGridWorld (旧实现)
class_name GridMapModel
extends RefCounted



# ========== GridTileData 内部类 ==========

## 瓦片数据
class GridTileData:
	## 坐标
	var coord: HexCoord
	## 高度 (用于 3D 渲染和寻路，0.0 = 地面)
	var height: float = 0.0
	## 移动代价 (用于寻路)
	var cost: float = 1.0
	## 是否阻挡
	var is_blocking: bool = false
	## 占用者 (Token 或其他对象)
	var occupant: Variant = null
	## 自定义元数据
	var metadata: Dictionary = {}
	
	func _init(p_coord: HexCoord = null) -> void:
		coord = p_coord if p_coord else HexCoord.zero()
	
	## 复制
	func duplicate() -> GridTileData:
		var copy := GridTileData.new(coord.duplicate())
		copy.height = height
		copy.cost = cost
		copy.is_blocking = is_blocking
		copy.occupant = occupant
		copy.metadata = metadata.duplicate()
		return copy


# ========== 信号 ==========

## 瓦片数据变化 (coord: HexCoord)
signal tile_changed(coord, old_data: GridTileData, new_data: GridTileData)

## 高度变化 (coord: HexCoord)
signal height_changed(coord, old_height: float, new_height: float)

## 占用者变化 (coord: HexCoord)
signal occupant_changed(coord, old_occupant: Variant, new_occupant: Variant)


# ========== 配置属性 ==========

## 网格配置
var _config: GridMapConfig

## 布局转换器
var _layout: GridLayout

## 瓦片存储 (key: String via HexCoord.to_key(), value: GridTileData)
var _tiles: Dictionary = {}


# ========== 初始化 ==========

## 使用配置初始化地图
func initialize(config: GridMapConfig) -> void:
	_config = config
	
	# 创建布局转换器
	_layout = GridLayout.new(
		config.grid_type,
		config.size,
		config.origin,
		config.orientation,
		config.tile_size
	)
	
	# 清空现有瓦片
	_tiles.clear()
	
	# 根据绘制模式生成瓦片
	match config.draw_mode:
		GridMapConfig.DrawMode.ROW_COLUMN:
			_generate_tiles_row_column()
		GridMapConfig.DrawMode.RADIUS:
			_generate_tiles_radius()


## 基于行列生成矩形地图（中心对称）
func _generate_tiles_row_column() -> void:
	var half_rows := _config.rows / 2
	var half_cols := _config.columns / 2
	
	match _config.grid_type:
		GridMapConfig.GridType.HEX:
			_generate_hex_row_column(half_rows, half_cols)
		GridMapConfig.GridType.RECT_SIX_DIR:
			_generate_rect_six_dir_row_column(half_rows, half_cols)
		GridMapConfig.GridType.SQUARE, GridMapConfig.GridType.RECT:
			_generate_square_row_column(half_rows, half_cols)


## 生成六边形行列地图
func _generate_hex_row_column(half_rows: int, half_cols: int) -> void:
	# 使用 offset 坐标思路生成矩形，然后转换为 axial 坐标
	for offset_row in range(-half_rows, half_rows + 1):
		for offset_col in range(-half_cols, half_cols + 1):
			var q: int
			var r: int
			if _config.orientation == GridMapConfig.Orientation.FLAT:
				# flat-top: odd-q offset 转 axial
				q = offset_col
				r = offset_row - (offset_col >> 1)
			else:
				# pointy-top: odd-r offset 转 axial
				q = offset_col - (offset_row >> 1)
				r = offset_row
			var coord := HexCoord.new(q, r)
			_tiles[coord.to_key()] = GridTileData.new(coord)


## 生成 RECT_SIX_DIR 行列地图
func _generate_rect_six_dir_row_column(half_rows: int, half_cols: int) -> void:
	for row in range(-half_rows, half_rows + 1):
		for col in range(-half_cols, half_cols + 1):
			var coord := HexCoord.new(col, row)
			_tiles[coord.to_key()] = GridTileData.new(coord)


## 生成正方形/矩形行列地图
func _generate_square_row_column(half_rows: int, half_cols: int) -> void:
	for row in range(-half_rows, half_rows + 1):
		for col in range(-half_cols, half_cols + 1):
			var coord := HexCoord.new(col, row)
			_tiles[coord.to_key()] = GridTileData.new(coord)


## 基于半径生成六边形地图
func _generate_tiles_radius() -> void:
	match _config.grid_type:
		GridMapConfig.GridType.HEX:
			var axial_coords := GridMath.hex_range(Vector2i.ZERO, _config.radius)
			for axial in axial_coords:
				var coord = HexCoord.from_axial(axial)
				_tiles[coord.to_key()] = GridTileData.new(coord)
		GridMapConfig.GridType.RECT_SIX_DIR, GridMapConfig.GridType.SQUARE, GridMapConfig.GridType.RECT:
			# 非六边形类型使用菱形范围
			for x in range(-_config.radius, _config.radius + 1):
				for y in range(-_config.radius, _config.radius + 1):
					var coord = HexCoord.new(x, y)
					_tiles[coord.to_key()] = GridTileData.new(coord)


# ========== 配置访问 ==========

## 获取配置
func get_config() -> GridMapConfig:
	return _config


## 获取网格类型
func get_grid_type() -> GridMapConfig.GridType:
	return _config.grid_type


## 获取布局
func get_layout() -> GridLayout:
	return _layout


# ========== 坐标转换 (代理方法) ==========

## 网格坐标转世界坐标
func coord_to_world(coord: HexCoord) -> Vector2:
	return _layout.coord_to_pixel(coord.to_axial())


## 世界坐标转网格坐标
func world_to_coord(world_pos: Vector2) -> HexCoord:
	var axial: Vector2i = _layout.pixel_to_coord(world_pos)
	return HexCoord.from_axial(axial)


## 获取相邻格子的世界距离
func get_adjacent_world_distance() -> float:
	match _config.grid_type:
		GridMapConfig.GridType.HEX:
			return _config.size * GridLayout.SQRT3
		GridMapConfig.GridType.SQUARE:
			return _config.tile_size.x
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return _config.tile_size.x
	return _config.size


# ========== 邻居查询 (代理方法) ==========

## 获取邻居坐标
func get_neighbors(coord: HexCoord) -> Array[HexCoord]:
	var axial_neighbors := GridMath.get_neighbors(coord.to_axial(), _config.grid_type)
	var result: Array[HexCoord] = []
	for axial in axial_neighbors:
		result.append(HexCoord.from_axial(axial))
	return result


## 获取指定范围内的所有格子
func get_range(center: HexCoord, range_radius: int) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	match _config.grid_type:
		GridMapConfig.GridType.HEX:
			var axial_coords := GridMath.hex_range(center.to_axial(), range_radius)
			for axial in axial_coords:
				result.append(HexCoord.from_axial(axial))
		_:
			# 非六边形使用曼哈顿距离范围
			for x in range(-range_radius, range_radius + 1):
				for y in range(-range_radius, range_radius + 1):
					if absi(x) + absi(y) <= range_radius:
						result.append(HexCoord.new(center.q + x, center.r + y))
	return result


## 计算两个格子之间的距离
func get_distance(from: HexCoord, to: HexCoord) -> int:
	return GridMath.distance(from.to_axial(), to.to_axial(), _config.grid_type)


# ========== 瓦片查询 ==========

## 检查格子是否存在
func has_tile(coord: HexCoord) -> bool:
	return coord.to_key() in _tiles


## 获取瓦片数据
func get_tile(coord: HexCoord) -> GridTileData:
	return _tiles.get(coord.to_key(), null)


## 设置瓦片数据
func set_tile(coord: HexCoord, data: GridTileData) -> void:
	var key: String = coord.to_key()
	var old_data: GridTileData = _tiles.get(key, null)
	_tiles[key] = data
	tile_changed.emit(coord, old_data, data)


## 获取所有格子坐标
func get_all_coords() -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	for key in _tiles.keys():
		result.append(HexCoord.from_key(key))
	return result


## 获取格子数量
func get_tile_count() -> int:
	return _tiles.size()


## 遍历所有瓦片 (callback receives HexCoord and GridTileData)
func for_each_tile(callback: Callable) -> void:
	for key in _tiles.keys():
		var coord = HexCoord.from_key(key)
		callback.call(coord, _tiles[key])


# ========== 高度系统 ==========

## 设置瓦片高度
func set_tile_height(coord: HexCoord, height: float) -> void:
	var tile := get_tile(coord)
	if tile:
		var old_height := tile.height
		tile.height = clampf(height, 0.0, INF)
		height_changed.emit(coord, old_height, tile.height)


## 获取瓦片高度
func get_tile_height(coord: HexCoord) -> float:
	var tile := get_tile(coord)
	if tile:
		return tile.height
	return 1.0


## 批量设置瓦片高度
func set_tiles_height_batch(coords: Array[HexCoord], height: float) -> void:
	for coord in coords:
		set_tile_height(coord, height)


## 设置瓦片代价
func set_tile_cost(coord: HexCoord, cost: float) -> void:
	var tile := get_tile(coord)
	if tile:
		tile.cost = maxf(cost, 0.0)


## 获取瓦片代价
func get_tile_cost(coord: HexCoord) -> float:
	var tile := get_tile(coord)
	if tile:
		return tile.cost
	return 1.0


## 设置瓦片阻挡状态
func set_tile_blocking(coord: HexCoord, blocking: bool) -> void:
	var tile := get_tile(coord)
	if tile:
		tile.is_blocking = blocking


## 检查瓦片是否阻挡
func is_tile_blocking(coord: HexCoord) -> bool:
	var tile := get_tile(coord)
	if tile:
		return tile.is_blocking
	return true  # 不存在的瓦片视为阻挡


# ========== 占用管理 ==========

## 检查格子是否被占用
func is_occupied(coord: HexCoord) -> bool:
	var tile := get_tile(coord)
	if tile:
		return tile.occupant != null
	return false


## 获取格子的占用者
func get_occupant(coord: HexCoord) -> Variant:
	var tile := get_tile(coord)
	if tile:
		return tile.occupant
	return null


## 放置占用者
func place_occupant(coord: HexCoord, occupant: Variant) -> bool:
	if not has_tile(coord):
		return false
	if is_occupied(coord):
		return false
	
	var tile := get_tile(coord)
	var old_occupant: Variant = tile.occupant
	tile.occupant = occupant
	occupant_changed.emit(coord, old_occupant, occupant)
	return true


## 移除占用者
func remove_occupant(coord: HexCoord) -> bool:
	var tile := get_tile(coord)
	if not tile:
		return false
	if tile.occupant == null:
		return false
	
	var old_occupant: Variant = tile.occupant
	tile.occupant = null
	occupant_changed.emit(coord, old_occupant, null)
	return true


## 移动占用者
func move_occupant(from_coord: HexCoord, to_coord: HexCoord) -> bool:
	if not has_tile(to_coord):
		return false
	
	# 移动前先取消目标格子的预订
	cancel_reservation(to_coord)
	
	var from_tile := get_tile(from_coord)
	var to_tile := get_tile(to_coord)
	
	if not from_tile or from_tile.occupant == null:
		return false
	
	if to_tile.occupant != null:
		return false
	
	var occupant: Variant = from_tile.occupant
	
	# 执行移动
	from_tile.occupant = null
	to_tile.occupant = occupant
	
	occupant_changed.emit(from_coord, occupant, null)
	occupant_changed.emit(to_coord, null, occupant)
	return true


## 查找占用者的位置 (null if not found)
func find_occupant_position(occupant: Variant) -> Variant:
	for key in _tiles.keys():
		var tile: GridTileData = _tiles[key]
		if tile.occupant == occupant:
			return HexCoord.from_key(key)
	return null  # 未找到返回 null


## 检查坐标是否可通行 (未被占用且未阻挡)
func is_passable(coord: HexCoord) -> bool:
	var tile := get_tile(coord)
	if not tile:
		return false
	return not tile.is_blocking and tile.occupant == null


## 预订格子
## 使用 metadata 存储预订信息
func reserve_tile(coord: HexCoord, reserver_id: String) -> bool:
	var tile := get_tile(coord)
	if not tile:
		return false
	if tile.occupant != null:
		return false
	var existing_reservation: String = tile.metadata.get("reservation", "")
	if existing_reservation != "" and existing_reservation != reserver_id:
		return false
	tile.metadata["reservation"] = reserver_id
	return true


## 获取格子预订信息
func get_reservation(coord: HexCoord) -> String:
	return get_tile_metadata(coord, "reservation", "") as String


## 取消格子预订
func cancel_reservation(coord: HexCoord) -> void:
	var tile := get_tile(coord)
	if tile and tile.metadata.has("reservation"):
		tile.metadata.erase("reservation")


## 检查格子是否被预订
func is_reserved(coord: HexCoord) -> bool:
	return get_reservation(coord) != ""


# ========== 元数据 ==========

## 设置瓦片元数据
func set_tile_metadata(coord: HexCoord, key: String, value: Variant) -> void:
	var tile := get_tile(coord)
	if tile:
		tile.metadata[key] = value


## 获取瓦片元数据
func get_tile_metadata(coord: HexCoord, key: String, default: Variant = null) -> Variant:
	var tile := get_tile(coord)
	if tile:
		return tile.metadata.get(key, default)
	return default


## 检查瓦片是否有指定元数据
func has_tile_metadata(coord: HexCoord, key: String) -> bool:
	var tile := get_tile(coord)
	if tile:
		return key in tile.metadata
	return false



# ========== 序列化 ==========

## 导出地图配置
func to_config_dict() -> Dictionary:
	var config_dict := {
		"grid_type": _config.grid_type,
		"orientation": _config.orientation,
		"draw_mode": _config.draw_mode,
		"size": _config.size,
		"tile_size": { "x": _config.tile_size.x, "y": _config.tile_size.y },
		"origin": { "x": _config.origin.x, "y": _config.origin.y },
		"rows": _config.rows,
		"columns": _config.columns,
		"radius": _config.radius,
	}
	return config_dict


## 序列化完整状态
func serialize() -> Dictionary:
	var tiles_data: Array = []
	for key in _tiles.keys():
		var tile: GridTileData = _tiles[key]
		var tile_dict := {
			"coord": tile.coord.to_dict(),  # { "q": q, "r": r }
			"height": tile.height,
			"cost": tile.cost,
			"is_blocking": tile.is_blocking,
		}
		if tile.occupant != null:
			# 只保存占用者 ID (如果有)
			if tile.occupant is Dictionary and tile.occupant.has("id"):
				tile_dict["occupant_id"] = tile.occupant["id"]
			elif "id" in tile.occupant:
				tile_dict["occupant_id"] = tile.occupant.id
		if not tile.metadata.is_empty():
			tile_dict["metadata"] = tile.metadata
		tiles_data.append(tile_dict)
	
	return {
		"config": to_config_dict(),
		"tiles": tiles_data,
	}
