## RtsObstructionManager.rasterize Clearance + 外扩 acceptance smoke (M3.4 — AC1+AC2+AC3+AC8)
##
## 验证 M3 inflate 第二遍算法 + dirty 增量 + per-class 独立 + air class 不外扩。
##
## **核心计算**:
##   - default class clearance = 14 px → ceil(14/32)=1 cell → buffer_px = 1*32 = 32 px
##   - barracks @ (500, 500), 64×64 OBB, 无旋转 → AABB [468,532]×[468,532]
##   - 第一遍 cell-center-in-OBB: cells (15,15) (15,16) (16,15) (16,16) = 4
##   - 第二遍 inflate 距离 ≤ 32: 5×5 候选 [13..17]² 中 11 cell 新增标 (corner cells 距离 > 32 不标)
##
## **验证矩阵** (25 cells in [13..17]²):
##   - default blocked = {(15,15),(15,16),(16,15),(16,16),  # OBB 第一遍 4
##                        (14,14),(14,15),(14,16),(14,17),  # 左 + 左下 inflate
##                        (15,14),(15,17),(16,14),(16,17),  # 上下 inflate
##                        (17,14),(17,15),(17,16)}           # 右 + 右上 inflate
##                                                          → 共 15 cells
##   - default passable = 4 corners (13,13/13,17/17,17) + (13, 14..16) + (15..17, 13)
##                       + (17, 17 重复) → 共 10 cells (距离 > 32)
##   - 全 25 cells air passable (M3 _shape_blocks_class 对 air 全 false)
##
## AC1 — Rasterize inflate 第二遍工作 (default class blocked count = 15, expected 15)
## AC2 — Per-class clearance 独立 (air class 同 cells 全 passable, count = 0 blocked)
## AC3 — Dirty 增量正确 (rasterize_if_dirty 触发; remove + rasterize_if_dirty 后 cells 全 passable)
## AC8 — air class 外扩独立 (default + air rasterize 后 air bit cells 都 0)
##
## 不依赖 RtsBattleGrid / GameWorld / procedure — 纯数据 + manager smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_inflate_basic()
	_test_air_class_independent()
	_test_dirty_lifecycle()
	_test_rasterize_if_dirty_helper()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - clearance inflate — AC1+AC2+AC3+AC8 all OK (15 default-blocked + 25 air-passable + dirty cleanup)")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Test cases ==========

# AC1 — Inflate 第二遍工作: 15 cells in 5×5 范围标 default bit
func _test_inflate_basic() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(20, 20)  # 640×640 px
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	manager.add_static_shape(
		"barracks", Vector2(500.0, 500.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "0",
	)

	var default_pass: RtsPassabilityClassConfig = registry.get_pass_class("default")
	manager.rasterize(grid, default_pass, false)
	var default_mask: int = registry.get_mask("default")

	var blocked_set: Dictionary = _expected_default_blocked_cells()
	var unexpected: Array[String] = []
	var missed: Array[String] = []
	for j in range(13, 18):
		for i in range(13, 18):
			var key := Vector2i(i, j)
			var actual_blocked: bool = not grid.is_passable(i, j, default_mask)
			var expected_blocked: bool = blocked_set.has(key)
			if actual_blocked == expected_blocked:
				continue
			if actual_blocked:
				unexpected.append("(%d,%d) actual=blocked expected=passable" % [i, j])
			else:
				missed.append("(%d,%d) actual=passable expected=blocked" % [i, j])

	if not (missed.is_empty() and unexpected.is_empty()):
		_failures.append("AC1 inflate: %d cell(s) mismatch: missed=%s unexpected=%s" %
			[missed.size() + unexpected.size(), ",".join(missed), ",".join(unexpected)])

	var blocked_count: int = _count_blocked(grid, default_mask, 13, 18, 13, 18)
	if blocked_count != 15:
		_failures.append("AC1 inflate: blocked count expected 15, got %d" % blocked_count)


# AC2 + AC8 — air class 同 cells 全 passable (M3 affects_pathfinding=false 对 air 全跳过 inflate)
func _test_air_class_independent() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(20, 20)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	manager.add_static_shape(
		"barracks", Vector2(500.0, 500.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "0",
	)

	manager.rasterize(grid, registry.get_pass_class("default"), false)
	manager.rasterize(grid, registry.get_pass_class("air"), false)

	var air_blocked_count: int = _count_blocked(grid, registry.get_mask("air"), 13, 18, 13, 18)
	if air_blocked_count != 0:
		_failures.append("AC2/AC8 air class: %d cell(s) air-blocked, expected 0 (air affects_pathfinding=false)" % air_blocked_count)


# AC3 — Dirty 增量正确: 加 + remove 后 cells 全 passable
func _test_dirty_lifecycle() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(20, 20)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)
	var default_mask: int = registry.get_mask("default")

	var tag: int = manager.add_static_shape(
		"barracks_remove_test", Vector2(500.0, 500.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "0",
	)
	manager.rasterize_if_dirty(grid, registry)
	grid.clear_dirty()

	var blocked_after_add: int = _count_blocked(grid, default_mask, 13, 18, 13, 18)
	if blocked_after_add != 15:
		_failures.append("AC3 add: blocked after add+rasterize_if_dirty expected 15, got %d" % blocked_after_add)

	manager.remove_shape(tag)
	manager.rasterize_if_dirty(grid, registry)

	var blocked_after_remove: int = _count_blocked(grid, default_mask, 13, 18, 13, 18)
	if blocked_after_remove != 0:
		_failures.append("AC3 remove: blocked after remove+rasterize_if_dirty expected 0, got %d" % blocked_after_remove)


# rasterize_if_dirty 空 dirty 时返 false (noop)
func _test_rasterize_if_dirty_helper() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(10, 10)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	# 无 dirty cells → rasterize_if_dirty 应返 false
	var noop_result: bool = manager.rasterize_if_dirty(grid, registry)
	if noop_result:
		_failures.append("rasterize_if_dirty noop: expected false, got true (no dirty cells)")

	# add shape → dirty → rasterize_if_dirty 应返 true
	manager.add_static_shape(
		"test_shape", Vector2(160.0, 160.0), 0.0, 32.0, 32.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "0",
	)
	var triggered_result: bool = manager.rasterize_if_dirty(grid, registry)
	if not triggered_result:
		_failures.append("rasterize_if_dirty triggered: expected true after add_static_shape, got false")


# ========== Helper ==========

func _build_registry() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var air_cfg := RtsPassabilityClassConfig.new()
	air_cfg.class_name_id = "air"
	air_cfg.clearance = 8.0
	air_cfg.affects_pathfinding = false  # M3 wiring: BLOCK_PATHFINDING shape 不写 air bit
	registry.register(air_cfg)
	return registry


# Count default-blocked cells in [i_lo, i_hi) × [j_lo, j_hi).
func _count_blocked(grid: RtsNavcellGrid, mask: int, i_lo: int, i_hi: int, j_lo: int, j_hi: int) -> int:
	var count: int = 0
	for j in range(j_lo, j_hi):
		for i in range(i_lo, i_hi):
			if not grid.is_passable(i, j, mask):
				count += 1
	return count


# 5×5 cell range [13..17]² 中 default-blocked 的 cells (15 个)。
# 见文件头部注释的精确几何推导:
#   OBB AABB [468,532]² → cell-center-in-OBB (i ∈ {15,16}, j ∈ {15,16}) = 4 cells
#   inflate buffer 32 px → AABB [436,564]² 5×5 cells, 距离 ≤ 32 标 11 个 (corner cells 距离 > 32)
func _expected_default_blocked_cells() -> Dictionary:
	var s: Dictionary = {}
	# 第一遍 OBB cells
	s[Vector2i(15, 15)] = true
	s[Vector2i(15, 16)] = true
	s[Vector2i(16, 15)] = true
	s[Vector2i(16, 16)] = true
	# 第二遍 inflate (距离 ≤ 32 的边缘 cells)
	s[Vector2i(14, 14)] = true  # dist 5.66
	s[Vector2i(14, 15)] = true  # dist 4
	s[Vector2i(14, 16)] = true  # dist 4
	s[Vector2i(14, 17)] = true  # dist 28.28
	s[Vector2i(15, 14)] = true  # dist 4
	s[Vector2i(15, 17)] = true  # dist 28
	s[Vector2i(16, 14)] = true  # dist 4
	s[Vector2i(16, 17)] = true  # dist 28
	s[Vector2i(17, 14)] = true  # dist 28.28
	s[Vector2i(17, 15)] = true  # dist 28
	s[Vector2i(17, 16)] = true  # dist 28
	return s
