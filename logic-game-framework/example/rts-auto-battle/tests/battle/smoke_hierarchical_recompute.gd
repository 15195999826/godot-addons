## RtsHierarchicalPathfinder.recompute acceptance smoke (M4a — AC2 / AC8)
##
## 验证以下断言:
##
## **AC2 — recompute 正确**:
##   - 单 chunk 全可通 → 1 region(local r=1)
##   - 单 chunk 一半 impassable(竖直墙隔开)→ 2 regions
##   - 全 impassable chunk → regions_id 空(0 regions)
##
## **AC2 — 跨 chunk edges 完整**:
##   - 2×2 chunks 全可通,无内部墙 → 4 chunks 各 1 region,所有相邻 chunk pair 都有 edge,
##     最终 GlobalRegion = 1(全图同号)
##   - 2×2 chunks 中间用全图墙隔开 → 2 个 GlobalRegion
##
## **AC8 — Determinism**:
##   - 同 grid 跑两次 recompute → chunks regions / edges / global_regions deep-equal
##   - region ID 在 chunk 内单调递增(1, 2, 3, ...)
##
## 不依赖 procedure / world — 直接 NavcellGrid + Pathfinder 数据结构 smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_single_chunk_full_passable()
	_test_single_chunk_split_two_regions()
	_test_full_impassable_chunk()
	_test_2x2_chunks_all_connected()
	_test_2x2_chunks_split_by_wall()
	_test_determinism_two_runs()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - hierarchical_recompute — AC2 + AC8 all assertions OK")
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


func _block_cell(grid: RtsNavcellGrid, i: int, j: int, mask: int) -> void:
	grid.or_data(i, j, mask)


# ========== Test cases ==========

func _test_single_chunk_full_passable() -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE  # 96
	var grid := RtsNavcellGrid.new(chunk_size, chunk_size)  # 1×1 chunks
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	if hp.chunks_w() != 1 or hp.chunks_h() != 1:
		_failures.append("single-chunk: chunks_w/h expected 1/1 got %d/%d" % [hp.chunks_w(), hp.chunks_h()])
		return

	var ch: RtsHierarchicalChunk = hp.get_chunk(0, 0, default_mask)
	if ch == null:
		_failures.append("single-chunk: get_chunk(0,0) is null")
		return
	if ch.regions_id.size() != 1:
		_failures.append("single-chunk full passable: regions_id expected 1 got %d" % ch.regions_id.size())
		return
	if ch.regions_id[0] != 1:
		_failures.append("single-chunk: first region ID expected 1 got %d" % ch.regions_id[0])

	# 任意 navcell 应属 region 1
	if ch.get_region(0, 0) != 1 or ch.get_region(50, 50) != 1 or ch.get_region(95, 95) != 1:
		_failures.append("single-chunk full passable: get_region not all 1")

	# Global region: 单 region → GlobalID 1
	var globals: Dictionary = hp.get_global_regions(default_mask)
	var rid: int = RtsRegionIdHelper.pack(0, 0, 1)
	if globals.get(rid, 0) != 1:
		_failures.append("single-chunk: global_region(rid=%d) expected 1 got %d" % [rid, globals.get(rid, 0)])


func _test_single_chunk_split_two_regions() -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size, chunk_size)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	# 在 i=48 列竖直墙(从 j=0 到 j=95)— 把 chunk 一分为二
	for j in range(chunk_size):
		_block_cell(grid, 48, j, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var ch: RtsHierarchicalChunk = hp.get_chunk(0, 0, default_mask)
	if ch == null:
		_failures.append("split-chunk: get_chunk null")
		return
	if ch.regions_id.size() != 2:
		_failures.append("split-chunk: regions_id expected 2 got %d" % ch.regions_id.size())
		return
	# 左半(i < 48)= region 1;右半(i > 48)= region 2(因 BFS 起点 (0, 0) 字典序先扫)
	if ch.get_region(0, 0) != 1:
		_failures.append("split-chunk: (0,0) expected region 1 got %d" % ch.get_region(0, 0))
	if ch.get_region(47, 50) != 1:
		_failures.append("split-chunk: (47,50) expected region 1 got %d" % ch.get_region(47, 50))
	if ch.get_region(48, 50) != 0:
		_failures.append("split-chunk: (48,50) wall expected region 0 got %d" % ch.get_region(48, 50))
	if ch.get_region(49, 50) != 2:
		_failures.append("split-chunk: (49,50) expected region 2 got %d" % ch.get_region(49, 50))

	# Global region:同一 chunk 内两 region 互相不接(被墙隔开)→ 各自 GlobalID
	# 两 region 各 1 个 packed RID,排序后 (ci=0,cj=0,r=1) < (ci=0,cj=0,r=2)
	# 所以 region 1 → GlobalID 1, region 2 → GlobalID 2
	var globals: Dictionary = hp.get_global_regions(default_mask)
	var rid1: int = RtsRegionIdHelper.pack(0, 0, 1)
	var rid2: int = RtsRegionIdHelper.pack(0, 0, 2)
	if globals.get(rid1, 0) != 1 or globals.get(rid2, 0) != 2:
		_failures.append(
			"split-chunk: globals (rid1=%d → %d, rid2=%d → %d) expected (1, 2)" % [
				rid1, globals.get(rid1, 0), rid2, globals.get(rid2, 0),
			]
		)


func _test_full_impassable_chunk() -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size, chunk_size)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	# 全 chunk impassable
	for j in range(chunk_size):
		for i in range(chunk_size):
			_block_cell(grid, i, j, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var ch: RtsHierarchicalChunk = hp.get_chunk(0, 0, default_mask)
	if ch == null:
		_failures.append("full-impassable: get_chunk null")
		return
	if not ch.regions_id.is_empty():
		_failures.append("full-impassable: regions_id expected empty got %d" % ch.regions_id.size())
	if ch.get_region(0, 0) != 0 or ch.get_region(50, 50) != 0:
		_failures.append("full-impassable: get_region expected all 0")

	var globals: Dictionary = hp.get_global_regions(default_mask)
	if not globals.is_empty():
		_failures.append("full-impassable: global_regions expected empty got %d entries" % globals.size())


func _test_2x2_chunks_all_connected() -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size * 2, chunk_size * 2)  # 2×2 chunks
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	if hp.chunks_w() != 2 or hp.chunks_h() != 2:
		_failures.append("2x2: chunks_w/h expected 2/2 got %d/%d" % [hp.chunks_w(), hp.chunks_h()])
		return

	# 4 chunks 各 1 region(全可通)
	for cj in range(2):
		for ci in range(2):
			var ch: RtsHierarchicalChunk = hp.get_chunk(ci, cj, default_mask)
			if ch.regions_id.size() != 1:
				_failures.append("2x2 (%d,%d): regions_id expected 1 got %d" % [ci, cj, ch.regions_id.size()])

	# Edges:每个 region (ci, cj, r=1) 与右邻 / 下邻 都有 edge
	# 4 region pair 应各自连接:(0,0)-(1,0), (0,0)-(0,1), (1,0)-(1,1), (0,1)-(1,1)
	var edges: Dictionary = hp.get_edges(default_mask)
	var rid_00: int = RtsRegionIdHelper.pack(0, 0, 1)
	var rid_10: int = RtsRegionIdHelper.pack(1, 0, 1)
	var rid_01: int = RtsRegionIdHelper.pack(0, 1, 1)
	var rid_11: int = RtsRegionIdHelper.pack(1, 1, 1)

	var pairs: Array = [
		[rid_00, rid_10],
		[rid_00, rid_01],
		[rid_10, rid_11],
		[rid_01, rid_11],
	]
	for p in pairs:
		var a: int = p[0]
		var b: int = p[1]
		var a_neighbors: Array = edges.get(a, [])
		if not (b in a_neighbors):
			_failures.append("2x2 edges: pair(%d, %d) missing in a_neighbors=%s" % [a, b, str(a_neighbors)])
		var b_neighbors: Array = edges.get(b, [])
		if not (a in b_neighbors):
			_failures.append("2x2 edges: pair(%d, %d) missing in b_neighbors" % [a, b])

	# Global regions:4 个 packed RID 全连通 → 都拿同一 GlobalID(1)
	var globals: Dictionary = hp.get_global_regions(default_mask)
	if globals.get(rid_00, 0) != 1 or globals.get(rid_10, 0) != 1 or globals.get(rid_01, 0) != 1 or globals.get(rid_11, 0) != 1:
		_failures.append("2x2 all-connected: expected all GlobalID=1 got (%d,%d,%d,%d)" % [
			globals.get(rid_00, 0),
			globals.get(rid_10, 0),
			globals.get(rid_01, 0),
			globals.get(rid_11, 0),
		])
	if hp.next_global_region(default_mask) != 2:
		_failures.append("2x2 all-connected: next_global expected 2 got %d" % hp.next_global_region(default_mask))


func _test_2x2_chunks_split_by_wall() -> void:
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size * 2, chunk_size * 2)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	# 整图水平墙 j=chunk_size-1 + j=chunk_size — 把 grid 上下两半完全断开
	for i in range(chunk_size * 2):
		_block_cell(grid, i, chunk_size - 1, default_mask)
		_block_cell(grid, i, chunk_size, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	# 上半 chunks (cj=0): regions 各 1(被墙阻挡的最后一行 navcell impassable → 95 行可通)
	# 下半 chunks (cj=1): regions 各 1(同理)
	var globals: Dictionary = hp.get_global_regions(default_mask)
	var top_left: int = globals.get(RtsRegionIdHelper.pack(0, 0, 1), 0)
	var top_right: int = globals.get(RtsRegionIdHelper.pack(1, 0, 1), 0)
	var bot_left: int = globals.get(RtsRegionIdHelper.pack(0, 1, 1), 0)
	var bot_right: int = globals.get(RtsRegionIdHelper.pack(1, 1, 1), 0)

	# 上 2 chunks 同 GlobalID,下 2 chunks 同 GlobalID,但上 ≠ 下
	if top_left == 0 or top_right == 0 or bot_left == 0 or bot_right == 0:
		_failures.append("2x2 split: any GlobalID == 0: (%d,%d,%d,%d)" % [top_left, top_right, bot_left, bot_right])
		return
	if top_left != top_right:
		_failures.append("2x2 split: top half should share GlobalID, got %d vs %d" % [top_left, top_right])
	if bot_left != bot_right:
		_failures.append("2x2 split: bot half should share GlobalID, got %d vs %d" % [bot_left, bot_right])
	if top_left == bot_left:
		_failures.append("2x2 split: top vs bot should differ, both == %d" % top_left)
	if hp.next_global_region(default_mask) != 3:
		_failures.append("2x2 split: next_global expected 3 (2 GlobalIDs assigned) got %d" % hp.next_global_region(default_mask))


func _test_determinism_two_runs() -> void:
	# 跑两次 recompute,验证 chunks / edges / global_regions deep-equal
	var chunk_size: int = RtsHierarchicalChunk.CHUNK_SIZE
	var grid := RtsNavcellGrid.new(chunk_size * 2, chunk_size * 2)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")

	# 在两 chunk 边界附近放些不规则障碍(增加 region 数)
	for k in range(20):
		_block_cell(grid, 30 + k, 50, default_mask)
	for k in range(15):
		_block_cell(grid, 100, 30 + k, default_mask)

	var hp1 := RtsHierarchicalPathfinder.new()
	hp1.recompute(grid, registry.get_classes())

	var hp2 := RtsHierarchicalPathfinder.new()
	hp2.recompute(grid, registry.get_classes())

	# 两次 chunks regions / regions_id 应完全一致
	for cj in range(2):
		for ci in range(2):
			var ch1: RtsHierarchicalChunk = hp1.get_chunk(ci, cj, default_mask)
			var ch2: RtsHierarchicalChunk = hp2.get_chunk(ci, cj, default_mask)
			if ch1.regions_id != ch2.regions_id:
				_failures.append("determinism: chunk(%d,%d) regions_id differs: %s vs %s" % [
					ci, cj, str(ch1.regions_id), str(ch2.regions_id),
				])
			if ch1.regions != ch2.regions:
				_failures.append("determinism: chunk(%d,%d) regions array differs (size %d vs %d)" % [
					ci, cj, ch1.regions.size(), ch2.regions.size(),
				])

	# Global regions 一致
	var g1: Dictionary = hp1.get_global_regions(default_mask)
	var g2: Dictionary = hp2.get_global_regions(default_mask)
	if g1.size() != g2.size():
		_failures.append("determinism: global_regions size differs %d vs %d" % [g1.size(), g2.size()])
	for k in g1:
		if g1[k] != g2.get(k, -1):
			_failures.append("determinism: global_regions[%d] differs %d vs %d" % [k, g1[k], g2.get(k, -1)])

	# Edges 一致(Dictionary 比较复杂,逐 key 比 sorted neighbors)
	var e1: Dictionary = hp1.get_edges(default_mask)
	var e2: Dictionary = hp2.get_edges(default_mask)
	if e1.size() != e2.size():
		_failures.append("determinism: edges size differs %d vs %d" % [e1.size(), e2.size()])
	for k in e1:
		var n1: Array = e1[k]
		var n2: Array = e2.get(k, [])
		if n1 != n2:
			_failures.append("determinism: edges[%d] differs %s vs %s" % [k, str(n1), str(n2)])
