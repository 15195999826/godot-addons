## CoordConverter - 坐标系统转换工具
##
## 提供不同坐标系统之间的转换功能（纯静态工具类）
##
## 支持的坐标系统:
## - Axial: (q, r) 六边形主坐标系，使用 HexCoord 或 Vector2i
## - Cube: (q, r, s) 约束 q + r + s = 0，使用 Vector3i
## - Offset: (col, row) 四种变体 (odd-q, even-q, odd-r, even-r)
## - Doubled: (col, row) 两种变体 (width, height)
## - Cartesian: (x, y) 直接映射 (正方形/矩形)
##
## 注意: Axial <-> Cube 转换请使用 HexCoord.to_cube() / HexCoord.from_cube()
##
## 参考: https://www.redblobgames.com/grids/hexagons/
class_name CoordConverter
extends RefCounted


# ========== 枚举 ==========

## Offset 坐标类型 (六边形)
enum OffsetType {
	ODD_Q,   ## Flat-top, 奇数列下移
	EVEN_Q,  ## Flat-top, 偶数列下移
	ODD_R,   ## Pointy-top, 奇数行右移
	EVEN_R,  ## Pointy-top, 偶数行右移
}

## Doubled 坐标类型 (六边形)
enum DoubledType {
	WIDTH,   ## Flat-top, col = 2*q + r
	HEIGHT,  ## Pointy-top, row = 2*r + q
}


# ========== 取整 (像素转坐标时使用) ==========

## Cube 坐标取整 (用于像素转六边形)
## 返回满足 q + r + s = 0 约束的最近整数坐标
static func cube_round(frac_q: float, frac_r: float, frac_s: float) -> Vector3i:
	var q := roundi(frac_q)
	var r := roundi(frac_r)
	var s := roundi(frac_s)
	
	var q_diff := absf(q - frac_q)
	var r_diff := absf(r - frac_r)
	var s_diff := absf(s - frac_s)
	
	# 修正误差最大的分量以满足 q + r + s = 0
	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s
	else:
		s = -q - r
	
	return Vector3i(q, r, s)


## Axial 坐标取整
## 返回 Vector2i (q, r)
static func axial_round(frac_q: float, frac_r: float) -> Vector2i:
	var cube_coord := cube_round(frac_q, frac_r, -frac_q - frac_r)
	return Vector2i(cube_coord.x, cube_coord.y)


# ========== 验证 ==========

## 验证 Cube 坐标是否有效 (q + r + s == 0)
static func cube_is_valid(coord: Vector3i) -> bool:
	return coord.x + coord.y + coord.z == 0


## 验证 Doubled 坐标是否有效 (col + row 必须为偶数)
static func doubled_is_valid(coord: Vector2i) -> bool:
	return (coord.x + coord.y) % 2 == 0


# ========== Offset <-> Cube 转换 ==========

## Offset 转 Cube
static func offset_to_cube(coord: Vector2i, offset_type: OffsetType) -> Vector3i:
	var q: int
	var r: int
	
	match offset_type:
		OffsetType.ODD_Q:
			q = coord.x
			r = coord.y - (coord.x - (coord.x & 1)) / 2
		OffsetType.EVEN_Q:
			q = coord.x
			r = coord.y - (coord.x + (coord.x & 1)) / 2
		OffsetType.ODD_R:
			q = coord.x - (coord.y - (coord.y & 1)) / 2
			r = coord.y
		OffsetType.EVEN_R:
			q = coord.x - (coord.y + (coord.y & 1)) / 2
			r = coord.y
	
	return Vector3i(q, r, -q - r)


## Cube 转 Offset
static func cube_to_offset(coord: Vector3i, offset_type: OffsetType) -> Vector2i:
	var col: int
	var row: int
	
	match offset_type:
		OffsetType.ODD_Q:
			col = coord.x
			row = coord.y + (coord.x - (coord.x & 1)) / 2
		OffsetType.EVEN_Q:
			col = coord.x
			row = coord.y + (coord.x + (coord.x & 1)) / 2
		OffsetType.ODD_R:
			col = coord.x + (coord.y - (coord.y & 1)) / 2
			row = coord.y
		OffsetType.EVEN_R:
			col = coord.x + (coord.y + (coord.y & 1)) / 2
			row = coord.y
	
	return Vector2i(col, row)


# ========== Offset <-> Axial 转换 ==========

## Offset 转 Axial
static func offset_to_axial(coord: Vector2i, offset_type: OffsetType) -> Vector2i:
	var cube_coord := offset_to_cube(coord, offset_type)
	return Vector2i(cube_coord.x, cube_coord.y)


## Axial 转 Offset
static func axial_to_offset(coord: Vector2i, offset_type: OffsetType) -> Vector2i:
	var cube_coord := Vector3i(coord.x, coord.y, -coord.x - coord.y)
	return cube_to_offset(cube_coord, offset_type)


# ========== Doubled <-> Axial 转换 ==========

## Doubled 转 Axial
static func doubled_to_axial(coord: Vector2i, doubled_type: DoubledType) -> Vector2i:
	match doubled_type:
		DoubledType.WIDTH:
			# col = 2*q + r, row = r
			# q = (col - row) / 2, r = row
			return Vector2i((coord.x - coord.y) / 2, coord.y)
		DoubledType.HEIGHT:
			# col = q, row = 2*r + q
			# q = col, r = (row - col) / 2
			return Vector2i(coord.x, (coord.y - coord.x) / 2)
	
	return Vector2i.ZERO


## Axial 转 Doubled
static func axial_to_doubled(coord: Vector2i, doubled_type: DoubledType) -> Vector2i:
	match doubled_type:
		DoubledType.WIDTH:
			# col = 2*q + r, row = r
			return Vector2i(2 * coord.x + coord.y, coord.y)
		DoubledType.HEIGHT:
			# col = q, row = 2*r + q
			return Vector2i(coord.x, 2 * coord.y + coord.x)
	
	return Vector2i.ZERO


# ========== Doubled <-> Cube 转换 ==========

## Doubled 转 Cube
static func doubled_to_cube(coord: Vector2i, doubled_type: DoubledType) -> Vector3i:
	var axial_coord := doubled_to_axial(coord, doubled_type)
	return Vector3i(axial_coord.x, axial_coord.y, -axial_coord.x - axial_coord.y)


## Cube 转 Doubled
static func cube_to_doubled(coord: Vector3i, doubled_type: DoubledType) -> Vector2i:
	var axial_coord := Vector2i(coord.x, coord.y)
	return axial_to_doubled(axial_coord, doubled_type)


# ========== Cartesian (正方形/矩形) ==========

## Cartesian 转 Axial (直接映射，无转换)
## 用于统一接口，正方形/矩形坐标直接映射到 Vector2i
static func cartesian_to_axial(coord: Vector2i) -> Vector2i:
	return coord


## Axial 转 Cartesian (直接映射，无转换)
## 用于统一接口，正方形/矩形坐标直接映射到 Vector2i
static func axial_to_cartesian(coord: Vector2i) -> Vector2i:
	return coord
