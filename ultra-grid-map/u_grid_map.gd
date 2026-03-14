## GridMapAutoload - 通用网格地图全局服务
##
## Autoload 单例，提供全局访问 GridMapModel
##
## 使用方式:
##   # 在战斗开始时配置
##   var config := GridMapConfig.new()
##   config.grid_type = GridMapConfig.GridType.HEX
##   config.draw_mode = GridMapConfig.DrawMode.RADIUS
##   config.radius = 5
##   config.size = 32.0
##   UGridMap.configure(config)
##
##   # 在任何地方使用
##   var coord := HexCoord.new(1, 2)
##   var world_pos := UGridMap.coord_to_world(coord)
##   var neighbors := UGridMap.get_neighbors(coord)
##
## 注意: 必须先调用 configure() 才能使用 model
extends Node




# ========== 信号 ==========

## 当 model 被配置时触发
signal model_configured(new_model: GridMapModel)

## 当 model 被清除时触发
signal model_cleared()


# ========== 属性 ==========

## 当前活跃的网格模型
var model: GridMapModel = null


# ========== 配置方法 ==========

## 配置网格模型
func configure(config: GridMapConfig) -> void:
	if config == null:
		push_error("[GridMap] Cannot configure with null config")
		return
	
	# 创建新模型
	var new_model := GridMapModel.new()
	new_model.initialize(config)
	
	model = new_model
	model_configured.emit(new_model)


## 清除当前模型
func clear() -> void:
	model = null
	model_cleared.emit()


## 检查是否已配置
func is_configured() -> bool:
	return model != null


## 从字典配置网格模型 (兼容旧 HexGrid API)
## @param config_dict: 配置字典，支持以下字段:
##   - draw_mode: "row_column" | "radius"
##   - rows: int (row_column 模式)
##   - columns: int (row_column 模式)
##   - radius: int (radius 模式)
##   - size: float (默认 10.0)
##   - orientation: "flat" | "pointy" (默认 "flat")
func configure_from_dict(config_dict: Dictionary) -> void:
	var config := GridMapConfig.new()
	
	# 网格类型 (默认 HEX)
	config.grid_type = GridMapConfig.GridType.HEX
	
	# 尺寸
	config.size = config_dict.get("size", 10.0)
	
	# 方向（支持枚举值）
	var orientation_val: int = config_dict.get("orientation", GridMapConfig.Orientation.FLAT) as int
	config.orientation = orientation_val as GridMapConfig.Orientation
	
	# 绘制模式（支持枚举值）
	var draw_mode_val: int = config_dict.get("draw_mode", GridMapConfig.DrawMode.ROW_COLUMN) as int
	config.draw_mode = draw_mode_val as GridMapConfig.DrawMode
	if config.draw_mode == GridMapConfig.DrawMode.RADIUS:
		config.radius = config_dict.get("radius", 4)
	else:
		config.rows = config_dict.get("rows", 9)
		config.columns = config_dict.get("columns", 9)
	
	configure(config)


# ========== 便捷方法（直接转发到 model）==========

## 网格坐标转世界坐标
func coord_to_world(coord: HexCoord) -> Vector2:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return Vector2.ZERO
	return model.coord_to_world(coord)


## 世界坐标转网格坐标
func world_to_coord(world_pos: Vector2) -> HexCoord:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return HexCoord.zero()
	return model.world_to_coord(world_pos)


## 获取邻居坐标
func get_neighbors(coord: HexCoord) -> Array[HexCoord]:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return []
	return model.get_neighbors(coord)


## 计算两个格子之间的距离
func get_distance(from: HexCoord, to: HexCoord) -> int:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return 0
	return model.get_distance(from, to)


## 检查坐标是否可通行
func is_passable(coord: HexCoord) -> bool:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return false
	return model.is_passable(coord)


## 获取瓦片数据
func get_tile(coord: HexCoord) -> GridMapModel.GridTileData:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return null
	return model.get_tile(coord)


## 检查格子是否存在
func has_tile(coord: HexCoord) -> bool:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return false
	return model.has_tile(coord)


## 获取指定范围内的所有格子
func get_range(center: HexCoord, range_radius: int) -> Array[HexCoord]:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return []
	return model.get_range(center, range_radius)


## 获取所有格子坐标
func get_all_coords() -> Array[HexCoord]:
	if model == null:
		push_error("[GridMap] Model not configured. Call configure() first.")
		return []
	return model.get_all_coords()
