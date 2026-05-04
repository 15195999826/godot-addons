## RtsLongPathfinder.compute_path_immediate basic acceptance smoke (M5 — AC1+AC2+AC3)
##
## 验证 LongPathfinder 朴素 A* 算法层(纯 API,不依赖 procedure / world / actor):
##
## **AC1 — Data class 落地**: RtsLongPathRequest / RtsWaypointPath / RtsPathGoal 实例化 + 字段
## **AC2 — A* heap 5 元组 lex compare 严格 deterministic**: 同 grid 跑两次 → path byte-identical
## **AC3 — Octile heuristic + integer cost**: HV 走 1 cell ≈ 65536, DIAG 走 1 cell ≈ 92682,比例 ≈ √2
##
## 测试 case:
##   - same-cell:start == goal 同 navcell → 单 waypoint = goal.center
##   - direct line:全可通 grid,start (10, 10) → goal (50, 50) → 走对角线 ~40 navcells
##   - 反方向:start (50, 50) → goal (10, 10) 也对称 ~40 cells
##   - 起点旁边的 next step:`path.back()` 是 start 的 8-邻居之一(对角线方向)
##   - 不可达:中间隔死 → 返回空 path
##   - determinism:同 grid + 同 start/goal 跑两次 → waypoints 完全相同
##   - integer cost ratio:_octile(0,0 → 10,0) 跟 _octile(0,0 → 10,10) 比对应 HV/DIAG 比例
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_data_classes_basic()
	_test_same_cell()
	_test_direct_line_passable()
	_test_path_back_is_neighbor()
	_test_unreachable_returns_empty()
	_test_determinism_two_runs()
	_test_integer_cost_ratio()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - long_pathfinder_basic — AC1+AC2+AC3 all OK")
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


func _make_grid(w: int, h: int) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(w, h)
	grid.set_origin_world(Vector2.ZERO)
	return grid


func _make_goal_point(world: Vector2) -> RtsPathGoal:
	return RtsPathGoal.new(RtsPathGoal.Type.POINT, world)


func _block_rect(grid: RtsNavcellGrid, i0: int, j0: int, i1: int, j1: int, mask: int) -> void:
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			grid.or_data(i, j, mask)


# ========== Test cases ==========

func _test_data_classes_basic() -> void:
	# RtsLongPathRequest 字段
	var goal := _make_goal_point(Vector2(100, 100))
	var req := RtsLongPathRequest.new(Vector2(50, 50), goal, 0x1, "actor_xyz", 42)
	if req.start != Vector2(50, 50) or req.goal != goal or req.pass_mask != 0x1 or req.notify_entity != "actor_xyz" or req.ticket != 42:
		_failures.append("data: RtsLongPathRequest fields unexpected")

	# RtsWaypointPath push/back/pop_back
	var path := RtsWaypointPath.new()
	if not path.is_empty() or path.size() != 0:
		_failures.append("data: WaypointPath new() should be empty size=0")
	path.push_back(Vector2(10, 10))
	path.push_back(Vector2(20, 20))
	if path.size() != 2 or path.back() != Vector2(20, 20):
		_failures.append("data: WaypointPath push/back failure")
	var popped := path.pop_back()
	if popped != Vector2(20, 20) or path.size() != 1 or path.back() != Vector2(10, 10):
		_failures.append("data: WaypointPath pop_back failure")
	path.clear()
	if not path.is_empty():
		_failures.append("data: WaypointPath clear() failure")

	# RtsPathGoal POINT distance + nearest
	var g := _make_goal_point(Vector2(100, 100))
	if absf(g.distance_to_point(Vector2(0, 0)) - 141.42) > 0.1:
		_failures.append("data: PathGoal distance_to_point POINT calc unexpected")
	if g.nearest_point_on_goal(Vector2(0, 0)) != Vector2(100, 100):
		_failures.append("data: PathGoal nearest_point_on_goal POINT should be center")


func _test_same_cell() -> void:
	var grid := _make_grid(96, 96)
	var registry := _make_registry_default_only()
	var mask: int = registry.get_mask("default")
	var lp := RtsLongPathfinder.new(grid)

	var start := grid.navcell_center_world(10, 10)
	var goal := _make_goal_point(grid.navcell_center_world(10, 10))
	var path := lp.compute_path_immediate(start, goal, mask)

	if path.size() != 1:
		_failures.append("same-cell: expected size=1, got %d" % path.size())
		return
	if path.back() != grid.navcell_center_world(10, 10):
		_failures.append("same-cell: back() expected goal center, got %s" % str(path.back()))


func _test_direct_line_passable() -> void:
	var grid := _make_grid(96, 96)
	var registry := _make_registry_default_only()
	var mask: int = registry.get_mask("default")
	var lp := RtsLongPathfinder.new(grid)

	var start := grid.navcell_center_world(10, 10)
	var goal := _make_goal_point(grid.navcell_center_world(50, 50))
	var path := lp.compute_path_immediate(start, goal, mask)

	# 对角线 8-邻居走 40 步(min(40, 40) = 40 个 DIAG step,0 个 HV)
	if path.size() != 40:
		_failures.append("direct: expected 40 waypoints (10→50 obj cells diagonal), got %d" % path.size())
		return
	# waypoints[0] = goal cell center;waypoints[size-1] = next step from start = (11, 11)
	if path.waypoints[0] != grid.navcell_center_world(50, 50):
		_failures.append("direct: waypoints[0] should be goal cell, got %s" % str(path.waypoints[0]))
	if path.back() != grid.navcell_center_world(11, 11):
		_failures.append("direct: back() should be (11, 11) center as next step from (10, 10), got %s" % str(path.back()))


func _test_path_back_is_neighbor() -> void:
	# start (50, 50) → goal (10, 30) — 反方向 + 非对角,验证 back() 是 start 的 8-邻居之一
	var grid := _make_grid(96, 96)
	var registry := _make_registry_default_only()
	var mask: int = registry.get_mask("default")
	var lp := RtsLongPathfinder.new(grid)

	var start := grid.navcell_center_world(50, 50)
	var goal := _make_goal_point(grid.navcell_center_world(10, 30))
	var path := lp.compute_path_immediate(start, goal, mask)

	if path.is_empty():
		_failures.append("back-neighbor: path empty (50→10,50→30 should be reachable)")
		return
	# next step 必须是 start 的 8-邻居之一(差 1 cell)
	var next_step: Vector2 = path.back()
	var dx := absf(next_step.x - start.x)
	var dy := absf(next_step.y - start.y)
	# 1 navcell = 32 px;邻居最大差 1.0 navcell = 32 px;严格 ≤ 32+1 px
	if dx > 33 or dy > 33:
		_failures.append("back-neighbor: back() (%s) not 8-neighbor of start (%s); dx=%f dy=%f" % [str(next_step), str(start), dx, dy])


func _test_unreachable_returns_empty() -> void:
	# 96×96 grid;j=48 行整个 horizontal wall 把 grid 切成上下两半,start (10, 10) goal (10, 80) 不可达
	var grid := _make_grid(96, 96)
	var registry := _make_registry_default_only()
	var mask: int = registry.get_mask("default")
	for i in range(96):
		grid.or_data(i, 48, mask)
	var lp := RtsLongPathfinder.new(grid)

	var start := grid.navcell_center_world(10, 10)
	var goal := _make_goal_point(grid.navcell_center_world(10, 80))
	var path := lp.compute_path_immediate(start, goal, mask)

	if not path.is_empty():
		_failures.append("unreachable: expected empty path (wall blocks j=48), got size=%d" % path.size())


func _test_determinism_two_runs() -> void:
	# 96×96 grid,加几个 obstacle,跑两次 → waypoints 完全相同
	var grid := _make_grid(96, 96)
	var registry := _make_registry_default_only()
	var mask: int = registry.get_mask("default")
	_block_rect(grid, 30, 30, 35, 35, mask)
	_block_rect(grid, 60, 60, 65, 65, mask)

	var lp1 := RtsLongPathfinder.new(grid)
	var lp2 := RtsLongPathfinder.new(grid)

	var start := grid.navcell_center_world(10, 10)
	var goal := _make_goal_point(grid.navcell_center_world(80, 80))
	var path1 := lp1.compute_path_immediate(start, goal, mask)
	var path2 := lp2.compute_path_immediate(start, goal, mask)

	if path1.size() != path2.size():
		_failures.append("determinism: size differs %d vs %d" % [path1.size(), path2.size()])
		return
	for k in range(path1.size()):
		if path1.waypoints[k] != path2.waypoints[k]:
			_failures.append("determinism: waypoints[%d] differs %s vs %s" % [k, str(path1.waypoints[k]), str(path2.waypoints[k])])
			return


func _test_integer_cost_ratio() -> void:
	# 验证 _octile static behavior(走 cost ratio):
	# - 10 cells HV: 10 × COST_HV = 655360
	# - 10 cells DIAG: 10 × COST_DIAG = 926820
	# 比例 = 926820 / 655360 ≈ 1.4142(√2)
	var hv_cost: int = 10 * RtsLongPathfinder.COST_HV
	var diag_cost: int = 10 * RtsLongPathfinder.COST_DIAG
	var ratio: float = float(diag_cost) / float(hv_cost)
	if absf(ratio - 1.4142) > 0.001:
		_failures.append("cost ratio: COST_DIAG/COST_HV expected ~1.4142(√2), got %f" % ratio)
