## RtsHierarchicalPathfinder - 0 A.D. 风格 chunk + region 可达性查询 (M4 引入)
##
## 0 A.D. `helpers/HierarchicalPathfinder.h/cpp` 的 GDScript 复刻。把 NavcellGrid 切成
## CHUNK_SIZE × CHUNK_SIZE 的 chunks,每 chunk 内 BFS 划分 region;跨 chunk 接壤可达的
## region 之间注册 edge;再做一次跨 chunk flood-fill 给同一连通分量分配 GlobalRegionID。
##
## **核心用途**(M4b 启用):
##   - `is_goal_reachable(start, goal, mask)` — 不修改 goal 检查可达
##   - `make_goal_reachable(start, goal, mask)` — canonicalize goal(替换为最近可达 navcell POINT)
##
## **M4a 阶段范围**:仅落 `recompute(grid, classes)` + 内部 chunks / edges / global_regions
## 数据结构。M4b 才接 `get_region` / `get_global_region` / `is_goal_reachable` /
## `make_goal_reachable` API + wire 进玩家命令。
##
## **生命周期**:RefCounted,挂 RtsWorldGameplayInstance.hierarchical_pathfinder。
## procedure._init 末尾构造,procedure.start() 末尾首次 recompute(grid 已 rasterize 后)。
##
## **Determinism contract**(data-structures.md §12.2):
##   - chunk flood-fill 起点按 `(local_j, local_i)` 字典序
##   - region ID 在 chunk 内按 BFS 起点顺序单调递增(1, 2, 3, ...)
##   - 跨 chunk edge 注册按"较小 packed RID 先注册"
##   - GlobalRegion BFS 起点 = 全量 packed RegionID 升序(R5 P1 #3 修订:不只 edges.keys(),
##     必须含 isolated region — 完全在某 chunk 内、与其他 chunk 无接壤的合法 passable region)
##
## **决策来源**:
##   - data-structures.md §4 + §12.2
##   - milestones/M4-hierarchical.md §M4a
##   - 0 A.D. 对照:helpers/HierarchicalPathfinder.h:120-170 公开 API + Recompute / Update
class_name RtsHierarchicalPathfinder
extends RefCounted


# ========== 常量 ==========

## 4 邻居 (li/lj) 偏移,顺序 +x/-x/+y/-y deterministic。
## 文件级 const 避免 BFS 内层每次 alloc 4 元 Array + 4 个 Vector2i。
const _NEIGHBOR_DELTA_LI: Array[int] = [1, -1, 0, 0]
const _NEIGHBOR_DELTA_LJ: Array[int] = [0, 0, 1, -1]


# ========== 字段 ==========

## 整图 chunk 列数(width / CHUNK_SIZE 向上取整);recompute 时填。
var _chunks_w: int = 0

## 整图 chunk 行数。
var _chunks_h: int = 0

## pass_mask (int) → Array[RtsHierarchicalChunk](按 cj * _chunks_w + ci 索引)。
##
## 每个 pass class 一份独立 chunks(D2 / data-structures §4.4)。
var _chunks: Dictionary = {}

## pass_mask (int) → Dictionary[packed RegionID(int) → Array[packed RegionID(int)]]。
##
## 跨 chunk 接壤的 region 之间的双向 edges。无向图:edges[a] 含 b ⇔ edges[b] 含 a。
## 邻居数组按 packed RID 升序(M4a.4 _add_undirected_edge 维护)。
var _edges: Dictionary = {}

## pass_mask (int) → Dictionary[packed RegionID(int) → GlobalRegionID(int)]。
##
## GlobalRegionID 单调递增,从 1 开始;同号 = 同一连通分量(整图可达)。
## 0 表示未分配 / impassable(查询时 fall-back 到 INVALID 语义)。
var _global_regions: Dictionary = {}

## pass_mask (int) → 下一个分配的 GlobalRegionID(单调递增 cursor)。
var _next_global_region: Dictionary = {}

## recompute 时存 grid 引用,M4b 查询 API(world ↔ navcell index)需要;调方修改 grid 后
## 必须重 recompute(M4a 阶段一次性,M4c 阶段 incremental update 时同步刷新)。
var _grid: RtsNavcellGrid = null


# ========== 常量 (M4b 查询) ==========

## 螺旋 / ring scan 最大半径(navcells)。200 × 32 px = 6400 px,足够覆盖正常游戏地图。
## 超过此半径 find_nearest_* 返 (-1, -1) — 玩家点距离任何可通行区域 6400 px 之外算"找不到"。
const _MAX_NEAREST_RADIUS: int = 200


# ========== 初始化 ==========

func _init() -> void:
	pass


# ========== M4a 入口:全图重建 ==========

## 全图重建 chunks + edges + global regions。
##
## 调方:procedure.start() 末尾(grid 已 rasterize 后);M4c 启用时 update(dirty) 替代每帧调
## recompute。
##
## **不清 grid._dirtiness** — 调方负责按 R5 P1-2 lifecycle 在 RtsWorld.tick step 7 末端清。
##
## per pass class 独立处理(D2);跑顺序按 registry.get_classes() 注册顺序(default → air),
## class.affects_pathfinding 为 false 的(air)虽然没 BLOCK_PATHFINDING 写入,但 chunks /
## edges / global_regions 仍然建立(整 chunk 全 passable,1 个大 region)— 让 M4b 查询接口
## 无需特判 air vs ground。
func recompute(grid: RtsNavcellGrid, classes: Array[RtsPassabilityClassConfig]) -> void:
	Log.assert_crash(grid != null, "RtsHierarchicalPathfinder", "recompute: grid is null")
	Log.assert_crash(classes != null, "RtsHierarchicalPathfinder", "recompute: classes is null")

	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	_chunks_w = (grid.width() + chunk_size - 1) / chunk_size
	_chunks_h = (grid.height() + chunk_size - 1) / chunk_size

	_chunks.clear()
	_edges.clear()
	_global_regions.clear()
	_next_global_region.clear()

	for cls in classes:
		var pass_mask: int = 1 << cls.bit_index

		# 1) Per-chunk flood-fill → local region ID
		var chunks: Array[RtsHierarchicalChunk] = []
		chunks.resize(_chunks_w * _chunks_h)
		for cj in range(_chunks_h):
			for ci in range(_chunks_w):
				chunks[cj * _chunks_w + ci] = _build_chunk(grid, ci, cj, pass_mask)
		_chunks[pass_mask] = chunks

		# 2) 注册跨 chunk edges
		_build_edges(pass_mask, chunks, _chunks_w, _chunks_h)

		# 3) 计算 GlobalRegionID(R5 P1 #3 修订:起点 = 全量 packed RegionID,含 isolated)
		_compute_global_regions(pass_mask)

	# 存 grid 引用给 M4b 查询 API(world ↔ navcell index 转换);调方下次 recompute 会刷新。
	_grid = grid


# ========== M4a 内部:per-chunk flood-fill ==========

## 单 chunk 内 BFS 划 region:起点按 (local_j, local_i) 字典序,region ID 从 1 起单调递增。
func _build_chunk(grid: RtsNavcellGrid, ci: int, cj: int, pass_mask: int) -> RtsHierarchicalChunk:
	var ch := RtsHierarchicalChunk.new(ci, cj)
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var next_local_r: int = 1

	for lj in range(chunk_size):
		var row_base: int = lj * chunk_size
		for li in range(chunk_size):
			if ch.regions[row_base + li] != 0:
				continue
			var gi: int = ci * chunk_size + li
			var gj: int = cj * chunk_size + lj
			# 越界(grid 不是 chunk_size 整数倍)由 grid.is_passable 边界外返 false 兜底。
			if not grid.is_passable(gi, gj, pass_mask):
				continue
			_flood_fill_chunk(grid, ch, ci, cj, li, lj, next_local_r, pass_mask)
			ch.regions_id.append(next_local_r)
			next_local_r += 1
	return ch


## 从 (start_li, start_lj) 在 chunk 内 BFS 4 邻居(不跨 chunk),把整个连通块打 r 标记。
##
## **Cursor 模式**: queue 用 PackedInt32Array + head 游标,避免 Array.pop_front() 的 O(N)
## memmove(9216-cell BFS 最坏 O(N²) ≈ 8500 万次拷贝 → 改完 O(N) ≈ 9216 次)。
## 元素是 packed `lj * chunk_size + li`,顺手省掉 Vector2i 实例化开销。
func _flood_fill_chunk(
	grid: RtsNavcellGrid,
	ch: RtsHierarchicalChunk,
	ci: int,
	cj: int,
	start_li: int,
	start_lj: int,
	r: int,
	pass_mask: int,
) -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(start_lj * chunk_size + start_li)
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		if ch.regions[idx] != 0:
			continue
		ch.regions[idx] = r
		var li: int = idx % chunk_size
		var lj: int = idx / chunk_size
		for d in range(4):
			var nli: int = li + _NEIGHBOR_DELTA_LI[d]
			var nlj: int = lj + _NEIGHBOR_DELTA_LJ[d]
			if nli < 0 or nli >= chunk_size or nlj < 0 or nlj >= chunk_size:
				continue
			var ngi: int = ci * chunk_size + nli
			var ngj: int = cj * chunk_size + nlj
			if not grid.is_passable(ngi, ngj, pass_mask):
				continue
			var nidx: int = nlj * chunk_size + nli
			if ch.regions[nidx] != 0:
				continue
			queue.append(nidx)


# ========== M4a 内部:跨 chunk edges ==========

## 扫所有相邻 chunk 对(右邻 + 下邻),把接壤可达的 region 双向 edge 注册到 _edges。
func _build_edges(
	pass_mask: int,
	chunks: Array[RtsHierarchicalChunk],
	w: int,
	h: int,
) -> void:
	var edges: Dictionary = {}
	for cj in range(h):
		for ci in range(w):
			var ch_a: RtsHierarchicalChunk = chunks[cj * w + ci]
			if ci + 1 < w:
				_add_vertical_edges(ch_a, chunks[cj * w + ci + 1], edges)
			if cj + 1 < h:
				_add_horizontal_edges(ch_a, chunks[(cj + 1) * w + ci], edges)
	_edges[pass_mask] = edges


## ch_a 在左,ch_b 在右;扫 ch_a 右边 (li=CHUNK_SIZE-1) vs ch_b 左边 (li=0)。
func _add_vertical_edges(ch_a: RtsHierarchicalChunk, ch_b: RtsHierarchicalChunk, edges: Dictionary) -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	for lj in range(chunk_size):
		_add_pair_if_passable(ch_a, ch_b, ch_a.get_region(chunk_size - 1, lj), ch_b.get_region(0, lj), edges)


## ch_a 在上,ch_b 在下;扫 ch_a 底边 (lj=CHUNK_SIZE-1) vs ch_b 顶边 (lj=0)。
func _add_horizontal_edges(ch_a: RtsHierarchicalChunk, ch_b: RtsHierarchicalChunk, edges: Dictionary) -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	for li in range(chunk_size):
		_add_pair_if_passable(ch_a, ch_b, ch_a.get_region(li, chunk_size - 1), ch_b.get_region(li, 0), edges)


## 双侧 region 都非 0 → 注册双向 edge(packed RID)。0 = 接壤 navcell impassable,跳过。
func _add_pair_if_passable(
	ch_a: RtsHierarchicalChunk,
	ch_b: RtsHierarchicalChunk,
	ra: int,
	rb: int,
	edges: Dictionary,
) -> void:
	if ra == 0 or rb == 0:
		return
	_add_undirected_edge(
		edges,
		RtsRegionIdHelper.pack(ch_a.ci, ch_a.cj, ra),
		RtsRegionIdHelper.pack(ch_b.ci, ch_b.cj, rb),
	)


## 双向加 edge a↔b。两端邻居数组按 packed RID 升序保 deterministic(§12.2)。
##
## **bsearch + insert** 替代 append+sort,保证有序的同时去重。接壤行内多个相邻 navcell 反复
## 触发同 region pair 时,bsearch 命中已存元素直接跳过。
func _add_undirected_edge(edges: Dictionary, a: int, b: int) -> void:
	if a == b:
		return  # 同 chunk 内 region 不可能跨 chunk 接壤(BFS 不出 chunk),自环防御
	_insert_sorted_unique(edges, a, b)
	_insert_sorted_unique(edges, b, a)


func _insert_sorted_unique(edges: Dictionary, key: int, value: int) -> void:
	var arr: Array = edges.get(key, [])
	var pos: int = arr.bsearch(value)
	if pos < arr.size() and arr[pos] == value:
		return
	arr.insert(pos, value)
	edges[key] = arr


# ========== M4a 内部:GlobalRegionID 计算(R5 P1 #3 修订)==========

## 跨 chunk flood-fill 给同一连通分量分配 GlobalRegionID。
##
## ⚠️ **R5 P1 #3 修订** — 起点必须**枚举所有 chunk.regions_id 生成全量 packed RegionID**:
##
## 原实现只从 `_edges[pass_mask].keys()` 取起点,**漏了"无跨 chunk edge 的 isolated passable
## region"** — 这种 region 完全在某 chunk 内,与所有邻 chunk 都不接壤(可能整 chunk 是孤岛,
## 也可能 chunk 内有多个独立连通块但都不挨着 chunk 边界)。这类 region 不在 edges 表里,
## 但仍是合法可通行区域。漏算导致 `_global_regions[rid]` 为 0,`is_goal_reachable` 把这种
## 合法 isolated region 当不可达 → 单位走不进去。
##
## **修订**:起点 = 全量 packed RegionID 升序(`(ci, cj, local_r)` 字典序保 deterministic);
## edges 仅作为"扩展邻居"的图。Isolated region 单独 BFS 起点 → 单独拿 GlobalRegionID。
func _compute_global_regions(pass_mask: int) -> void:
	var edges: Dictionary = _edges[pass_mask]
	var chunks: Array[RtsHierarchicalChunk] = _chunks[pass_mask]

	# R5 P1 #3:起点 = 全量 packed RegionID,**不是** edges.keys()
	var all_rids: Array[int] = []
	for ch in chunks:
		for local_r in ch.regions_id:    # local_r ≥ 1(不含 0/impassable)
			all_rids.append(RtsRegionIdHelper.pack(ch.ci, ch.cj, local_r))
	all_rids.sort()       # packed RID 升序 = (ci, cj, r) 字典序

	var global: Dictionary = {}
	var next_global: int = 1
	# Cursor 模式 BFS(同 _flood_fill_chunk):避免 Array.pop_front() O(N)。
	var queue: PackedInt64Array = PackedInt64Array()
	for rid in all_rids:
		if global.has(rid):
			continue
		queue.clear()
		queue.append(rid)
		var head: int = 0
		while head < queue.size():
			var r: int = queue[head]
			head += 1
			if global.has(r):
				continue
			global[r] = next_global
			# isolated region 在 edges 里没有 entry,get(r, []) = [],BFS 自然结束 —
			# 但 r 已分配到 next_global,isolated region 也拿到 GlobalID(R5 P1 #3)。
			for n in edges.get(r, []):
				if not global.has(n):
					queue.append(n)
		next_global += 1

	_global_regions[pass_mask] = global
	_next_global_region[pass_mask] = next_global


# ========== M4b 公开查询 API(player command / activity 消费)==========

## 已经做过 recompute 吗(替代外部 flag 跟踪 lazy 初始化)。
func is_recomputed() -> bool:
	return _chunks_w > 0


## 取 (i, j) navcell 所属 packed RegionID;impassable / 越界 → INVALID(0)。
func get_region(i: int, j: int, pass_mask: int) -> int:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var ci: int = i / chunk_size
	var cj: int = j / chunk_size
	var ch: RtsHierarchicalChunk = get_chunk(ci, cj, pass_mask)
	if ch == null:
		return RtsRegionIdHelper.INVALID
	var li: int = i % chunk_size
	var lj: int = j % chunk_size
	if li < 0 or li >= chunk_size or lj < 0 or lj >= chunk_size:
		return RtsRegionIdHelper.INVALID
	var local_r: int = ch.get_region(li, lj)
	if local_r == 0:
		return RtsRegionIdHelper.INVALID
	return RtsRegionIdHelper.pack(ci, cj, local_r)


## 取 (i, j) navcell 所属 GlobalRegionID;impassable / 越界 → 0。
##
## 同 GlobalID = 同一连通分量(整图可达);0 永远表示不可通行 / 未知。
func get_global_region(i: int, j: int, pass_mask: int) -> int:
	var rid: int = get_region(i, j, pass_mask)
	if RtsRegionIdHelper.is_invalid(rid):
		return 0
	return _global_regions.get(pass_mask, {}).get(rid, 0)


## 给定 start_world / goal_world,goal 是否跟 start 同一 GlobalRegion(整图可达)。
##
## 不修改任何状态。start 落在 impassable navcell 时返 false(不做 fallback,
## 跟 make_goal_reachable_point 区分:本 API 是"原 goal 直接可达"判定)。
func is_goal_reachable_point(start_world: Vector2, goal_world: Vector2, pass_mask: int) -> bool:
	if _grid == null:
		return false
	var start_ij: Vector2i = _grid.nearest_navcell(start_world)
	var start_g: int = get_global_region(start_ij.x, start_ij.y, pass_mask)
	if start_g == 0:
		return false
	var goal_ij: Vector2i = _grid.nearest_navcell(goal_world)
	var goal_g: int = get_global_region(goal_ij.x, goal_ij.y, pass_mask)
	return goal_g == start_g


## Canonicalize POINT goal 到最近可达 navcell — 但仅在不可达时改 goal,可达时 no-op。
##
## 返回 Dictionary:
##   - "reachable": bool — true: goal_world 跟 start_world 同一 GlobalRegion;
##                          false: 不同 / goal 在 impassable / start 在 impassable 全找不到 fallback
##   - "canonicalized_world": Vector2:
##                              reachable: **= 原 goal_world**(no-op,不改 baseline 路径)
##                              !reachable: 跟 start 同 GlobalRegion 的、离 goal 最近的 navcell 中心
##                              彻底找不到任何可通 navcell:返原 goal_world(兜底,callsite 应记日志)
##
## **为什么 reachable=true 时不 canonicalize 到 navcell 中心**:
## spec §M4b.2 描述"总是 mutate goal 到 POINT navcell 中心"是给 M5 LongPathfinder 用的(它期望
## navcell 中心点做 A* 起终点)。但 M5 之前 LongPathfinder 不存在,单位走 RtsNavAgent +
## NavigationAgent2D 路径 — canonicalize 到 navcell 中心会让 target 偏 0-16 px → 改 baseline 路径
## → 触发 stop runner 第 6 条(M4 不应改路径)。M4b 阶段保留"reachable → no-op"语义,
## M5 引入 LongPathfinder 时再改成"总是 navcell 中心 canonicalize"+ 接受 P1 baseline 漂。
##
## **不**修改 grid / hierarchical 状态(纯查询)。
func make_goal_reachable_point(
	start_world: Vector2,
	goal_world: Vector2,
	pass_mask: int,
) -> Dictionary:
	if _grid == null:
		return {"reachable": false, "canonicalized_world": goal_world}

	var start_ij: Vector2i = _grid.nearest_navcell(start_world)
	var start_g: int = get_global_region(start_ij.x, start_ij.y, pass_mask)

	# start 在 impassable navcell → 找最近 passable 作 fallback start
	if start_g == 0:
		var fallback: Vector2i = find_nearest_passable_navcell(start_ij, pass_mask)
		if fallback == Vector2i(-1, -1):
			return {"reachable": false, "canonicalized_world": goal_world}
		start_ij = fallback
		start_g = get_global_region(start_ij.x, start_ij.y, pass_mask)
		if start_g == 0:
			return {"reachable": false, "canonicalized_world": goal_world}

	var goal_ij: Vector2i = _grid.nearest_navcell(goal_world)
	var goal_g: int = get_global_region(goal_ij.x, goal_ij.y, pass_mask)

	if goal_g == start_g and goal_g != 0:
		# 可达:no-op(M4b 阶段保 baseline,见 docstring)
		return {"reachable": true, "canonicalized_world": goal_world}

	# 不可达:找跟 start 同 GlobalRegion 的、离 goal 最近的 navcell
	var nearest: Vector2i = _find_nearest_in_global_region(goal_ij, start_g, pass_mask)
	if nearest == Vector2i(-1, -1):
		# 兜底:start 自身一定 ∈ start_g,不应到此(防御 _MAX_NEAREST_RADIUS 内找不到的极端 case)
		return {"reachable": false, "canonicalized_world": _grid.navcell_center_world(start_ij.x, start_ij.y)}
	return {"reachable": false, "canonicalized_world": _grid.navcell_center_world(nearest.x, nearest.y)}


## 螺旋 / ring scan 找离 start 最近的 passable (任意 GlobalRegion) navcell。
##
## start 自身可通就返 start;否则按 chess-board 距离 r=1, 2, 3, ... 外扩,每 ring 内
## 按 (di, dj) 字典序遍历 → deterministic。超过 _MAX_NEAREST_RADIUS 返 (-1, -1)。
func find_nearest_passable_navcell(start: Vector2i, pass_mask: int) -> Vector2i:
	if _grid == null:
		return Vector2i(-1, -1)
	if _grid.is_passable(start.x, start.y, pass_mask):
		return start
	for r in range(1, _MAX_NEAREST_RADIUS + 1):
		var found: Vector2i = _scan_ring_for_passable(start, r, pass_mask)
		if found != Vector2i(-1, -1):
			return found
	return Vector2i(-1, -1)


## 螺旋 ring scan 找离 start 最近的、属于 target_global GlobalRegion 的 navcell。
##
## start 自身已 ∈ target_global 就返 start;否则外扩至 _MAX_NEAREST_RADIUS。
func _find_nearest_in_global_region(start: Vector2i, target_global: int, pass_mask: int) -> Vector2i:
	if _grid == null or target_global == 0:
		return Vector2i(-1, -1)
	if get_global_region(start.x, start.y, pass_mask) == target_global:
		return start
	for r in range(1, _MAX_NEAREST_RADIUS + 1):
		var found: Vector2i = _scan_ring_for_global(start, r, pass_mask, target_global)
		if found != Vector2i(-1, -1):
			return found
	return Vector2i(-1, -1)


## 扫 chess-board 距离 = r 的 ring,按 (di, dj) 字典序找第一个 passable navcell。
func _scan_ring_for_passable(center: Vector2i, r: int, pass_mask: int) -> Vector2i:
	for di in range(-r, r + 1):
		for dj in range(-r, r + 1):
			if maxi(absi(di), absi(dj)) != r:   # 仅 ring 上(不重复扫内层)
				continue
			var i: int = center.x + di
			var j: int = center.y + dj
			if _grid.is_passable(i, j, pass_mask):
				return Vector2i(i, j)
	return Vector2i(-1, -1)


## 扫 chess-board 距离 = r 的 ring,按 (di, dj) 字典序找第一个 ∈ target_global 的 navcell。
func _scan_ring_for_global(center: Vector2i, r: int, pass_mask: int, target_global: int) -> Vector2i:
	for di in range(-r, r + 1):
		for dj in range(-r, r + 1):
			if maxi(absi(di), absi(dj)) != r:
				continue
			var i: int = center.x + di
			var j: int = center.y + dj
			if get_global_region(i, j, pass_mask) == target_global:
				return Vector2i(i, j)
	return Vector2i(-1, -1)


# ========== M4a 调试 / smoke 查询 ==========


## chunks 数据(给 smoke 验证用;production code 应通过 M4b 公开 API)。
func chunks_w() -> int:
	return _chunks_w


func chunks_h() -> int:
	return _chunks_h


## 取 pass_mask 视角下 (ci, cj) chunk;不存在返 null。
func get_chunk(ci: int, cj: int, pass_mask: int) -> RtsHierarchicalChunk:
	if ci < 0 or ci >= _chunks_w or cj < 0 or cj >= _chunks_h:
		return null
	var arr: Array = _chunks.get(pass_mask, [])
	if arr.is_empty():
		return null
	return arr[cj * _chunks_w + ci] as RtsHierarchicalChunk


## 取 pass_mask 视角下整图 edges Dictionary 的引用(只读);不存在返 {}。
##
## 给 smoke 验证 edges 完整性用。production code 不应直接 mutate。
func get_edges(pass_mask: int) -> Dictionary:
	return _edges.get(pass_mask, {})


## 取 pass_mask 视角下 packed RegionID → GlobalRegionID 映射;给 smoke 用。
func get_global_regions(pass_mask: int) -> Dictionary:
	return _global_regions.get(pass_mask, {})


## 取 pass_mask 视角下下一个 GlobalRegionID(= 已分配数 + 1);给 smoke 用。
func next_global_region(pass_mask: int) -> int:
	return _next_global_region.get(pass_mask, 1)
