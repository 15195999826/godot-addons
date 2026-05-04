## RtsHierarchicalPathfinder.make_goal_reachable_point acceptance smoke (M4b — AC3)
##
## 验证 M4b 公开查询 API 行为(纯 API 测试,不依赖完整 battle):
##
## **AC3.1 — 可达 (reachable=true)**:start 跟 goal 同 GlobalRegion → canonicalize 到 goal navcell 中心
## **AC3.2 — 不可达 (reachable=false)**:goal 在 impassable 区 / 不同 GlobalRegion → canonicalize 到
##                                       跟 start 同 GlobalRegion 的、离 goal 最近的 navcell 中心
## **AC3.3 — start 在 impassable 自动 fallback**:start 落在墙上 → 自动找最近 passable 当 start,
##                                                  再走可达判定
## **AC3.4 — is_goal_reachable_point**:不修改状态,纯查询;边界 case(start impassable 返 false)
##
## 不依赖 procedure / world / actor — 直接 NavcellGrid + Pathfinder API smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_reachable_canonicalize_to_goal()
	_test_unreachable_canonicalize_to_nearest_in_region()
	_test_goal_in_impassable_navcell()
	_test_start_in_impassable_navcell()
	_test_is_goal_reachable_point_pure_query()
	_test_split_by_wall_canonicalize_in_start_region()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - hierarchical_unreachable — AC3 + canonicalize all OK")
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


func _make_grid_with_origin(w: int, h: int) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(w, h)
	# origin = (0, 0) 让 navcell index = world / NAVCELL_SIZE_PX 直接对应
	grid.set_origin_world(Vector2.ZERO)
	return grid


func _block_rect(grid: RtsNavcellGrid, i0: int, j0: int, i1: int, j1: int, mask: int) -> void:
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			grid.or_data(i, j, mask)


# ========== Test cases ==========

func _test_reachable_canonicalize_to_goal() -> void:
	# 192×192 grid (2×2 chunks), 全可通; start (10*32, 10*32) world, goal (50*32, 50*32) world
	# 起手 navcell 中心 = (i+0.5)*32, 所以 navcell (10, 10) 中心 = (336, 336)
	var grid := _make_grid_with_origin(192, 192)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var start_world: Vector2 = grid.navcell_center_world(10, 10)
	var goal_world: Vector2 = grid.navcell_center_world(50, 50)
	var result: Dictionary = hp.make_goal_reachable_point(start_world, goal_world, default_mask)

	if not result.get("reachable", false):
		_failures.append("reachable: expected true (全可通) got false")
		return
	# canonicalized 应该 ≈ goal navcell (50,50) 中心
	var expected: Vector2 = grid.navcell_center_world(50, 50)
	var actual: Vector2 = result.get("canonicalized_world", Vector2.ZERO)
	if actual.distance_to(expected) > 0.01:
		_failures.append("reachable canonicalized: expected %s got %s" % [str(expected), str(actual)])


func _test_unreachable_canonicalize_to_nearest_in_region() -> void:
	# 192×192 grid; 在 (60..80, 60..80) 区域全墙 (5×5 cell 块); start (10, 10), goal 直接打到墙内
	var grid := _make_grid_with_origin(192, 192)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	_block_rect(grid, 60, 60, 80, 80, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var start_world: Vector2 = grid.navcell_center_world(10, 10)
	var goal_world: Vector2 = grid.navcell_center_world(70, 70)   # 墙内
	var result: Dictionary = hp.make_goal_reachable_point(start_world, goal_world, default_mask)

	if result.get("reachable", true):
		_failures.append("unreachable: goal in wall (70,70), expected reachable=false got true")
		return
	# canonicalized 应该是跟 start 同 GlobalRegion (= 全图唯一可通区) 的、离 goal 最近的 navcell
	# 墙边在 (60..80) 周围一圈,(70, 70) 最近可通是 (70, 59) 或 (59, 70) 之类
	# 因 ring scan 是 (di, dj) 字典序遍历,最先扫到的应是 di=-r 那一行 (j 较小)
	var canon: Vector2 = result.get("canonicalized_world", Vector2.ZERO)
	# 验:canon 对应的 navcell 必须 passable(不在墙内)
	var canon_ij: Vector2i = grid.nearest_navcell(canon)
	if not grid.is_passable(canon_ij.x, canon_ij.y, default_mask):
		_failures.append("unreachable: canonicalized %s (navcell %s) is impassable" % [str(canon), str(canon_ij)])
	# 验:canon 不等于原 goal(确实做了 canonicalize 不是 no-op)
	if canon.distance_to(goal_world) < 0.01:
		_failures.append("unreachable: canon == goal (no canonicalize)")
	# 验:canon 跟 start 同 GlobalRegion(关键 invariant)
	var canon_g: int = hp.get_global_region(canon_ij.x, canon_ij.y, default_mask)
	var start_g: int = hp.get_global_region(10, 10, default_mask)
	if canon_g == 0 or canon_g != start_g:
		_failures.append(
			"unreachable: canon (navcell %s, global=%d) should ∈ start_g (%d)" % [str(canon_ij), canon_g, start_g]
		)


func _test_goal_in_impassable_navcell() -> void:
	# 跟上 case 类似,goal 直接落在墙上 navcell 中心
	var grid := _make_grid_with_origin(192, 192)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	_block_rect(grid, 60, 60, 80, 80, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var start_world: Vector2 = grid.navcell_center_world(10, 10)
	# goal 落在墙正中心 navcell (70, 70)
	var goal_world: Vector2 = grid.navcell_center_world(70, 70)
	var result: Dictionary = hp.make_goal_reachable_point(start_world, goal_world, default_mask)

	if result.get("reachable", true):
		_failures.append("goal-in-wall: expected reachable=false")
	# canon 必须是 passable
	var canon: Vector2 = result.get("canonicalized_world", Vector2.ZERO)
	var canon_ij: Vector2i = grid.nearest_navcell(canon)
	if not grid.is_passable(canon_ij.x, canon_ij.y, default_mask):
		_failures.append("goal-in-wall: canon (navcell %s) is impassable" % str(canon_ij))


func _test_start_in_impassable_navcell() -> void:
	# start 落在墙上 → 自动 fallback 找最近 passable;然后 goal 在外面 passable → 应该 reachable=true
	var grid := _make_grid_with_origin(192, 192)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	_block_rect(grid, 60, 60, 80, 80, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var start_world: Vector2 = grid.navcell_center_world(70, 70)   # start 在墙正中
	var goal_world: Vector2 = grid.navcell_center_world(120, 120)  # goal passable
	var result: Dictionary = hp.make_goal_reachable_point(start_world, goal_world, default_mask)

	# start fallback 后跟 goal 都在唯一可通区(墙是孤岛在中间)→ reachable=true
	if not result.get("reachable", false):
		_failures.append("start-in-wall fallback: expected reachable=true got false")
	# canonicalized 应是 goal navcell (120, 120) 中心
	var canon: Vector2 = result.get("canonicalized_world", Vector2.ZERO)
	var expected: Vector2 = grid.navcell_center_world(120, 120)
	if canon.distance_to(expected) > 0.01:
		_failures.append("start-in-wall fallback: canon %s expected %s" % [str(canon), str(expected)])


func _test_is_goal_reachable_point_pure_query() -> void:
	var grid := _make_grid_with_origin(192, 192)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	_block_rect(grid, 60, 60, 80, 80, default_mask)

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var start_world: Vector2 = grid.navcell_center_world(10, 10)

	# goal 在同一可通区:reachable
	if not hp.is_goal_reachable_point(start_world, grid.navcell_center_world(150, 150), default_mask):
		_failures.append("pure query: open goal expected reachable")

	# goal 在墙内:not reachable(global region != start)
	if hp.is_goal_reachable_point(start_world, grid.navcell_center_world(70, 70), default_mask):
		_failures.append("pure query: wall-interior goal expected not reachable")

	# start 在墙内 → 直接返 false(不做 fallback)
	if hp.is_goal_reachable_point(grid.navcell_center_world(70, 70), grid.navcell_center_world(150, 150), default_mask):
		_failures.append("pure query: start-in-wall expected not reachable (no fallback)")


func _test_split_by_wall_canonicalize_in_start_region() -> void:
	# 192×192 grid;  纵向全墙 i=96 (chunks 0,0 和 1,0 之间);
	# start 在左半区 (50, 50);goal 在右半区 (130, 50)
	# 不可达 → canon 应在左半区(start global)边界附近,非右半区
	var grid := _make_grid_with_origin(192, 192)
	var registry := _make_registry_default_only()
	var default_mask: int = registry.get_mask("default")
	for j in range(192):
		grid.or_data(96, j, default_mask)
		grid.or_data(97, j, default_mask)   # 加宽墙避免 inflate ambiguity

	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())

	var start_world: Vector2 = grid.navcell_center_world(50, 50)
	var goal_world: Vector2 = grid.navcell_center_world(130, 50)
	var start_g: int = hp.get_global_region(50, 50, default_mask)
	var goal_g: int = hp.get_global_region(130, 50, default_mask)

	# 验:start / goal 在不同 GlobalRegion
	if start_g == goal_g or start_g == 0 or goal_g == 0:
		_failures.append("split-wall: expected start_g != goal_g (both non-zero), got start=%d goal=%d" % [start_g, goal_g])
		return

	var result: Dictionary = hp.make_goal_reachable_point(start_world, goal_world, default_mask)
	if result.get("reachable", true):
		_failures.append("split-wall: expected reachable=false")

	# canon 必须 ∈ start_g(左半区)
	var canon: Vector2 = result.get("canonicalized_world", Vector2.ZERO)
	var canon_ij: Vector2i = grid.nearest_navcell(canon)
	var canon_g: int = hp.get_global_region(canon_ij.x, canon_ij.y, default_mask)
	if canon_g != start_g:
		_failures.append(
			"split-wall: canon (navcell %s, global=%d) should ∈ start_g (%d)" % [str(canon_ij), canon_g, start_g]
		)
	# canon 应该在墙左边(i < 96),不能是右半区
	if canon_ij.x >= 96:
		_failures.append("split-wall: canon should be on left of wall (i < 96), got i=%d" % canon_ij.x)
