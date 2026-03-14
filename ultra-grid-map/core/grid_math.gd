## GridMath - 网格数学运算
##
## 提供所有网格类型的数学算法:
## - 距离计算 (六边形 Cube 距离、曼哈顿距离、切比雪夫距离)
## - 邻居查找 (支持 HEX, RECT_SIX_DIR, SQUARE, RECT)
## - 范围查询
## - 环和螺旋
## - 线段绘制
## - 旋转和反射
##
## 所有方法使用 Vector2i 或 Vector3i 坐标
## 参考: https://www.redblobgames.com/grids/hexagons/
class_name GridMath
extends RefCounted




# ========== 六边形方向常量 ==========

## 6 个邻居方向 (Axial 坐标)
## 顺序: 右、右上、左上、左、左下、右下
const HEX_AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),    # 0: 右 (E)
	Vector2i(1, -1),   # 1: 右上 (NE)
	Vector2i(0, -1),   # 2: 左上 (NW)
	Vector2i(-1, 0),   # 3: 左 (W)
	Vector2i(-1, 1),   # 4: 左下 (SW)
	Vector2i(0, 1),    # 5: 右下 (SE)
]

## 6 个邻居方向 (Cube 坐标)
const HEX_CUBE_DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, -1, 0),   # 0: 右 (E)
	Vector3i(1, 0, -1),   # 1: 右上 (NE)
	Vector3i(0, 1, -1),   # 2: 左上 (NW)
	Vector3i(-1, 1, 0),   # 3: 左 (W)
	Vector3i(-1, 0, 1),   # 4: 左下 (SW)
	Vector3i(0, -1, 1),   # 5: 右下 (SE)
]

## 6 个对角方向 (Cube 坐标)
const HEX_CUBE_DIAGONALS: Array[Vector3i] = [
	Vector3i(2, -1, -1),  # 0
	Vector3i(1, 1, -2),   # 1
	Vector3i(-1, 2, -1),  # 2
	Vector3i(-2, 1, 1),   # 3
	Vector3i(-1, -1, 2),  # 4
	Vector3i(1, -2, 1),   # 5
]

## 6 个对角方向 (Axial 坐标)
const HEX_AXIAL_DIAGONALS: Array[Vector2i] = [
	Vector2i(2, -1),   # 0
	Vector2i(1, 1),    # 1
	Vector2i(-1, 2),   # 2
	Vector2i(-2, 1),   # 3
	Vector2i(-1, -1),  # 4
	Vector2i(1, -2),   # 5
]


# ========== RECT_SIX_DIR 方向常量 ==========

## RECT_SIX_DIR 偶数行邻居方向 (row % 2 == 0)
const RECT_SIX_DIR_EVEN: Array[Vector2i] = [
	Vector2i(1, 0),    # 右
	Vector2i(0, -1),   # 上
	Vector2i(-1, -1),  # 左上
	Vector2i(-1, 0),   # 左
	Vector2i(-1, 1),   # 左下
	Vector2i(0, 1),    # 下
]

## RECT_SIX_DIR 奇数行邻居方向 (row % 2 == 1)
const RECT_SIX_DIR_ODD: Array[Vector2i] = [
	Vector2i(1, 0),    # 右
	Vector2i(1, -1),   # 右上
	Vector2i(0, -1),   # 上
	Vector2i(-1, 0),   # 左
	Vector2i(0, 1),    # 下
	Vector2i(1, 1),    # 右下
]


# ========== 正方形/矩形方向常量 ==========

## SQUARE 4 方向邻居 (上下左右)
const SQUARE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),    # 右
	Vector2i(0, -1),   # 上
	Vector2i(-1, 0),   # 左
	Vector2i(0, 1),    # 下
]

## SQUARE 8 方向邻居 (包含对角)
const SQUARE_DIRECTIONS_8: Array[Vector2i] = [
	Vector2i(1, 0),    # 右
	Vector2i(1, -1),   # 右上
	Vector2i(0, -1),   # 上
	Vector2i(-1, -1),  # 左上
	Vector2i(-1, 0),   # 左
	Vector2i(-1, 1),   # 左下
	Vector2i(0, 1),    # 下
	Vector2i(1, 1),    # 右下
]


# ========== 距离计算 ==========

## 计算六边形距离 (Axial 坐标)
## 使用 Cube 距离公式: (|dq| + |dr| + |ds|) / 2
static func hex_distance(from: Vector2i, to: Vector2i) -> int:
	var diff := from - to
	return (absi(diff.x) + absi(diff.x + diff.y) + absi(diff.y)) / 2


## 计算六边形距离 (Cube 坐标)
static func hex_distance_cube(from: Vector3i, to: Vector3i) -> int:
	var diff := from - to
	return maxi(maxi(absi(diff.x), absi(diff.y)), absi(diff.z))


## 计算曼哈顿距离 (SQUARE/RECT)
## |dx| + |dy|
static func manhattan_distance(from: Vector2i, to: Vector2i) -> int:
	var diff := from - to
	return absi(diff.x) + absi(diff.y)


## 计算切比雪夫距离 (8方向移动)
## max(|dx|, |dy|)
static func chebyshev_distance(from: Vector2i, to: Vector2i) -> int:
	var diff := from - to
	return maxi(absi(diff.x), absi(diff.y))


## 根据网格类型计算距离
static func distance(from: Vector2i, to: Vector2i, grid_type: GridMapConfig.GridType) -> int:
	match grid_type:
		GridMapConfig.GridType.HEX:
			return hex_distance(from, to)
		GridMapConfig.GridType.RECT_SIX_DIR:
			# RECT_SIX_DIR 使用与 HEX 相同的 Cube 距离
			return hex_distance(from, to)
		GridMapConfig.GridType.SQUARE, GridMapConfig.GridType.RECT:
			return manhattan_distance(from, to)
	return 0


## 计算 Axial 坐标到原点的距离
static func hex_length(coord: Vector2i) -> int:
	return (absi(coord.x) + absi(coord.x + coord.y) + absi(coord.y)) / 2


## 计算 Cube 坐标到原点的距离
static func hex_length_cube(coord: Vector3i) -> int:
	return maxi(maxi(absi(coord.x), absi(coord.y)), absi(coord.z))


# ========== 邻居查询 ==========

## 获取指定坐标的所有邻居
## 根据网格类型返回不同数量的邻居
static func get_neighbors(coord: Vector2i, grid_type: GridMapConfig.GridType) -> Array[Vector2i]:
	match grid_type:
		GridMapConfig.GridType.HEX:
			return get_hex_neighbors(coord)
		GridMapConfig.GridType.RECT_SIX_DIR:
			return get_rect_six_dir_neighbors(coord)
		GridMapConfig.GridType.SQUARE, GridMapConfig.GridType.RECT:
			return get_square_neighbors(coord)
	return []


## 获取六边形邻居 (6 个)
static func get_hex_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in HEX_AXIAL_DIRECTIONS:
		result.append(coord + dir)
	return result


## 获取 RECT_SIX_DIR 邻居 (6 个，根据行奇偶性)
static func get_rect_six_dir_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var directions: Array[Vector2i]
	
	# 根据行的奇偶性选择方向数组
	if coord.y % 2 == 0:
		directions = RECT_SIX_DIR_EVEN
	else:
		directions = RECT_SIX_DIR_ODD
	
	for dir in directions:
		result.append(coord + dir)
	return result


## 获取正方形邻居 (4 个)
static func get_square_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in SQUARE_DIRECTIONS:
		result.append(coord + dir)
	return result


## 获取正方形 8 方向邻居 (包含对角)
static func get_square_neighbors_8(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in SQUARE_DIRECTIONS_8:
		result.append(coord + dir)
	return result


## 获取指定方向的六边形邻居 (Axial)
static func hex_neighbor(coord: Vector2i, direction: int) -> Vector2i:
	return coord + HEX_AXIAL_DIRECTIONS[direction % 6]


## 获取指定方向的六边形邻居 (Cube)
static func hex_neighbor_cube(coord: Vector3i, direction: int) -> Vector3i:
	return coord + HEX_CUBE_DIRECTIONS[direction % 6]


## 获取六边形对角邻居 (Axial)
static func get_hex_diagonal_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in HEX_AXIAL_DIAGONALS:
		result.append(coord + dir)
	return result


## 获取指定方向的六边形对角邻居 (Axial)
static func hex_diagonal_neighbor(coord: Vector2i, direction: int) -> Vector2i:
	return coord + HEX_AXIAL_DIAGONALS[direction % 6]


# ========== 六边形基础运算 ==========

## Axial 坐标相加
static func axial_add(a: Vector2i, b: Vector2i) -> Vector2i:
	return a + b


## Axial 坐标相减
static func axial_subtract(a: Vector2i, b: Vector2i) -> Vector2i:
	return a - b


## Axial 坐标缩放
static func axial_scale(coord: Vector2i, factor: int) -> Vector2i:
	return coord * factor


## Cube 坐标相加
static func cube_add(a: Vector3i, b: Vector3i) -> Vector3i:
	return a + b


## Cube 坐标相减
static func cube_subtract(a: Vector3i, b: Vector3i) -> Vector3i:
	return a - b


## Cube 坐标缩放
static func cube_scale(coord: Vector3i, factor: int) -> Vector3i:
	return coord * factor


# ========== 范围查询 ==========

## 获取指定范围内的所有六边形 (Axial)
## 返回距离 center <= radius 的所有坐标
static func hex_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	
	for q in range(-radius, radius + 1):
		var r1 := maxi(-radius, -q - radius)
		var r2 := mini(radius, -q + radius)
		for r in range(r1, r2 + 1):
			results.append(Vector2i(center.x + q, center.y + r))
	
	return results


## 获取指定范围内的所有六边形 (Cube)
static func hex_range_cube(center: Vector3i, radius: int) -> Array[Vector3i]:
	var results: Array[Vector3i] = []
	
	for q in range(-radius, radius + 1):
		var r1 := maxi(-radius, -q - radius)
		var r2 := mini(radius, -q + radius)
		for r in range(r1, r2 + 1):
			var s := -q - r
			results.append(Vector3i(center.x + q, center.y + r, center.z + s))
	
	return results


## 计算范围内六边形数量
## 公式: 3 * N * (N + 1) + 1
static func hex_range_count(radius: int) -> int:
	return 3 * radius * (radius + 1) + 1


## 两个范围的交集 (Axial)
static func hex_range_intersection(
	center1: Vector2i, radius1: int,
	center2: Vector2i, radius2: int
) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	
	# 计算边界约束
	var q_min := maxi(center1.x - radius1, center2.x - radius2)
	var q_max := mini(center1.x + radius1, center2.x + radius2)
	var r_min := maxi(center1.y - radius1, center2.y - radius2)
	var r_max := mini(center1.y + radius1, center2.y + radius2)
	
	for q in range(q_min, q_max + 1):
		for r in range(r_min, r_max + 1):
			var coord := Vector2i(q, r)
			if hex_distance(coord, center1) <= radius1 and \
			   hex_distance(coord, center2) <= radius2:
				results.append(coord)
	
	return results


# ========== 环 ==========

## 获取指定距离的环形 (Axial)
## 返回距离 center 恰好等于 radius 的所有坐标
static func hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	
	var results: Array[Vector2i] = []
	
	# 从起点开始 (center + radius * direction[4])
	var hex := center + axial_scale(HEX_AXIAL_DIRECTIONS[4], radius)
	
	for i in range(6):
		for j in range(radius):
			results.append(hex)
			hex = hex_neighbor(hex, i)
	
	return results


## 计算环上六边形数量
## 公式: 6 * N (N > 0), 1 (N = 0)
static func hex_ring_count(radius: int) -> int:
	if radius == 0:
		return 1
	return 6 * radius


# ========== 螺旋 ==========

## 获取螺旋形排列的所有六边形 (Axial)
## 从中心开始，按环逐层向外
static func hex_spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = [center]
	
	for k in range(1, radius + 1):
		results.append_array(hex_ring(center, k))
	
	return results


# ========== 线段 ==========

## 绘制从 a 到 b 的直线 (Axial)
## 包含两端点
static func hex_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var n := hex_distance(from, to)
	if n == 0:
		return [from]
	
	var results: Array[Vector2i] = []
	
	# 添加小偏移避免边界歧义
	var nudge := 1e-6
	var from_q := float(from.x) + nudge
	var from_r := float(from.y) + nudge
	var to_q := float(to.x)
	var to_r := float(to.y)
	
	for i in range(n + 1):
		var t := float(i) / float(n)
		var q := lerpf(from_q, to_q, t)
		var r := lerpf(from_r, to_r, t)
		results.append(CoordConverter.axial_round(q, r))
	
	return results


# ========== 旋转 ==========

## 绕原点顺时针旋转 60° (Axial)
static func axial_rotate_cw(coord: Vector2i) -> Vector2i:
	var cube := Vector3i(coord.x, coord.y, -coord.x - coord.y)
	var rotated := cube_rotate_cw(cube)
	return Vector2i(rotated.x, rotated.y)


## 绕原点逆时针旋转 60° (Axial)
static func axial_rotate_ccw(coord: Vector2i) -> Vector2i:
	var cube := Vector3i(coord.x, coord.y, -coord.x - coord.y)
	var rotated := cube_rotate_ccw(cube)
	return Vector2i(rotated.x, rotated.y)


## 绕原点顺时针旋转 60° (Cube)
## (q, r, s) -> (-r, -s, -q)
static func cube_rotate_cw(coord: Vector3i) -> Vector3i:
	return Vector3i(-coord.y, -coord.z, -coord.x)


## 绕原点逆时针旋转 60° (Cube)
## (q, r, s) -> (-s, -q, -r)
static func cube_rotate_ccw(coord: Vector3i) -> Vector3i:
	return Vector3i(-coord.z, -coord.x, -coord.y)


## 绕任意中心旋转 (Axial)
## rotations: 正数顺时针，负数逆时针，单位为 60°
static func axial_rotate_around(coord: Vector2i, center: Vector2i, rotations: int) -> Vector2i:
	# 平移到原点
	var vec := coord - center
	
	# 应用旋转
	var abs_rot := absi(rotations) % 6
	for i in range(abs_rot):
		if rotations > 0:
			vec = axial_rotate_cw(vec)
		else:
			vec = axial_rotate_ccw(vec)
	
	# 平移回去
	return vec + center


# ========== 反射 ==========

## 沿 q 轴反射 (交换 r 和 s)
static func cube_reflect_q(coord: Vector3i) -> Vector3i:
	return Vector3i(coord.x, coord.z, coord.y)


## 沿 r 轴反射 (交换 q 和 s)
static func cube_reflect_r(coord: Vector3i) -> Vector3i:
	return Vector3i(coord.z, coord.y, coord.x)


## 沿 s 轴反射 (交换 q 和 r)
static func cube_reflect_s(coord: Vector3i) -> Vector3i:
	return Vector3i(coord.y, coord.x, coord.z)


## 沿 q 轴反射 (Axial)
static func axial_reflect_q(coord: Vector2i) -> Vector2i:
	var cube := Vector3i(coord.x, coord.y, -coord.x - coord.y)
	var reflected := cube_reflect_q(cube)
	return Vector2i(reflected.x, reflected.y)


## 沿 r 轴反射 (Axial)
static func axial_reflect_r(coord: Vector2i) -> Vector2i:
	var cube := Vector3i(coord.x, coord.y, -coord.x - coord.y)
	var reflected := cube_reflect_r(cube)
	return Vector2i(reflected.x, reflected.y)


## 沿 s 轴反射 (Axial)
static func axial_reflect_s(coord: Vector2i) -> Vector2i:
	var cube := Vector3i(coord.x, coord.y, -coord.x - coord.y)
	var reflected := cube_reflect_s(cube)
	return Vector2i(reflected.x, reflected.y)
