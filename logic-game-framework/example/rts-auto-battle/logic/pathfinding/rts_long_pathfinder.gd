## RtsLongPathfinder - 朴素 A* on RtsNavcellGrid (M5)
## Archived fixture-only implementation. Production pathfinding goes through
## `RtsPathfinderFacade` and delegates to `addons/sim-nav-map`; new navigation
## work belongs in `sim-nav-map` or an adapter.
##
## 0 A.D. `LongPathfinder` (helpers/LongPathfinder.h/cpp) 的 GDScript 朴素复刻。**D6 决策**:
## 不做 JPS + JumpPointCache,纯朴素 A*,100 单位 / 1024² grid 规模够用。M5 末若 perf 不够
## 再考虑 GDExtension or JPS 优化。
##
## **核心算法** (data-structures §6 + spec §M5.2):
##   - Open list = SortedArray of 5 元组 `[f, h, i, j, insertion_seq]`,bsearch + insert
##     保严格升序;弹出 = `remove_at(0)` 是 O(N) 但 GDScript 没真 priority queue,
##     朴素 demo 规模够用(K1 决策)
##   - PathCost 整数(`COST_HV = 65536`, `COST_DIAG = 92682 ≈ 65536 × √2`),不引入浮点
##     避免跨平台 IEEE 漂
##   - 8 邻居顺序固定 deterministic:HV 4 个 (+x, -x, +y, -y) → diag 4 个 (++, +-, -+, --)
##   - Reconstruct 反向存储到 RtsWaypointPath: `waypoints[0] = goal`, `waypoints[size-1] = next step`
##   - `_pack_cell(v)` = `v.x * 65536 + v.y`(K2:固定 packing 不依赖 grid 尺寸);grid < 65536
##     时 collision-free,assert 在 _init 防未来扩 16K² grid 时 silent collision
##
## **5 元组 lex compare 严格保 deterministic** (data-structures §12.1):
##   1. f: 总代价(主排序)
##   2. h: 启发(f 相同时 h 小优先 — 离 goal 更近的先扩)
##   3. i, j: navcell 坐标 — h 也相同时按 (i, j) 字典序保 deterministic
##   4. insertion_seq: 单调递增,所有上面字段相同时(罕见)按插入序保最严格 deterministic
##
## **Octile heuristic** (4-向 + 对角): `h = max(di, dj) - min(di, dj) 个 HV + min(di, dj) 个 DIAG`,
## 跟 step_cost (HV / DIAG) 一致 — admissible + consistent。
##
## **决策来源**:
##   - data-structures.md §6 (LongPath data class + integer cost + reverse-stored path)
##   - milestones/M5-long-pathfinder.md §M5.2 (5 元组 lex compare + reconstruct 流程)
##   - data-structures.md §12.1 (Determinism heap key 严格)
##   - 0 A.D. helpers/LongPathfinder.h:120-180 公开 API
class_name RtsLongPathfinder
extends RefCounted


# ========== 常量 ==========

## 整数 cost,水平 / 垂直走 1 navcell。
const COST_HV: int = 65536

## 整数 cost,对角走 1 navcell ≈ HV × √2(int round)。
const COST_DIAG: int = 92682

## `_pack_cell` 限制:每 grid 维度必须 < 65536 否则 silent collision。
const _PACK_LIMIT: int = 65536

## 8 邻居偏移(HV 4 个先,对角 4 个后);文件级 const 避免内层 alloc。
const _NEIGHBOR_DI: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const _NEIGHBOR_DJ: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const _NEIGHBOR_IS_DIAG: Array[bool] = [false, false, false, false, true, true, true, true]


# ========== 字段 ==========

## NavcellGrid 引用;facade 注入;调方修改 grid 后无需重 init(下次 compute_path 自然反映)。
var _grid: RtsNavcellGrid = null


# ========== 初始化 ==========

func _init(grid: RtsNavcellGrid) -> void:
	Log.assert_crash(grid != null, "RtsLongPathfinder", "_init: grid is null")
	# R5 反馈: _pack_cell 假设 grid < 65536, 显式 assert 让未来扩 16K² grid 时立即 crash
	# 而非 silent collision。
	Log.assert_crash(
		grid.width() < _PACK_LIMIT and grid.height() < _PACK_LIMIT,
		"RtsLongPathfinder",
		"grid must be < %d per side (current: %d × %d)" % [_PACK_LIMIT, grid.width(), grid.height()],
	)
	_grid = grid


# ========== 公开 API ==========

## 同步寻路:start (world) → goal (POINT) 走 8-邻居 A*,返回 RtsWaypointPath(反向存储)。
##
## **goal 必须 POINT** — facade 调 `make_goal_reachable` 已 canonicalize 到 navcell 中心 POINT;
## 直接传 CIRCLE/SQUARE 会 assert_crash(M6 VertexPath 才支持非 POINT goal)。
##
## 起点 / 终点同 navcell → 返回单 waypoint = goal.center(空 path 的 fail-safe 由调方
## 用 `path.is_empty()` 区分:LongPath 找不到时返回空)。
##
## 起点 navcell impassable → A* 仍从 start_cell 出发(0 A.D. 实现 start always allowed,
## 仅 neighbor 查 is_passable);终点 navcell impassable → 返回空 path(facade 应先调
## make_goal_reachable canonicalize 避免此情况)。
func compute_path_immediate(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> RtsWaypointPath:
	Log.assert_crash(goal != null, "RtsLongPathfinder", "compute_path_immediate: goal is null")
	Log.assert_crash(
		goal.type == RtsPathGoal.Type.POINT,
		"RtsLongPathfinder",
		"compute_path_immediate: goal must be POINT (use facade.make_goal_reachable to canonicalize), got type=%d" % goal.type,
	)

	var start_cell: Vector2i = _grid.nearest_navcell(start_world)
	var goal_cell: Vector2i = _grid.nearest_navcell(goal.center)

	if start_cell == goal_cell:
		var path := RtsWaypointPath.new()
		path.push_back(goal.center)
		return path

	# **Direct-path fallback** (跟老 RtsPathfinding.find_path 一致行为):
	# goal 落 impassable navcell(M3 clearance inflate 区 / building footprint 内)→ A* 找不到 path
	# → 返回单 waypoint = goal.center,让 callsite "直接朝目标走过去"。
	#
	# 用例:harvest/attack/drop 走 facade.compute_path_direct 不过 canonicalize 时,target=actor
	# 中心可能落 inflate 区 → A* 找不到 path → 直接 path 让 unit 走到 in-range 距离,distance check
	# (HARVEST_RADIUS / attack_range / DROP_OFF_RADIUS) 决定 in-range 行为。
	#
	# 走过 canonicalize 的 callsite(玩家 click)goal 已 mutate 到 passable navcell 中心,这个分支
	# 不会触发(走正常 A*)。
	if not _grid.is_passable(goal_cell.x, goal_cell.y, pass_mask):
		var direct := RtsWaypointPath.new()
		direct.push_back(goal.center)
		return direct

	return _astar(start_cell, goal_cell, pass_mask)


# ========== 内部:A* ==========

## 朴素 A* on 8-邻居 grid。Open list = SortedArray 5 元组 lex 升序;closed = Dict[packed, true]。
##
## 5 元组比较保 deterministic:同 f → 比 h → 比 (i, j) 字典序 → 比 insertion_seq。
func _astar(start: Vector2i, goal: Vector2i, pass_mask: int) -> RtsWaypointPath:
	var open_keys: Array = []                  # SortedArray of 5-元组 [f, h, i, j, seq]
	var came_from: Dictionary = {}             # packed_cell → packed_parent
	var g_score: Dictionary = {}               # packed_cell → int g
	var closed: Dictionary = {}                # packed_cell → true
	var insertion_seq: int = 0

	var start_pack: int = _pack_cell(start)
	var goal_pack: int = _pack_cell(goal)
	g_score[start_pack] = 0

	var h0: int = _octile(start, goal)
	open_keys.append([h0, h0, start.x, start.y, insertion_seq])
	insertion_seq += 1

	var w: int = _grid.width()
	var h: int = _grid.height()

	while not open_keys.is_empty():
		var key: Array = open_keys[0]
		open_keys.remove_at(0)
		var cur_i: int = key[2]
		var cur_j: int = key[3]
		var cur_pack: int = _pack_cell(Vector2i(cur_i, cur_j))
		if closed.has(cur_pack):
			continue
		closed[cur_pack] = true

		if cur_pack == goal_pack:
			return _reconstruct(came_from, start_pack, goal_pack)

		var cur_g: int = g_score[cur_pack]
		for d in range(8):
			var nb_i: int = cur_i + _NEIGHBOR_DI[d]
			var nb_j: int = cur_j + _NEIGHBOR_DJ[d]
			if nb_i < 0 or nb_i >= w or nb_j < 0 or nb_j >= h:
				continue
			if not _grid.is_passable(nb_i, nb_j, pass_mask):
				continue
			var nb_pack: int = _pack_cell(Vector2i(nb_i, nb_j))
			if closed.has(nb_pack):
				continue
			var step_cost: int = COST_DIAG if _NEIGHBOR_IS_DIAG[d] else COST_HV
			var new_g: int = cur_g + step_cost
			if g_score.has(nb_pack) and new_g >= g_score[nb_pack]:
				continue
			g_score[nb_pack] = new_g
			came_from[nb_pack] = cur_pack
			var nb_h: int = _octile(Vector2i(nb_i, nb_j), goal)
			var f: int = new_g + nb_h
			RtsPathfinderHeap.insert(open_keys, [f, nb_h, nb_i, nb_j, insertion_seq])
			insertion_seq += 1

	# Open list 耗尽,找不到路径
	return RtsWaypointPath.new()


## Octile heuristic = `(max(di,dj) - min(di,dj)) * COST_HV + min(di,dj) * COST_DIAG`。
## 8-邻居 grid 的 admissible + consistent heuristic;跟 step_cost 同尺度。
func _octile(a: Vector2i, b: Vector2i) -> int:
	var di: int = absi(b.x - a.x)
	var dj: int = absi(b.y - a.y)
	var diag: int = mini(di, dj)
	var hv: int = maxi(di, dj) - diag
	return hv * COST_HV + diag * COST_DIAG


## 16-bit pack:`v.x * 65536 + v.y`。grid < 65536 时 collision-free(_init assert)。
func _pack_cell(v: Vector2i) -> int:
	return v.x * _PACK_LIMIT + v.y


## 反向存储 reconstruct:从 goal 追溯 parent → start,把 trail[0..N-2](跳 start)按顺序
## push_back → waypoints[0] = goal, waypoints[size-1] = next step from start。
##
## **不变量**:`waypoints.size() = trail.size() - 1`(start cell 不进 path,单位已在那)。
func _reconstruct(came_from: Dictionary, start_pack: int, goal_pack: int) -> RtsWaypointPath:
	var path := RtsWaypointPath.new()
	# Trail 从 goal 倒推到 start
	var trail: Array[int] = [goal_pack]
	var cur: int = goal_pack
	while cur != start_pack:
		if not came_from.has(cur):
			# 重建失败(理论不该发生 — A* 找到 goal 必有 came_from 链)
			return RtsWaypointPath.new()
		cur = came_from[cur]
		trail.append(cur)
	# trail = [goal, ..., start];push goal..start 之前的 cells(跳 start_pack):
	# trail[0] = goal → waypoints[0],trail[N-2] = next-step → waypoints[N-2] = back()
	for k in range(trail.size() - 1):
		var pc: int = trail[k]
		@warning_ignore("integer_division")
		var x: int = pc / _PACK_LIMIT
		var y: int = pc % _PACK_LIMIT
		path.push_back(_grid.navcell_center_world(x, y))
	return path
