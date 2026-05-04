## RtsLineOfSight - 线段可见性 / grid raycast helper (M6 引入)
##
## 0 A.D. `helpers/VertexPathfinder.cpp` 内部 segment clearance 测试 + `helpers/Pathfinding.cpp`
## `CheckLineMovement` 的 GDScript 复刻。给 VertexPathfinder lazy visibility A* 用 (`segment_clear`)
## 与 motion path post-processing (`check_line_movement`)。
##
## **API**:
##   - `segment_clear(a, b, shapes, buffer) -> bool` — 线段 a→b 距任何 shape 的最近距离
##     是否 ≥ shape.clearance + buffer (Unit 圆) 或 buffer (Static OBB)
##   - `check_line_movement(grid, a, b, pass_mask) -> bool` — Bresenham raycast,沿 navcell 步进
##     直到撞到 impassable cell 返 false
##
## **实现策略(M6b 精确化)**:
##   - segment vs OBB 距离 = OBB local 坐标变换后 segment vs AABB 精确公式
##     (Liang-Barsky 测 segment-AABB 相交 + 不相交时 endpoint-to-AABB 与 corner-to-segment 取 min)
##   - segment vs Unit (圆) 用解析公式 (segment-to-point 距离 ≤ unit.clearance + buffer)
##   - **enclose-radius 早出**:三角不等式下界 ≥ buffer 时直接 skip 精确算 (典型 demo ~80% 调用走早出)
##
## **决策来源**:
##   - data-structures.md §7.3 (API 签名)
##   - milestones/M6-vertex-pathfinder.md §M6a.4 (实现简化策略)
##   - 0 A.D. helpers/VertexPathfinder.cpp 内部 LineOfSight 模块
class_name RtsLineOfSight
extends RefCounted


# ========== 公开 API ==========

## 线段 a → b 距任何 shape 的距离是否足够远 (≥ buffer / Unit ≥ clearance + buffer)?
##
## - Unit 圆:dist(segment, center) ≥ clearance + buffer 才视为 clear (严格 < 视为撞)
## - Static OBB:dist(segment, OBB) ≥ buffer 才视为 clear
##
## 任一 shape 不通过 → 返 false (撞);全部通过 → 返 true。
##
## **buffer 含义**:caller 通常传单位的避让半径 (clearance) — segment 是 unit 中心移动轨迹,
## buffer = 单位半径,确保单位 body 不撞 shape。M6a 阶段 vertex pathfinder 传 req.clearance。
static func segment_clear(a: Vector2, b: Vector2, shapes: Array, buffer: float) -> bool:
	for s in shapes:
		if s is RtsObstructionShapeUnit:
			var u_shape := s as RtsObstructionShapeUnit
			var threshold: float = u_shape.clearance + buffer
			if _segment_to_point_dist(a, b, u_shape.center) < threshold:
				return false
		elif s is RtsObstructionShapeStatic:
			if _segment_to_obb_dist(a, b, s as RtsObstructionShapeStatic, buffer) < buffer:
				return false
	return true


## Bresenham raycast on grid:沿 a → b 步进 navcell,任一 impassable 返 false。
##
## 起点 navcell impassable 也视为不通(跟 LongPathfinder 不同)。caller 应保证 start cell passable。
##
## **用例**:M7 motion 走完 short path 后做"路径压缩"(冗余 waypoint 删除)— 若中间两 waypoint
## 间 grid 直线无 impassable cell,可跳过中间 waypoint 直走。
static func check_line_movement(grid: RtsNavcellGrid, a: Vector2, b: Vector2, pass_mask: int) -> bool:
	var ca: Vector2i = grid.nearest_navcell(a)
	var cb: Vector2i = grid.nearest_navcell(b)
	var di: int = absi(cb.x - ca.x)
	var dj: int = absi(cb.y - ca.y)
	var sx: int = 1 if cb.x >= ca.x else -1
	var sy: int = 1 if cb.y >= ca.y else -1
	var err: int = di - dj
	var x: int = ca.x
	var y: int = ca.y
	while true:
		if not grid.is_passable(x, y, pass_mask):
			return false
		if x == cb.x and y == cb.y:
			return true
		var e2: int = 2 * err
		if e2 > -dj:
			err -= dj
			x += sx
		if e2 < di:
			err += di
			y += sy
	return true


# ========== 内部 helper ==========

## 线段 a → b 上离点 p 最近距离。
##
## 算法:把 p 投影到 ab 直线上,clamp t 到 [0,1] (确保投影点在 segment 上,不超出端点),
## 然后计算 p 距投影点距离。
static func _segment_to_point_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var nearest: Vector2 = a + ab * t
	return p.distance_to(nearest)


## 线段 a → b 距 OBB 的最近距离。
##
## **M6a 实现**:
##   1. **Enclose-radius 早出**(efficiency 大赢家): segment 距 OBB center 距离 ≥ enclose_radius + buffer
##      → 距离真值下界 ≥ buffer → caller 一定视为 clear,无需进 t-stepping(t-stepping 占 inner-loop
##      最大开销;实际 demo ~80% 调用都被早出过滤掉)。
##   2. **Axis-aligned fast-path**: rotation_rad ≈ 0 时跳 cos/sin/dot,直接 segment - center 即 local 坐标。
##   3. **T-stepping 精确算**: OBB 转 local 坐标系后用 segment-vs-AABB 距离公式 (100 sample 取 min)。
##      M6b 末换 Liang-Barsky / SAT 精确版。
##
## **buffer 参数**用于早出阈值;函数返回值仍是真距离(t-stepping)或安全下界(enclose 早出)。
static func _segment_to_obb_dist(a: Vector2, b: Vector2, obb: RtsObstructionShapeStatic, buffer: float) -> float:
	var enclose_radius: float = sqrt(obb.width * obb.width + obb.height * obb.height) * 0.5
	var center_dist: float = _segment_to_point_dist(a, b, obb.center)
	# WHY: 三角不等式 obb_dist ≥ center_dist - enclose_radius;下界 ≥ buffer 时 caller 必判 clear。
	if center_dist >= enclose_radius + buffer:
		return center_dist - enclose_radius

	var la: Vector2
	var lb: Vector2
	# WHY: rotation=0 是当前 demo 全部 building 的常态,跳 cos/sin/dot ~30% per-call。
	if absf(obb.rotation_rad) < 1e-6:
		la = a - obb.center
		lb = b - obb.center
	else:
		var u: Vector2 = Vector2(cos(obb.rotation_rad), sin(obb.rotation_rad))
		var v: Vector2 = Vector2(-sin(obb.rotation_rad), cos(obb.rotation_rad))
		la = Vector2((a - obb.center).dot(u), (a - obb.center).dot(v))
		lb = Vector2((b - obb.center).dot(u), (b - obb.center).dot(v))
	var hw: float = obb.width * 0.5
	var hh: float = obb.height * 0.5
	return _segment_to_aabb_dist(la, lb, hw, hh)


## 线段 a → b 距以原点为中心、半宽 hw / 半高 hh 的 AABB 的最近距离(M6b 精确版)。
##
## **算法**:
##   1. 端点 a 或 b 在 AABB 内 → 距离 0
##   2. Liang-Barsky 测 segment 跟 AABB 相交 → 距离 0
##   3. 否则 nearest = min(端点 a 距 AABB, 端点 b 距 AABB, AABB 4 corner 距 segment)
##
## **精度**:1 IEEE ulp(完全解析),取代 M6a 100-sample t-stepping(误差 ≤ 0.5 px)。caller buffer
## (典型 12-14 px) 远大于 ulp,行为不变;t-stepping 漏判 corner case 此版彻底消除。
static func _segment_to_aabb_dist(a: Vector2, b: Vector2, hw: float, hh: float) -> float:
	if absf(a.x) <= hw and absf(a.y) <= hh:
		return 0.0
	if absf(b.x) <= hw and absf(b.y) <= hh:
		return 0.0

	var t_min: float = 0.0
	var t_max: float = 1.0
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	# WHY: 用 absf > 1e-9 而非 != 0:浮点段几乎平行轴时 |dx| 极小但非 0,inv_dx 会爆 → 无穷 t1/t2
	# 让 Liang-Barsky 误判;阈值跟 buffer 数量级 (~12px) 相比绝对小,不影响 ≤ 1 ulp 精度。
	if absf(dx) > 1e-9:
		var inv_dx: float = 1.0 / dx
		var tx1: float = (-hw - a.x) * inv_dx
		var tx2: float = (hw - a.x) * inv_dx
		if tx1 > tx2:
			var tmp_x: float = tx1
			tx1 = tx2
			tx2 = tmp_x
		t_min = maxf(t_min, tx1)
		t_max = minf(t_max, tx2)
	elif a.x < -hw or a.x > hw:
		return _segment_aabb_no_intersect_dist(a, b, hw, hh)

	if absf(dy) > 1e-9:
		var inv_dy: float = 1.0 / dy
		var ty1: float = (-hh - a.y) * inv_dy
		var ty2: float = (hh - a.y) * inv_dy
		if ty1 > ty2:
			var tmp_y: float = ty1
			ty1 = ty2
			ty2 = tmp_y
		t_min = maxf(t_min, ty1)
		t_max = minf(t_max, ty2)
	elif a.y < -hh or a.y > hh:
		return _segment_aabb_no_intersect_dist(a, b, hw, hh)

	if t_min <= t_max:
		return 0.0

	return _segment_aabb_no_intersect_dist(a, b, hw, hh)


## Segment 跟 AABB 不重叠时的最近距离 = min(端点 a/b 距 AABB, AABB 4 corner 距 segment)。
static func _segment_aabb_no_intersect_dist(a: Vector2, b: Vector2, hw: float, hh: float) -> float:
	var dxa: float = maxf(absf(a.x) - hw, 0.0)
	var dya: float = maxf(absf(a.y) - hh, 0.0)
	var min_dist: float = sqrt(dxa * dxa + dya * dya)

	var dxb: float = maxf(absf(b.x) - hw, 0.0)
	var dyb: float = maxf(absf(b.y) - hh, 0.0)
	min_dist = minf(min_dist, sqrt(dxb * dxb + dyb * dyb))

	# AABB 4 corner 距 segment(corner 顺序固定 deterministic)
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(-hw, -hh)))
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(hw, -hh)))
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(hw, hh)))
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(-hw, hh)))
	return min_dist
