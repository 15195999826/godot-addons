class_name GridMapRenderer2D
extends Node2D

## 2D 通用网格渲染器
##
## 负责渲染任意类型网格的线框、高亮和填充效果。
## 支持 HEX, SQUARE, RECT 等所有 GridMapModel 支持的网格类型。
## 使用 Node2D 的 _draw() 方法进行渲染。

## 网格线框颜色
@export var grid_color: Color = Color.WHITE

## 高亮颜色
@export var highlight_color: Color = Color.YELLOW

## 填充颜色
@export var fill_color: Color = Color(0.2, 0.6, 1.0, 0.3)

## 线条宽度
@export var line_width: float = 2.0

# 内部状态
var _model: GridMapModel = null
var _show_grid: bool = false
var _highlighted_tiles: Dictionary = {}  # String (key) -> Color
var _filled_tiles: Dictionary = {}  # String (key) -> Color



## 设置要渲染的网格模型
##
## @param model: GridMapModel 实例，传入 null 会清空渲染器
func set_model(model: GridMapModel) -> void:
	_model = model
	queue_redraw()


## 渲染网格线框
##
## 绘制所有格子的边框线条
func render_grid() -> void:
	_show_grid = true
	queue_redraw()


## 高亮指定的格子
##
## @param coords: 要高亮的格子坐标数组 (Array[HexCoord])
## @param color: 高亮颜色，默认使用 highlight_color
func highlight_tiles(coords: Array, color: Color = highlight_color) -> void:
	for coord in coords:
		_highlighted_tiles[coord.to_key()] = color
	queue_redraw()


## 填充指定的格子
##
## @param coords: 要填充的格子坐标数组 (Array[HexCoord])
## @param color: 填充颜色，默认使用 fill_color
func fill_tiles(coords: Array, color: Color = fill_color) -> void:
	for coord in coords:
		_filled_tiles[coord.to_key()] = color
	queue_redraw()


## 清除所有高亮
func clear_highlights() -> void:
	_highlighted_tiles.clear()
	queue_redraw()


## 清除所有填充
func clear_fills() -> void:
	_filled_tiles.clear()
	queue_redraw()


## 清除所有渲染效果（网格、高亮、填充）
func clear_all() -> void:
	_show_grid = false
	_highlighted_tiles.clear()
	_filled_tiles.clear()
	queue_redraw()


## 核心渲染方法
func _draw() -> void:
	if _model == null:
		return
	
	var layout := _model.get_layout()
	var grid_type := _model.get_config().grid_type
	
	# 绘制网格线框
	if _show_grid:
		for coord in _model.get_all_coords():
			var points := _get_tile_corners(layout, grid_type, coord.to_axial())
			if points.size() > 0:
				points.append(points[0])  # 闭合形状
				draw_polyline(points, grid_color, line_width)
	
	# 绘制填充（在线框之前，避免遮挡）
	for key in _filled_tiles.keys():
		var coord: HexCoord = HexCoord.from_key(key)
		var points := _get_tile_corners(layout, grid_type, coord.to_axial())
		if points.size() > 0:
			var colors := PackedColorArray([_filled_tiles[key]])
			draw_polygon(points, colors)
	
	# 绘制高亮（在最上层）
	for key in _highlighted_tiles.keys():
		var coord: HexCoord = HexCoord.from_key(key)
		var points := _get_tile_corners(layout, grid_type, coord.to_axial())
		if points.size() > 0:
			points.append(points[0])  # 闭合形状
			draw_polyline(points, _highlighted_tiles[key], line_width * 1.5)


## 获取格子角点（辅助方法）
func _get_tile_corners(layout: GridLayout, grid_type: int, coord: Vector2i) -> PackedVector2Array:
	if grid_type == GridMapConfig.GridType.HEX:
		return layout.hex_corners(coord)
	else:
		# SQUARE, RECT, RECT_SIX_DIR 都使用矩形角点
		return layout.rect_corners(coord)
