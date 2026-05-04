## RtsVertexPathfinder - 短程绕避(visibility graph + A*) (M6 引入,M6a/b/c 完整)
##
## 0 A.D. `helpers/VertexPathfinder.cpp` (~1500 行 C++) 的 GDScript 复刻。在 [start, goal] 间
## 一个有限大小的 search box 内,把 OBB corner / 圆 AABB corner / 搜索框 4 角 / terrain 边界中点
## / virtual goal vertex 全收为 vertex 候选,跑 lazy visibility A* 找最短路径。
##
## 跟 LongPath 区别:
##   - LongPath = 全图 navcell A*,8 邻居,粒度 = 32 px navcell;路径形状是阶梯形
##   - VertexPath = visibility graph A*,任意角度直线段;路径形状贴 obstruction 边
##
## **9 大类边界 case 全实现**(spec data-structures §7.2):
##   - #1 search bounds toward goal shift / #2 range boundary edges / #3 virtual goal vertex /
##     #4 terrain edges / #5 lazy visibility / #6 best-so-far fallback / #7 moving unit square
##     proxy / #8 group filter / #9 tie-break order
##
## **M6 sub-phase 历史**:
##   - **M6a**: search bounds + range boundary + lazy visibility + 5 元组 deterministic
##   - **M6b**: virtual goal CIRCLE/SQUARE/INVERTED 几何 + terrain edges + best-so-far +
##     Liang-Barsky 精确化(替代 t-stepping)
##   - **M6c**: dynamic units (square proxy) + group filter + avoid_moving_units 开关 +
##     facade wire (compute_short_path_immediate API)
##
## **决策来源**:
##   - data-structures.md §7.2 (核心算法 9 大类边界 case)
##   - data-structures.md §12.3 (Determinism vertex 候选顺序 + A* 5 元组 key)
##   - interfaces.md §5 (公开 API)
##   - milestones/M6-vertex-pathfinder.md(完整 spec)
class_name RtsVertexPathfinder
extends RefCounted


# ========== 常量 ==========

## OBB corner 外推 buffer 倍数 — 把 corner 沿 (corner - center) 方向外推 (clearance × 此倍率),
## 让 vertex 在 OBB 外刚好够单位身体不撞。
##
## **1.0**:vertex 距 OBB corner 等于单位 clearance,segment_clear 验证时若擦边会被 buffer
## threshold 滤掉(`< buffer` 视为撞)。M6b Liang-Barsky 精确化后擦边判定无误差,1.0 安全
## 余地 = 1 IEEE ulp(实际无漏判);未来若 demo 出现擦边失败可调到 1.1。
const OBB_CORNER_OUTSET_FACTOR: float = 1.0

## A* heap key 浮点 → 整数粒度(0.1 px),用作 deterministic tie-break。
##
## 决策 L1 (spec §M6 决策):用 `int(round(x * 10))`,0.1 px 粒度足够区分实际 vertex 位置;
## 1 px 粒度容易让两个不同 vertex 同 key 走 seq tie-break,不稳定。
const COORD_INT_SCALE: int = 10


# ========== 字段 ==========

## NavcellGrid 引用(M6b terrain edges 用;M6a 暂只为统一 ctor 签名跟 M6b/c 兼容)。
var _grid: RtsNavcellGrid = null


# ========== 初始化 ==========

func _init(grid: RtsNavcellGrid) -> void:
	Log.assert_crash(grid != null, "RtsVertexPathfinder", "_init: grid is null")
	_grid = grid


# ========== 公开 API ==========

## 同步寻路:跑 visibility graph A* 找 start → goal 的短路径。
##
## **空 path 语义**:
##   - start ≈ virtual_goal:返回单 waypoint = virtual_goal(same-point 兜底)
##   - 找不到完整可见路径 + best-so-far 也没改善 (best_idx == start_idx):返回空 path,caller 用
##     `path.is_empty()` 判定 stuck;否则返回 best-so-far reconstruct(让 unit 至少朝 goal 走一段)
##
## **Determinism (§12.3)**:
##   - vertex 候选顺序:[start, virtual_goal, OBB corners(按 obstr.tag 升序 × get_corners() 4 角),
##     unit AABB corners(按 obstr.tag 升序 × +x+y/+x-y/-x-y/-x+y),search bounds TL/TR/BL/BR,
##     terrain edges (j, i) 字典序]
##   - A* heap key 5 元组:(f, h, vx_int, vy_int, seq) lex 比较;6th 元素 vertex_idx 仅查找用
func compute_short_path_immediate(req: RtsShortPathRequest, obstr_mgr: RtsObstructionManager) -> RtsWaypointPath:
	Log.assert_crash(req != null, "RtsVertexPathfinder", "compute_short_path_immediate: req is null")
	Log.assert_crash(req.goal != null, "RtsVertexPathfinder", "compute_short_path_immediate: req.goal is null")
	Log.assert_crash(obstr_mgr != null, "RtsVertexPathfinder", "compute_short_path_immediate: obstr_mgr is null")

	# WHY: virtual goal 是 goal 几何上离 start 最近的边界点(M6b detail #3);start ≈ virtual_goal
	# 兜底用 virtual_goal 而非 goal.center,让 caller 拿到一致语义(POINT goal 仍走 goal.center)。
	var virtual_goal: Vector2 = _compute_virtual_goal(req)
	if req.start.distance_squared_to(virtual_goal) < 1.0:
		var same := RtsWaypointPath.new()
		same.push_back(virtual_goal)
		return same

	var bounds: Rect2 = _compute_search_bounds(req.start, virtual_goal, req.range_px)

	var bounds_center: Vector2 = bounds.position + bounds.size * 0.5
	var bounds_circumradius: float = bounds.size.length() * 0.5
	var nearby: Array = obstr_mgr.get_obstructions_in_range(bounds_center, bounds_circumradius)

	# Filter (M6c detail #8 group filter + #3 avoid_moving_units 开关):
	# - control_group != "" + obstr.control_group / control_group_2 任一匹配 → skip(同 group 不互挡)
	# - avoid_moving_units == false + unit.flags & MOVING → skip(让"挤过"队伍)
	# WHY: nearby 按 tag 升序 (§12.4),filter 不破坏顺序 → statics / units 维持升序 (§12.3)
	var statics: Array = []
	var units: Array = []
	var has_group_filter: bool = req.control_group != ""
	for s in nearby:
		if has_group_filter:
			if s.control_group == req.control_group:
				continue
			if s is RtsObstructionShapeStatic and (s as RtsObstructionShapeStatic).control_group_2 == req.control_group:
				continue
		if s is RtsObstructionShapeStatic:
			statics.append(s)
		elif s is RtsObstructionShapeUnit:
			# WHY: avoid_moving_units == false 让 caller 选"挤过队伍",MOVING flag 单位不算障碍
			if not req.avoid_moving_units and (s.flags & RtsObstructionFlags.MOVING) != 0:
				continue
			units.append(s)

	# 顺序契约 (§12.3): start, virtual_goal, OBB corners (statics 升序 × get_corners() 0..3),
	# unit AABB corners (units 升序 × 4 角 +x+y → +x-y → -x-y → -x+y),
	# bounds TL/TR/BL/BR, terrain edges (M6b cell (i,j) 字典序)
	var vertices: Array[Vector2] = []
	vertices.append(req.start)
	var start_idx: int = 0
	vertices.append(virtual_goal)
	var goal_idx: int = 1

	for s in statics:
		var obb := s as RtsObstructionShapeStatic
		var corners: Array[Vector2] = obb.get_corners()
		var outset: float = req.clearance * OBB_CORNER_OUTSET_FACTOR
		for c in corners:
			var dir: Vector2 = (c - obb.center).normalized()
			vertices.append(c + dir * outset)

	# Moving unit square proxy (M6c detail #7): 圆形 obstruction 在 visibility graph 中近似 AABB
	# 4 corner(0 A.D. 简化避免切线几何 bug);visibility check 时 segment_clear 仍当圆处理
	# (RtsLineOfSight._segment_to_point_dist + clearance + buffer threshold)。
	for s in units:
		var u_shape := s as RtsObstructionShapeUnit
		var r: float = u_shape.clearance + req.clearance
		vertices.append(u_shape.center + Vector2(r, r))
		vertices.append(u_shape.center + Vector2(r, -r))
		vertices.append(u_shape.center + Vector2(-r, -r))
		vertices.append(u_shape.center + Vector2(-r, r))

	# WHY: bounds 4 角作 range-boundary vertex,让 A* 能"沿 search box 边缘绕过 OBB" (detail #2);
	# 没这层时 search box 内 OBB 完全堵住直线 + 无可见 vertex 时 A* 直接 return empty。
	var br: Rect2 = bounds
	vertices.append(Vector2(br.position.x, br.position.y))
	vertices.append(Vector2(br.position.x + br.size.x, br.position.y))
	vertices.append(Vector2(br.position.x, br.position.y + br.size.y))
	vertices.append(br.position + br.size)

	# Terrain edges (detail #4): bounds 内 grid 上 passable / impassable 邻居对中点作 vertex
	_add_terrain_vertices(vertices, bounds, req.pass_mask)

	# A* obstacles = statics + units (RtsLineOfSight.segment_clear 双类型 dispatch:Static 用 OBB
	# 距离;Unit 用 segment-to-point 距离;buffer = req.clearance,unit 自己 clearance 在 segment_clear 内累加)
	var obstacles: Array = []
	obstacles.append_array(statics)
	obstacles.append_array(units)
	return _astar_lazy_visibility(vertices, start_idx, goal_idx, obstacles, req.clearance)


# ========== 内部:Terrain edges (detail #4) ==========

## 沿 search bounds 内 grid 边界扫,passable / impassable 邻居对(右邻 / 下邻)的中点作 vertex。
##
## **顺序契约**(§12.3):内层按 (j, i) 字典序遍历;每 cell 先加东邻 vertex 后加南邻 vertex。
## **origin-aware**:用 grid.world_to_navcell_i/j 而非硬编码 floor div(NavcellGrid.set_origin_world
## 偏移生效)。
##
## **M6b 用例**:水陆交界 / 不可走地形边界 — 让 A* 沿这些"地形线"绕路。当前 demo 没水,实际启用
## 仅 grid 边界紧贴 obstruction inflate 区时产生 vertex(decision L2 default A:M6b 启用为后续 M9
## 加水时 wiring 通,无 perf 代价 — 仅 search bounds 内扫 ~50×50 = 2500 cells)。
func _add_terrain_vertices(vertices: Array[Vector2], bounds: Rect2, pass_mask: int) -> void:
	var i0: int = _grid.world_to_navcell_i(bounds.position.x)
	var i1: int = _grid.world_to_navcell_i(bounds.position.x + bounds.size.x)
	var j0: int = _grid.world_to_navcell_j(bounds.position.y)
	var j1: int = _grid.world_to_navcell_j(bounds.position.y + bounds.size.y)
	var w: int = _grid.width()
	var h: int = _grid.height()
	i0 = maxi(i0, 0)
	i1 = mini(i1, w - 1)
	j0 = maxi(j0, 0)
	j1 = mini(j1, h - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var here_pass: bool = _grid.is_passable(i, j, pass_mask)
			if i + 1 <= i1:
				var east_pass: bool = _grid.is_passable(i + 1, j, pass_mask)
				if here_pass != east_pass:
					vertices.append((_grid.navcell_center_world(i, j) + _grid.navcell_center_world(i + 1, j)) * 0.5)
			if j + 1 <= j1:
				var south_pass: bool = _grid.is_passable(i, j + 1, pass_mask)
				if here_pass != south_pass:
					vertices.append((_grid.navcell_center_world(i, j) + _grid.navcell_center_world(i, j + 1)) * 0.5)


# ========== 内部:Virtual goal (detail #3) ==========

## POINT goal → goal.center;CIRCLE/SQUARE/INVERTED_* → goal 边界离 start 最近点。
##
## **M6b 简化**:不做 passable check,直接用 goal.nearest_point_on_goal(req.start) 几何 nearest。
## passable 兜底由 best-so-far fallback (M6b detail #6) 间接处理 — A* 找不到就返 best 而非空。
func _compute_virtual_goal(req: RtsShortPathRequest) -> Vector2:
	if req.goal.type == RtsPathGoal.Type.POINT:
		return req.goal.center
	return req.goal.nearest_point_on_goal(req.start)


# ========== 内部:Search bounds 计算 (detail #1) ==========

## 计算 search bounds:中心 = (start, goal) 中点 + 沿 toward_goal 方向偏移一段距离;
## size = (range, range) 正方形。
##
## **偏移量**(0 A.D. SHORT_PATH_GOAL_BIAS): 沿 toward_goal 方向偏 `min(toward_dist/6, range/4)`,
## 让 search box 朝 goal 倾斜,避免反向收 100 个无用 obstruction。
##
## **极端 case**:start ≈ goal 时 toward_goal 长度接近 0,偏移量 0 → bounds 中心 ≈ start (== goal),
## 此时上层 same-point 兜底已 return,不进此函数。
func _compute_search_bounds(start: Vector2, goal_center: Vector2, range_px: float) -> Rect2:
	var mid: Vector2 = start.lerp(goal_center, 0.5)
	var toward_goal: Vector2 = goal_center - start
	var toward_dist: float = toward_goal.length()
	var bias: float = minf(toward_dist / 6.0, range_px / 4.0)
	var biased_center: Vector2 = mid
	if toward_dist > 0.0001:
		biased_center = mid + toward_goal / toward_dist * bias
	var size: Vector2 = Vector2(range_px, range_px)
	return Rect2(biased_center - size * 0.5, size)


# ========== 内部:A* lazy visibility ==========

## Lazy visibility A* — 跟 LongPath 同 5 元组 lex compare,但 (i, j) 换成 (vx_int, vy_int)
## (浮点 vertex 坐标 × COORD_INT_SCALE 取整)。 expand 节点时才测试它跟其他 vertex 的可见性。
##
## **Heap key 6 元组**:`[f, h, vx_int, vy_int, seq, vertex_idx]`(RtsPathfinderHeap.key_less 仅
## 比前 5 项;`key[5]` = vertex_idx 是 caller payload,从 open 弹出时用作 lookup,不进 lex compare)。
##
## **Lazy decrease-key**:同 vertex 找到更短路径时不删 open list 旧 entry,直接 push 新 entry +
## 更新 g_score / came_from;pop 时 `closed.has(cur_idx)` 跳过陈旧重复(标准技巧避开 hash → heap-index 反查)。
##
## **Best-so-far fallback (M6b detail #6)**:open 耗尽未达 goal_idx 时,返回扩展过的 vertices 中
## **离 goal 最近**那个的 reconstruct 路径(让 unit 至少朝 goal 方向走一段;M7 m_FollowKnownImperfectPathCountdown
## 触发 retry)。同距离时按 expansion 顺序保 deterministic(`d < best_dist` 严格 <,不是 ≤)。
func _astar_lazy_visibility(
	vertices: Array[Vector2],
	start_idx: int,
	goal_idx: int,
	statics: Array,
	clearance: float,
) -> RtsWaypointPath:
	var open_keys: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var insertion_seq: int = 0

	g_score[start_idx] = 0.0
	var start_pos: Vector2 = vertices[start_idx]
	var goal_pos: Vector2 = vertices[goal_idx]
	var h0: float = start_pos.distance_to(goal_pos)
	open_keys.append([h0, h0, _coord_int(start_pos.x), _coord_int(start_pos.y), insertion_seq, start_idx])
	insertion_seq += 1

	# Best-so-far 跟踪:start 自身是初始候选(距离 = h0)
	var best_idx: int = start_idx
	var best_dist: float = h0

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var cur_idx: int = key[5]
		if closed.has(cur_idx):
			continue
		closed[cur_idx] = true

		if cur_idx == goal_idx:
			return _reconstruct(vertices, came_from, start_idx, goal_idx)

		var cur_pos: Vector2 = vertices[cur_idx]
		var cur_g: float = g_score[cur_idx]

		for nb_idx in range(vertices.size()):
			if nb_idx == cur_idx or closed.has(nb_idx):
				continue
			var nb_pos: Vector2 = vertices[nb_idx]
			if not RtsLineOfSight.segment_clear(cur_pos, nb_pos, statics, clearance):
				continue
			var step_cost: float = cur_pos.distance_to(nb_pos)
			var new_g: float = cur_g + step_cost
			if g_score.has(nb_idx) and new_g >= g_score[nb_idx]:
				continue
			g_score[nb_idx] = new_g
			came_from[nb_idx] = cur_idx
			var nb_h: float = nb_pos.distance_to(goal_pos)
			# WHY: 严格 < 让"等距"按 expansion 顺序保 deterministic
			if nb_h < best_dist:
				best_dist = nb_h
				best_idx = nb_idx
			var f: float = new_g + nb_h
			RtsPathfinderHeap.insert(open_keys, [f, nb_h, _coord_int(nb_pos.x), _coord_int(nb_pos.y), insertion_seq, nb_idx])
			insertion_seq += 1

	# 找不到完整路径 → best-so-far(M6b detail #6);best_idx == start_idx 时返空(start 自身是 best,
	# 没向 goal 进展过 — 通常意味无任何邻居可见,真正死锁,空 path 保留 caller fallback 信号)
	if best_idx == start_idx:
		return RtsWaypointPath.new()
	return _reconstruct(vertices, came_from, start_idx, best_idx)


## 浮点坐标 → 0.1 px 粒度整数(deterministic tie-break key)。
static func _coord_int(x: float) -> int:
	return int(round(x * COORD_INT_SCALE))


## Reconstruct 反向存储 RtsWaypointPath:从 goal 倒推 came_from 链 → trail 然后 push goal..start
## (跳 start 自身,因单位已在 start)。
##
## 不变量:`waypoints[0] = goal`、`waypoints[size-1] = next-step`(同 LongPath._reconstruct)。
func _reconstruct(
	vertices: Array[Vector2],
	came_from: Dictionary,
	start_idx: int,
	goal_idx: int,
) -> RtsWaypointPath:
	var path := RtsWaypointPath.new()
	var trail: Array[int] = [goal_idx]
	var cur: int = goal_idx
	while cur != start_idx:
		if not came_from.has(cur):
			# 重建失败(理论不该发生 — A* 找到 goal 必有 came_from 链)
			return RtsWaypointPath.new()
		cur = came_from[cur]
		trail.append(cur)
	# trail = [goal, ..., start];push trail[0..N-2] 跳 start
	for k in range(trail.size() - 1):
		path.push_back(vertices[trail[k]])
	return path
