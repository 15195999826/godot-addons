## RtsLongPathfinder determinism smoke (M5 — AC2 + spec §12.1 heap key)
##
## 验证 5 元组 (f, h, i, j, insertion_seq) lex compare 严格 deterministic — 同 grid 同
## start/goal 跑两次 byte-identical;并发不同 obstacle pattern 仍跨 2 run 一致。
##
## **AC2 严格定义** (data-structures.md §12.1):
##   1. f 主排序(总代价)
##   2. h 次排序(启发更小 = 离 goal 更近的先扩)
##   3. (i, j) 字典序(同 f h 时 navcell 坐标 deterministic)
##   4. insertion_seq(全部相同时插入序保最严格 deterministic)
##
## 测试 case:
##   - simple direct line:全可通 grid byte-identical
##   - obstacles in middle:绕障碍 byte-identical
##   - tight squeeze:1 navcell 缝隙强制 8-邻居 diagonal 选择 byte-identical
##   - 长路径:跨 grid 边对角 byte-identical
##   - canonicalize 路径 byte-identical (facade 整套)
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_simple_direct_line()
	_test_obstacles_in_middle()
	_test_tight_squeeze_diagonal()
	_test_long_path_corner_to_corner()
	_test_facade_canonicalize_byte_identical()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - long_pathfinder_determinism — AC2 5 元组 lex byte-identical")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_grid_with_blocks(blocks: Array) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var mask: int = registry.get_mask("default")
	for b in blocks:
		var rect: Array = b
		for j in range(rect[1], rect[3] + 1):
			for i in range(rect[0], rect[2] + 1):
				grid.or_data(i, j, mask)
	return grid


func _compare_paths(p1: RtsWaypointPath, p2: RtsWaypointPath, label: String) -> void:
	if p1.size() != p2.size():
		_failures.append("%s: path size differs %d vs %d" % [label, p1.size(), p2.size()])
		return
	for k in range(p1.size()):
		if p1.waypoints[k] != p2.waypoints[k]:
			_failures.append("%s: waypoints[%d] differs %s vs %s" % [label, k, str(p1.waypoints[k]), str(p2.waypoints[k])])
			return


func _bench_long_path(blocks: Array, start_ij: Vector2i, goal_ij: Vector2i) -> Array:
	var grid := _make_grid_with_blocks(blocks)
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var mask: int = registry.get_mask("default")

	var lp1 := RtsLongPathfinder.new(grid)
	var lp2 := RtsLongPathfinder.new(grid)
	var start := grid.navcell_center_world(start_ij.x, start_ij.y)
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, grid.navcell_center_world(goal_ij.x, goal_ij.y))
	var p1 := lp1.compute_path_immediate(start, goal, mask)

	# 第二次跑用新 goal 实例(避免 goal mutate 被共享)
	var goal2 := RtsPathGoal.new(RtsPathGoal.Type.POINT, grid.navcell_center_world(goal_ij.x, goal_ij.y))
	var p2 := lp2.compute_path_immediate(start, goal2, mask)
	return [p1, p2]


# ========== Test cases ==========

func _test_simple_direct_line() -> void:
	var paths := _bench_long_path([], Vector2i(10, 10), Vector2i(50, 50))
	_compare_paths(paths[0], paths[1], "direct-line")


func _test_obstacles_in_middle() -> void:
	# 几个不规则 obstacle 块,A* 必须绕开
	var blocks: Array = [
		[20, 20, 25, 25],
		[40, 40, 50, 45],
		[60, 30, 70, 35],
	]
	var paths := _bench_long_path(blocks, Vector2i(10, 10), Vector2i(85, 85))
	_compare_paths(paths[0], paths[1], "obstacles")


func _test_tight_squeeze_diagonal() -> void:
	# 仅留 (47, 50) 一个 navcell 通道,强制 unit 必走 diagonal 经过该缝
	var blocks: Array = []
	for j in range(96):
		if j == 50:
			continue
		blocks.append([47, j, 47, j])
	# blocks 是 1xN 列除了 (47, 50)
	var paths := _bench_long_path(blocks, Vector2i(20, 30), Vector2i(80, 70))
	_compare_paths(paths[0], paths[1], "tight-squeeze")


func _test_long_path_corner_to_corner() -> void:
	# 跨整 grid 对角 (1, 1) → (94, 94),走 ~93 个 diagonal step
	var paths := _bench_long_path([], Vector2i(1, 1), Vector2i(94, 94))
	if paths[0].size() < 90:
		_failures.append("long-path: expected ≥ 90 waypoints (corner-to-corner), got %d" % paths[0].size())
	_compare_paths(paths[0], paths[1], "corner-to-corner")


func _test_facade_canonicalize_byte_identical() -> void:
	# 整 facade 路径(canonicalize + A*)byte-identical
	var grid := _make_grid_with_blocks([[40, 40, 50, 50]])
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var mask: int = registry.get_mask("default")

	var hp1 := RtsHierarchicalPathfinder.new()
	hp1.recompute(grid, registry.get_classes())
	var lp1 := RtsLongPathfinder.new(grid)
	var facade1 := RtsPathfinderFacade.new(grid, hp1, lp1)

	var hp2 := RtsHierarchicalPathfinder.new()
	hp2.recompute(grid, registry.get_classes())
	var lp2 := RtsLongPathfinder.new(grid)
	var facade2 := RtsPathfinderFacade.new(grid, hp2, lp2)

	var start := grid.navcell_center_world(20, 20)
	var goal_world := grid.navcell_center_world(70, 70)
	var goal1 := RtsPathGoal.new(RtsPathGoal.Type.POINT, goal_world)
	var goal2 := RtsPathGoal.new(RtsPathGoal.Type.POINT, goal_world)
	var p1 := facade1.compute_path_immediate(start, goal1, mask)
	var p2 := facade2.compute_path_immediate(start, goal2, mask)
	_compare_paths(p1, p2, "facade-canonicalize")

	# Goal 字段也应 mutate 一致
	if goal1.center != goal2.center:
		_failures.append("facade-canonicalize: goal.center mutate differs %s vs %s" % [str(goal1.center), str(goal2.center)])
