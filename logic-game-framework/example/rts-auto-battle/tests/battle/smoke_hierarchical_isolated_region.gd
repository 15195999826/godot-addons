## RtsHierarchicalPathfinder isolated region smoke (M4a — R5 P1 #3 关键验证)
##
## 验证 R5 P1 #3 修订:_compute_global_regions 起点 = 全量 packed RegionID(不只 edges.keys())。
##
## **失败模式**(原实现 bug):若 _compute_global_regions 仅遍历 edges.keys() 起点,**漏算 isolated
## region** — 完全在某 chunk 内、跟其他 chunk 都不接壤的合法可通行区域。这种 region 没在 edges 里,
## global_regions[rid] 永远不被赋值,is_goal_reachable 把合法 isolated region 当不可达。
##
## **测试场景**:
##   - 单 chunk 内构造 4 个独立的小 island region(被墙隔开,且都不接触 chunk 边界)
##   - 单 chunk 设置下 _edges 必为空(没有跨 chunk 接壤)
##   - 验证 4 个 isolated region 都拿到 unique GlobalRegionID(1, 2, 3, 4)
##   - 验证 _global_regions 含全部 4 个 packed RID
##
## 同时覆盖 **AC1 + AC8 边界**:
##   - 跨 chunk 接壤但其中一边被墙阻隔 → 该 region 仍是 isolated(没邻居)
##   - GlobalID 分配按 packed RID 升序 deterministic
##
## 不依赖 procedure / world — 直接 NavcellGrid + Pathfinder 数据结构 smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_4_isolated_regions_in_single_chunk()
	_test_isolated_chunk_within_2x2_grid()
	_test_global_id_assignment_order()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - hierarchical_isolated_region — R5 P1 #3 + AC1/AC8 OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_registry_default_only() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	return registry


# 把 grid 整个填满 mask(整图 impassable),给后续局部凿洞用。
func _block_all(grid: RtsNavcellGrid, w: int, h: int, mask: int) -> void:
	for j in range(h):
		for i in range(w):
			grid.or_data(i, j, mask)


# 在 grid 内凿出 [i0, i1] × [j0, j1] 的 passable 矩形(清 mask bit)。
func _carve_rect(grid: RtsNavcellGrid, i0: int, j0: int, i1: int, j1: int, mask: int) -> void:
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			grid.and_data(i, j, mask)


# ========== Test cases ==========

func _test_4_isolated_regions_in_single_chunk() -> void:
	# 单 chunk 96×96。整图墙,然后在 4 个内部位置各凿一个 5×5 passable rect,
	# 4 个 rect 互不相邻 + 都不挨 chunk 边界(简化:都在 chunk 中央偏内)
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE  # 96
	var grid := RtsNavcellGrid.new(chunk_size, chunk_size)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	# 整图墙
	_block_all(grid, chunk_size, chunk_size, default_mask)

	# 4 个 island rect(各 5×5 passable),位置:左上 / 右上 / 左下 / 右下,远离 chunk 边
	# 都不接触 chunk 边界 (i ∈ [10, 14] / [70, 74], j ∈ [10, 14] / [70, 74])
	_carve_rect(grid, 10, 10, 14, 14, default_mask)  # island 1
	_carve_rect(grid, 70, 10, 74, 14, default_mask)  # island 2
	_carve_rect(grid, 10, 70, 14, 74, default_mask)  # island 3
	_carve_rect(grid, 70, 70, 74, 74, default_mask)  # island 4

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	# 单 chunk → _edges 空(没有跨 chunk 接壤)
	var edges: Dictionary = hp.get_edges(default_mask)
	if not edges.is_empty():
		_failures.append("single chunk: edges expected empty got %d" % edges.size())

	# 应有 4 个 local region
	var ch: RtsHierarchicalChunk = hp.get_chunk(0, 0, default_mask)
	if ch.regions_id.size() != 4:
		_failures.append("4 islands: regions_id expected 4 got %d (regions=%s)" % [ch.regions_id.size(), str(ch.regions_id)])
		return

	# 4 个 packed RID 都应在 _global_regions 表里(R5 P1 #3 关键验证)
	var globals: Dictionary = hp.get_global_regions(default_mask)
	if globals.size() != 4:
		_failures.append("R5 P1 #3: global_regions expected 4 entries got %d (R5 P1 #3 bug = isolated region missed)" % globals.size())
		return

	# 4 个 GlobalID 都非 0,且互不相同(unique)
	var assigned_global_ids: Array[int] = []
	for local_r in ch.regions_id:
		var rid: int = RtsRegionIdHelper.pack(0, 0, local_r)
		var gid: int = globals.get(rid, 0)
		if gid == 0:
			_failures.append("R5 P1 #3: isolated region rid=%d got GlobalID 0 (means missed in compute)" % rid)
			continue
		if gid in assigned_global_ids:
			_failures.append("isolated regions should have unique GlobalID; rid=%d duplicates GlobalID %d" % [rid, gid])
		assigned_global_ids.append(gid)

	# next_global_region 应 = 5(分配了 1, 2, 3, 4)
	if hp.next_global_region(default_mask) != 5:
		_failures.append("R5 P1 #3: next_global expected 5 got %d" % hp.next_global_region(default_mask))


func _test_isolated_chunk_within_2x2_grid() -> void:
	# 2×2 chunks,左上 chunk 整 chunk 全墙(0 region),右上 chunk 全可通(1 region),
	# 左下 chunk 全墙(0 region),右下 chunk 全可通(1 region)。
	# 右上 / 右下两 chunk passable,但它们之间不接壤(右上下边墙;右下上边墙):
	#   - 右上 chunk 底排 (cj=0, lj=95) 全 impassable → 跟右下 (cj=1, lj=0) 没 edge
	# → 右上 / 右下 各是 isolated chunk-level region
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size * 2, chunk_size * 2)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	# 左上 chunk(ci=0, cj=0)整 chunk 墙
	for j in range(chunk_size):
		for i in range(chunk_size):
			grid.or_data(i, j, default_mask)

	# 左下 chunk(ci=0, cj=1)整 chunk 墙
	for j in range(chunk_size, chunk_size * 2):
		for i in range(chunk_size):
			grid.or_data(i, j, default_mask)

	# 右上 chunk 底边 + 右下 chunk 顶边一行墙 → 让它们不接壤
	for i in range(chunk_size, chunk_size * 2):
		grid.or_data(i, chunk_size - 1, default_mask)  # 右上 chunk 底排
		grid.or_data(i, chunk_size, default_mask)      # 右下 chunk 顶排

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	# 右上 chunk(ci=1, cj=0)有 1 region,右下 chunk(ci=1, cj=1)有 1 region
	var ch_tr: RtsHierarchicalChunk = hp.get_chunk(1, 0, default_mask)
	var ch_br: RtsHierarchicalChunk = hp.get_chunk(1, 1, default_mask)
	if ch_tr.regions_id.size() != 1:
		_failures.append("isolated-chunk: top-right regions_id expected 1 got %d" % ch_tr.regions_id.size())
	if ch_br.regions_id.size() != 1:
		_failures.append("isolated-chunk: bot-right regions_id expected 1 got %d" % ch_br.regions_id.size())

	# 左上 / 左下空 chunk regions_id 空
	var ch_tl: RtsHierarchicalChunk = hp.get_chunk(0, 0, default_mask)
	var ch_bl: RtsHierarchicalChunk = hp.get_chunk(0, 1, default_mask)
	if not ch_tl.regions_id.is_empty():
		_failures.append("isolated-chunk: top-left regions_id expected empty got %d" % ch_tl.regions_id.size())
	if not ch_bl.regions_id.is_empty():
		_failures.append("isolated-chunk: bot-left regions_id expected empty got %d" % ch_bl.regions_id.size())

	# 右上 vs 右下 之间不应该有 edge(被墙隔开)
	var edges: Dictionary = hp.get_edges(default_mask)
	var rid_tr: int = RtsRegionIdHelper.pack(1, 0, 1)
	var rid_br: int = RtsRegionIdHelper.pack(1, 1, 1)
	var tr_neighbors: Array = edges.get(rid_tr, [])
	if rid_br in tr_neighbors:
		_failures.append("isolated-chunk: right-top should NOT have edge to right-bot (blocked by wall)")

	# Global regions:右上 / 右下 各拿独立 GlobalID(2 个非 0 unique GlobalID)
	var globals: Dictionary = hp.get_global_regions(default_mask)
	var gid_tr: int = globals.get(rid_tr, 0)
	var gid_br: int = globals.get(rid_br, 0)
	if gid_tr == 0 or gid_br == 0:
		_failures.append("isolated-chunk: GlobalID expected non-zero for both, got tr=%d br=%d" % [gid_tr, gid_br])
	if gid_tr == gid_br:
		_failures.append("isolated-chunk: top-right and bot-right should have DIFFERENT GlobalID, both = %d" % gid_tr)


func _test_global_id_assignment_order() -> void:
	# 验证 GlobalID 按 packed RID 升序分配(deterministic)
	# 单 chunk 内 4 isolated region:region 1, 2, 3, 4 — 按 BFS 起点字典序分配 local r,
	# packed RID 按 (ci=0, cj=0, r) 升序 = r 升序 = 1,2,3,4
	# → GlobalID 也按此顺序 = 1, 2, 3, 4
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size, chunk_size)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	_block_all(grid, chunk_size, chunk_size, default_mask)

	# 4 island,起点字典序 (lj 主, li 次):
	#   island 1: (10, 10)..(14, 14)  → BFS 起点首次出现 (10, 10),local r = 1
	#   island 2: (70, 10)..(74, 14)  → 首次 (70, 10) 在 lj=10, li=70,但 lj=10 时 li=10 先扫到 → r=1 已分配
	#                                    继续扫,lj=10, li ∈ [11, 69] 都 impassable, li=70 → r=2
	#   island 3: (10, 70)..(14, 74)  → lj=70, li=10 → r=3
	#   island 4: (70, 70)..(74, 74)  → lj=70, li=70 → r=4
	_carve_rect(grid, 10, 10, 14, 14, default_mask)
	_carve_rect(grid, 70, 10, 74, 14, default_mask)
	_carve_rect(grid, 10, 70, 14, 74, default_mask)
	_carve_rect(grid, 70, 70, 74, 74, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var ch: RtsHierarchicalChunk = hp.get_chunk(0, 0, default_mask)
	# 验证 BFS 起点字典序产生的 local region ID
	if ch.get_region(10, 10) != 1:
		_failures.append("order: (10,10) expected region 1 got %d" % ch.get_region(10, 10))
	if ch.get_region(70, 10) != 2:
		_failures.append("order: (70,10) expected region 2 got %d" % ch.get_region(70, 10))
	if ch.get_region(10, 70) != 3:
		_failures.append("order: (10,70) expected region 3 got %d" % ch.get_region(10, 70))
	if ch.get_region(70, 70) != 4:
		_failures.append("order: (70,70) expected region 4 got %d" % ch.get_region(70, 70))

	# GlobalID 也按 packed RID 升序分配
	var globals: Dictionary = hp.get_global_regions(default_mask)
	for local_r in [1, 2, 3, 4]:
		var rid: int = RtsRegionIdHelper.pack(0, 0, local_r)
		var gid: int = globals.get(rid, 0)
		if gid != local_r:
			_failures.append("order: GlobalID for rid=%d (local r=%d) expected %d got %d" % [rid, local_r, local_r, gid])
