## GridLayout - 网格像素坐标转换
##
## 支持所有网格类型的像素坐标转换:
## - HEX: 六边形 (Flat-top/Pointy-top)
## - SQUARE: 正方形
## - RECT: 矩形
## - RECT_SIX_DIR: 六方向矩形 (与 SQUARE 相同)
##
## 使用方式:
##   var layout := GridLayout.new(GridMapConfig.GridType.HEX, 32.0, Vector2.ZERO, GridMapConfig.Orientation.POINTY)
##   var pixel := layout.coord_to_pixel(Vector2i(1, 2))
##   var coord := layout.pixel_to_coord(Vector2(100, 100))
##
## 参考: https://www.redblobgames.com/grids/hexagons/
class_name GridLayout
extends RefCounted



# ========== 常量 ==========

const SQRT3 := 1.7320508075688772935


# ========== 方向矩阵 (六边形) ==========

## Flat-top 方向矩阵
## f: hex -> pixel, b: pixel -> hex
const FLAT_ORIENTATION := {
	"f0": 1.5,
	"f1": 0.0,
	"f2": SQRT3 / 2.0,
	"f3": SQRT3,
	"b0": 2.0 / 3.0,
	"b1": 0.0,
	"b2": -1.0 / 3.0,
	"b3": SQRT3 / 3.0,
	"start_angle": 0.0,  # 第一个角的角度 (弧度)
}

## Pointy-top 方向矩阵
const POINTY_ORIENTATION := {
	"f0": SQRT3,
	"f1": SQRT3 / 2.0,
	"f2": 0.0,
	"f3": 1.5,
	"b0": SQRT3 / 3.0,
	"b1": -1.0 / 3.0,
	"b2": 0.0,
	"b3": 2.0 / 3.0,
	"start_angle": 0.5,  # 30度 (以 60度为单位)
}


# ========== 属性 ==========

## 网格类型
var grid_type: GridMapConfig.GridType

## 网格方向 (六边形: FLAT/POINTY)
var orientation: GridMapConfig.Orientation

## 网格大小 (六边形: 中心到角的距离)
var size: float

## 瓦片大小 (正方形/矩形)
var tile_size: Vector2

## 原点偏移
var origin: Vector2

## 当前使用的方向矩阵 (六边形)
var _matrix: Dictionary


# ========== 构造 ==========

func _init(
	p_grid_type: GridMapConfig.GridType = GridMapConfig.GridType.HEX,
	p_size: float = 32.0,
	p_origin: Vector2 = Vector2.ZERO,
	p_orientation: GridMapConfig.Orientation = GridMapConfig.Orientation.POINTY,
	p_tile_size: Vector2 = Vector2(32.0, 32.0)
) -> void:
	grid_type = p_grid_type
	size = p_size
	origin = p_origin
	orientation = p_orientation
	tile_size = p_tile_size
	_update_matrix()


func _update_matrix() -> void:
	if orientation == GridMapConfig.Orientation.FLAT:
		_matrix = FLAT_ORIENTATION.duplicate()
	else:
		_matrix = POINTY_ORIENTATION.duplicate()


# ========== 配置 ==========

## 设置网格类型
func set_grid_type(p_grid_type: GridMapConfig.GridType) -> void:
	grid_type = p_grid_type


## 设置方向
func set_orientation(p_orientation: GridMapConfig.Orientation) -> void:
	orientation = p_orientation
	_update_matrix()


## 设置大小
func set_size(p_size: float) -> void:
	size = p_size


## 设置瓦片大小
func set_tile_size(p_tile_size: Vector2) -> void:
	tile_size = p_tile_size


## 设置原点
func set_origin(p_origin: Vector2) -> void:
	origin = p_origin


## 从配置初始化
func from_config(config: GridMapConfig) -> void:
	grid_type = config.grid_type
	orientation = config.orientation
	size = config.size
	tile_size = config.tile_size
	origin = config.origin
	_update_matrix()


# ========== 尺寸计算 ==========

## 获取网格宽度
func get_cell_width() -> float:
	match grid_type:
		GridMapConfig.GridType.HEX:
			if orientation == GridMapConfig.Orientation.FLAT:
				return size * 2.0
			else:
				return size * SQRT3
		GridMapConfig.GridType.SQUARE:
			return tile_size.x
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return tile_size.x
	return tile_size.x


## 获取网格高度
func get_cell_height() -> float:
	match grid_type:
		GridMapConfig.GridType.HEX:
			if orientation == GridMapConfig.Orientation.FLAT:
				return size * SQRT3
			else:
				return size * 2.0
		GridMapConfig.GridType.SQUARE:
			return tile_size.y
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return tile_size.y
	return tile_size.y


## 获取水平间距 (相邻列中心距离)
func get_horizontal_spacing() -> float:
	match grid_type:
		GridMapConfig.GridType.HEX:
			if orientation == GridMapConfig.Orientation.FLAT:
				return size * 1.5
			else:
				return size * SQRT3
		GridMapConfig.GridType.SQUARE:
			return tile_size.x
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return tile_size.x
	return tile_size.x


## 获取垂直间距 (相邻行中心距离)
func get_vertical_spacing() -> float:
	match grid_type:
		GridMapConfig.GridType.HEX:
			if orientation == GridMapConfig.Orientation.FLAT:
				return size * SQRT3
			else:
				return size * 1.5
		GridMapConfig.GridType.SQUARE:
			return tile_size.y
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return tile_size.y
	return tile_size.y


# ========== 坐标转换 (统一接口) ==========

## 网格坐标转像素坐标
func coord_to_pixel(coord: Vector2i) -> Vector2:
	match grid_type:
		GridMapConfig.GridType.HEX:
			return _hex_to_pixel(coord)
		GridMapConfig.GridType.SQUARE:
			return _square_to_pixel(coord)
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return _rect_to_pixel(coord)
	return Vector2.ZERO


## 像素坐标转网格坐标
func pixel_to_coord(pixel: Vector2) -> Vector2i:
	match grid_type:
		GridMapConfig.GridType.HEX:
			return _pixel_to_hex(pixel)
		GridMapConfig.GridType.SQUARE:
			return _pixel_to_square(pixel)
		GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			return _pixel_to_rect(pixel)
	return Vector2i.ZERO


## 像素坐标转浮点网格坐标 (不取整)
func pixel_to_coord_frac(pixel: Vector2) -> Vector2:
	match grid_type:
		GridMapConfig.GridType.HEX:
			return _pixel_to_hex_frac(pixel)
		GridMapConfig.GridType.SQUARE, GridMapConfig.GridType.RECT, GridMapConfig.GridType.RECT_SIX_DIR:
			var pt: Vector2 = pixel - origin
			return Vector2(pt.x / tile_size.x, pt.y / tile_size.y)
	return Vector2.ZERO


# ========== 六边形像素转换 (内部) ==========

## 六边形坐标转像素坐标 (Axial)
func _hex_to_pixel(coord: Vector2i) -> Vector2:
	var f0: float = _matrix["f0"]
	var f1: float = _matrix["f1"]
	var f2: float = _matrix["f2"]
	var f3: float = _matrix["f3"]
	var x: float = (f0 * coord.x + f1 * coord.y) * size
	var y: float = (f2 * coord.x + f3 * coord.y) * size
	return Vector2(x, y) + origin


## 像素坐标转六边形坐标 (Axial)
func _pixel_to_hex(pixel: Vector2) -> Vector2i:
	var pt: Vector2 = (pixel - origin) / size
	var b0: float = _matrix["b0"]
	var b1: float = _matrix["b1"]
	var b2: float = _matrix["b2"]
	var b3: float = _matrix["b3"]
	var q: float = b0 * pt.x + b1 * pt.y
	var r: float = b2 * pt.x + b3 * pt.y
	return CoordConverter.axial_round(q, r)


## 像素坐标转浮点六边形坐标 (不取整)
func _pixel_to_hex_frac(pixel: Vector2) -> Vector2:
	var pt: Vector2 = (pixel - origin) / size
	var b0: float = _matrix["b0"]
	var b1: float = _matrix["b1"]
	var b2: float = _matrix["b2"]
	var b3: float = _matrix["b3"]
	var q: float = b0 * pt.x + b1 * pt.y
	var r: float = b2 * pt.x + b3 * pt.y
	return Vector2(q, r)


# ========== 正方形像素转换 (内部) ==========

## 正方形坐标转像素坐标
func _square_to_pixel(coord: Vector2i) -> Vector2:
	var x: float = coord.x * tile_size.x
	var y: float = coord.y * tile_size.y
	return Vector2(x, y) + origin


## 像素坐标转正方形坐标
func _pixel_to_square(pixel: Vector2) -> Vector2i:
	var pt: Vector2 = pixel - origin
	var x: int = floori(pt.x / tile_size.x)
	var y: int = floori(pt.y / tile_size.y)
	return Vector2i(x, y)


# ========== 矩形像素转换 (内部) ==========

## 矩形坐标转像素坐标
func _rect_to_pixel(coord: Vector2i) -> Vector2:
	var x: float = coord.x * tile_size.x
	var y: float = coord.y * tile_size.y
	return Vector2(x, y) + origin


## 像素坐标转矩形坐标
func _pixel_to_rect(pixel: Vector2) -> Vector2i:
	var pt: Vector2 = pixel - origin
	var x: int = floori(pt.x / tile_size.x)
	var y: int = floori(pt.y / tile_size.y)
	return Vector2i(x, y)


# ========== 角点计算 (六边形) ==========

## 获取六边形的一个角点偏移 (相对于中心)
## corner: 0-5
func hex_corner_offset(corner: int) -> Vector2:
	var start_angle: float = _matrix["start_angle"]
	var angle: float = 2.0 * PI * (start_angle + corner) / 6.0
	return Vector2(size * cos(angle), size * sin(angle))


## 获取六边形的所有角点 (世界坐标)
func hex_corners(coord: Vector2i) -> PackedVector2Array:
	var corners := PackedVector2Array()
	var center: Vector2 = coord_to_pixel(coord)
	
	for i in range(6):
		corners.append(center + hex_corner_offset(i))
	
	return corners


## 获取六边形的一条边的中点偏移 (相对于中心)
## edge: 0-5
func hex_edge_midpoint_offset(edge: int) -> Vector2:
	var corner1: Vector2 = hex_corner_offset(edge)
	var corner2: Vector2 = hex_corner_offset((edge + 1) % 6)
	return (corner1 + corner2) / 2.0


## 获取六边形的所有边中点 (世界坐标)
func hex_edge_midpoints(coord: Vector2i) -> PackedVector2Array:
	var midpoints := PackedVector2Array()
	var center: Vector2 = coord_to_pixel(coord)
	
	for i in range(6):
		midpoints.append(center + hex_edge_midpoint_offset(i))
	
	return midpoints


# ========== 角点计算 (正方形/矩形) ==========

## 获取正方形/矩形的所有角点 (世界坐标)
func rect_corners(coord: Vector2i) -> PackedVector2Array:
	var corners := PackedVector2Array()
	var center: Vector2 = coord_to_pixel(coord)
	var half_w: float = tile_size.x / 2.0
	var half_h: float = tile_size.y / 2.0
	
	corners.append(center + Vector2(-half_w, -half_h))  # 左上
	corners.append(center + Vector2(half_w, -half_h))   # 右上
	corners.append(center + Vector2(half_w, half_h))    # 右下
	corners.append(center + Vector2(-half_w, half_h))   # 左下
	
	return corners


# ========== Cube 坐标支持 (六边形) ==========

## Cube 坐标转像素坐标
func cube_to_pixel(coord: Vector3i) -> Vector2:
	return coord_to_pixel(Vector2i(coord.x, coord.y))


## 像素坐标转 Cube 坐标
func pixel_to_cube(pixel: Vector2) -> Vector3i:
	var axial_coord: Vector2i = pixel_to_coord(pixel)
	return Vector3i(axial_coord.x, axial_coord.y, -axial_coord.x - axial_coord.y)


# ========== 静态转换方法 (无需实例化) ==========

## Flat-top: 六边形转像素
static func flat_hex_to_pixel(coord: Vector2i, hex_size: float) -> Vector2:
	var x: float = hex_size * (1.5 * float(coord.x))
	var y: float = hex_size * (SQRT3 / 2.0 * float(coord.x) + SQRT3 * float(coord.y))
	return Vector2(x, y)


## Flat-top: 像素转六边形
static func flat_pixel_to_hex(pixel: Vector2, hex_size: float) -> Vector2i:
	var q: float = (2.0 / 3.0 * pixel.x) / hex_size
	var r: float = (-1.0 / 3.0 * pixel.x + SQRT3 / 3.0 * pixel.y) / hex_size
	return CoordConverter.axial_round(q, r)


## Pointy-top: 六边形转像素
static func pointy_hex_to_pixel(coord: Vector2i, hex_size: float) -> Vector2:
	var x: float = hex_size * (SQRT3 * float(coord.x) + SQRT3 / 2.0 * float(coord.y))
	var y: float = hex_size * (1.5 * float(coord.y))
	return Vector2(x, y)


## Pointy-top: 像素转六边形
static func pointy_pixel_to_hex(pixel: Vector2, hex_size: float) -> Vector2i:
	var q: float = (SQRT3 / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / hex_size
	var r: float = (2.0 / 3.0 * pixel.y) / hex_size
	return CoordConverter.axial_round(q, r)


## 正方形: 坐标转像素
static func square_to_pixel(coord: Vector2i, cell_size: float) -> Vector2:
	return Vector2(coord.x * cell_size, coord.y * cell_size)


## 正方形: 像素转坐标
static func pixel_to_square(pixel: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(floori(pixel.x / cell_size), floori(pixel.y / cell_size))


## 矩形: 坐标转像素
static func rect_to_pixel(coord: Vector2i, p_tile_size: Vector2) -> Vector2:
	return Vector2(coord.x * p_tile_size.x, coord.y * p_tile_size.y)


## 矩形: 像素转坐标
static func pixel_to_rect(pixel: Vector2, p_tile_size: Vector2) -> Vector2i:
	return Vector2i(floori(pixel.x / p_tile_size.x), floori(pixel.y / p_tile_size.y))
