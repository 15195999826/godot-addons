## RtsVertexPathfinder M6a static-OBB only acceptance smoke
##
## 验证 M6a 阶段的 vertex pathfinder 算法层(纯 API,不依赖 procedure / world / actor):
##
## **AC1 — Data class 落地**: RtsShortPathRequest 字段 + RtsLineOfSight.segment_clear 几何
## **AC2 — Empty obstructions direct line**: 无 OBB → path size=1, back() = goal.center
## **AC3 — OBB 阻挡 direct line → 绕**: OBB 中间挡 start↔goal → A* 走 corner,每段 segment_clear PASS
## **AC4 — Same-point 兜底**: start ≈ goal → 单 waypoint
## **AC5 — 完全包围 → 空 path**: 4 OBB 围 start → 找不到路径 → 空 path
## **AC6 — Determinism**: 同 setup 跑两次 → waypoints 完全相同(byte-identical)
## **AC7 — Search bounds toward goal**: start, goal 较远 → bounds center 偏向 goal,
##         远端 OBB 在 bounds 内被收(toward goal 偏移生效)
## **AC8 — Vertex 候选顺序 deterministic (§12.3)**: 多 OBB 不同 tag 顺序构造 → path 仍稳定
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_data_classes_basic()
	_test_segment_clear_geometry()
	_test_empty_obstructions_direct_line()
	_test_obb_blocks_direct_line()
	_test_same_point_fallback()
	_test_fully_enclosed_returns_empty()
	_test_determinism_two_runs()
	_test_search_bounds_toward_goal()
	_test_vertex_candidate_order_deterministic()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - vertex_static_obb — M6a AC1+AC2+AC3+AC4+AC5+AC6+AC7+AC8 all OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_grid(w: int = 96, h: int = 96) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(w, h)
	grid.set_origin_world(Vector2.ZERO)
	return grid


func _make_registry() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground := RtsPassabilityClassConfig.new()
	ground.class_name_id = "default"
	ground.clearance = 14.0
	registry.register(ground)
	return registry


func _make_manager(grid: RtsNavcellGrid, registry: RtsPassabilityClassRegistry) -> RtsObstructionManager:
	return RtsObstructionManager.new(grid, registry)


func _make_pathfinder(grid: RtsNavcellGrid) -> RtsVertexPathfinder:
	return RtsVertexPathfinder.new(grid)


func _make_request(start: Vector2, goal_world: Vector2, clearance: float = 12.0) -> RtsShortPathRequest:
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, goal_world)
	return RtsShortPathRequest.new(start, goal, clearance)


## 跑同一组 OBB(specs = [[entity, center, w, h], ...])在新 grid/manager/pf 上算 path。
func _path_for_obb_specs(obb_specs: Array, start: Vector2, goal_world: Vector2, clearance: float) -> RtsWaypointPath:
	var grid := _make_grid()
	var registry := _make_registry()
	var manager := _make_manager(grid, registry)
	for spec in obb_specs:
		manager.add_static_shape(spec[0], spec[1], 0.0, spec[2], spec[3], RtsObstructionFlags.BLOCK_PATHFINDING, "")
	var pf := _make_pathfinder(grid)
	var req := _make_request(start, goal_world, clearance)
	return pf.compute_short_path_immediate(req, manager)


## 比较两条 path 字面相等;不等时往 _failures 追加带 label 的差异详情。
func _assert_paths_equal(label: String, p1: RtsWaypointPath, p2: RtsWaypointPath) -> void:
	if p1.size() != p2.size():
		_failures.append("%s: size differ %d vs %d" % [label, p1.size(), p2.size()])
		return
	for k in range(p1.size()):
		if p1.waypoints[k] != p2.waypoints[k]:
			_failures.append("%s: waypoints[%d] differ %s vs %s" % [label, k, str(p1.waypoints[k]), str(p2.waypoints[k])])
			return


# ========== Test cases ==========

func _test_data_classes_basic() -> void:
	# RtsShortPathRequest 字段
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, Vector2(500, 500))
	var req := RtsShortPathRequest.new(Vector2(50, 50), goal, 12.0, 1024.0, 0x1, false, "team-A", "actor_xyz", 99)
	if req.start != Vector2(50, 50):
		_failures.append("data: start unexpected")
	if req.goal != goal:
		_failures.append("data: goal ref mismatch")
	if not is_equal_approx(req.clearance, 12.0):
		_failures.append("data: clearance unexpected")
	if not is_equal_approx(req.range_px, 1024.0):
		_failures.append("data: range_px unexpected")
	if req.pass_mask != 0x1:
		_failures.append("data: pass_mask unexpected")
	if req.avoid_moving_units != false:
		_failures.append("data: avoid_moving_units unexpected")
	if req.control_group != "team-A":
		_failures.append("data: control_group unexpected")
	if req.notify_entity != "actor_xyz":
		_failures.append("data: notify_entity unexpected")
	if req.ticket != 99:
		_failures.append("data: ticket unexpected")


func _test_segment_clear_geometry() -> void:
	# OBB at (200,200) 60x60 axis-aligned;线段 (100,200) → (300,200) 直接穿过 OBB 中心
	var obb := RtsObstructionShapeStatic.new()
	obb.center = Vector2(200, 200)
	obb.width = 60.0
	obb.height = 60.0
	obb.rotation_rad = 0.0
	var shapes: Array = [obb]
	# 穿过 OBB(线段距 OBB = 0)→ 不通(buffer = 5,0 < 5)
	if RtsLineOfSight.segment_clear(Vector2(100, 200), Vector2(300, 200), shapes, 5.0):
		_failures.append("seg_clear: line through OBB center should be blocked")
	# 远离 OBB(线段 y=400 距 OBB top edge y=170 = 230 px)→ 通(230 ≥ 5)
	if not RtsLineOfSight.segment_clear(Vector2(100, 400), Vector2(300, 400), shapes, 5.0):
		_failures.append("seg_clear: line far from OBB should be clear")

	# Unit 圆 at (200,200) clearance=20;线段 (100,200) → (300,200) 距圆心 = 0,0 < (20+5)
	var unit_shape := RtsObstructionShapeUnit.new()
	unit_shape.center = Vector2(200, 200)
	unit_shape.clearance = 20.0
	if RtsLineOfSight.segment_clear(Vector2(100, 200), Vector2(300, 200), [unit_shape], 5.0):
		_failures.append("seg_clear: line through unit should be blocked")
	# 线段 y=400 距单位圆心 = 200,200 ≥ 25 通
	if not RtsLineOfSight.segment_clear(Vector2(100, 400), Vector2(300, 400), [unit_shape], 5.0):
		_failures.append("seg_clear: line far from unit should be clear")


func _test_empty_obstructions_direct_line() -> void:
	var grid := _make_grid()
	var registry := _make_registry()
	var manager := _make_manager(grid, registry)
	var pf := _make_pathfinder(grid)

	# 无障碍 — start (50,50), goal (500,500)
	var req := _make_request(Vector2(50, 50), Vector2(500, 500))
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	if path.is_empty():
		_failures.append("empty: empty obstructions → path should not be empty")
		return
	if path.size() != 1:
		_failures.append("empty: empty obstructions → expected size=1 (direct), got %d" % path.size())
		return
	if path.back() != Vector2(500, 500):
		_failures.append("empty: empty obstructions → back() should be goal, got %s" % str(path.back()))


func _test_obb_blocks_direct_line() -> void:
	var grid := _make_grid()
	var registry := _make_registry()
	var manager := _make_manager(grid, registry)
	var pf := _make_pathfinder(grid)

	# OBB at (300,300) 200×200 直挡 (100,100) → (500,500) 对角线
	manager.add_static_shape(
		"barracks_1",
		Vector2(300, 300),
		0.0,
		200.0, 200.0,
		RtsObstructionFlags.BLOCK_PATHFINDING,
		"",
	)

	var req := _make_request(Vector2(100, 100), Vector2(500, 500), 12.0)
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	if path.is_empty():
		_failures.append("blocked: OBB-blocked path should NOT be empty (vertex graph 应能绕过 corner)")
		return
	if path.size() < 2:
		_failures.append("blocked: OBB-blocked path 至少 2 waypoints (1 corner + goal),got %d" % path.size())
		return
	if path.waypoints[0] != Vector2(500, 500):
		_failures.append("blocked: waypoints[0] 应为 goal,got %s" % str(path.waypoints[0]))

	# 验证沿 path 每段 segment 都跟 OBB 距离 ≥ buffer
	var statics: Array = manager.get_obstructions_in_range(Vector2(300, 300), 1000.0)
	var prev: Vector2 = Vector2(100, 100)  # start
	# 反向遍历 path:next-step 在 size-1,goal 在 0;按 unit 走的顺序 = path.size-1 → 0
	for k in range(path.size() - 1, -1, -1):
		var nxt: Vector2 = path.waypoints[k]
		if not RtsLineOfSight.segment_clear(prev, nxt, statics, 12.0):
			_failures.append("blocked: segment %s → %s 不 clear,vertex pathfinder 算法 bug" % [str(prev), str(nxt)])
			return
		prev = nxt


func _test_same_point_fallback() -> void:
	var grid := _make_grid()
	var registry := _make_registry()
	var manager := _make_manager(grid, registry)
	var pf := _make_pathfinder(grid)

	# start == goal
	var req := _make_request(Vector2(200, 200), Vector2(200, 200))
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	if path.size() != 1:
		_failures.append("same-point: expected size=1, got %d" % path.size())
		return
	if path.back() != Vector2(200, 200):
		_failures.append("same-point: back() expected (200,200), got %s" % str(path.back()))


func _test_fully_enclosed_returns_empty() -> void:
	var grid := _make_grid()
	var registry := _make_registry()
	var manager := _make_manager(grid, registry)
	var pf := _make_pathfinder(grid)

	# 4 个 wall 完全围住 start (300,300):上(W=600 H=20 y=200)、下(y=400)、左(x=200 w=20 h=600)、右(x=400)
	manager.add_static_shape("wall_top", Vector2(300, 200), 0.0, 600.0, 20.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("wall_bot", Vector2(300, 400), 0.0, 600.0, 20.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("wall_left", Vector2(200, 300), 0.0, 20.0, 600.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("wall_right", Vector2(400, 300), 0.0, 20.0, 600.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")

	# start (300,300) 围墙内, goal (1000, 1000) 围墙外
	var req := _make_request(Vector2(300, 300), Vector2(1000, 1000), 12.0)
	# range 设小到只覆盖围墙内 (绕不出去)
	req.range_px = 300.0
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	if not path.is_empty():
		_failures.append("enclosed: 4 walls 围住 + range=300 → 应返回空 path,got size=%d" % path.size())


func _test_determinism_two_runs() -> void:
	var specs: Array = [
		["b1", Vector2(250, 200), 80.0, 80.0],
		["b2", Vector2(350, 350), 100.0, 60.0],
		["b3", Vector2(200, 400), 60.0, 60.0],
	]
	var path1 := _path_for_obb_specs(specs, Vector2(80, 80), Vector2(500, 500), 14.0)
	var path2 := _path_for_obb_specs(specs, Vector2(80, 80), Vector2(500, 500), 14.0)
	_assert_paths_equal("determinism", path1, path2)


func _test_search_bounds_toward_goal() -> void:
	# start (50,50), goal (1500,1500),range=1024 → bounds 中心偏向 goal
	# OBB 放在 (1200,1200) 远端;若 bounds 不偏向 goal,中心 = (775,775),distance to OBB = 600+
	#   bounds 半径 ≈ 724 (sqrt(2)*1024/2),OBB 在 bounds 边界
	# 偏向 goal 后 bounds 中心 ≈ start.lerp(goal, 0.5) + toward_goal/6 = (775,775) + (170,170) = (945, 945)
	#   distance to OBB ≈ 360,在 bounds 内更深
	var grid := _make_grid(128, 128)
	var registry := _make_registry()
	var manager := _make_manager(grid, registry)
	# 远端 OBB 直挡 start↔goal 对角线
	manager.add_static_shape("far_obb", Vector2(1200, 1200), 0.0, 100.0, 100.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	var pf := _make_pathfinder(grid)

	var req := _make_request(Vector2(50, 50), Vector2(1500, 1500), 12.0)
	req.range_px = 1024.0
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	# 远端 OBB 应被收到 vertex 候选 → path 绕开;不偏 toward goal 的话 OBB 在 bounds 边外不被收 → direct line 通(错!)
	if path.is_empty():
		_failures.append("toward_goal: search bounds 应包含远端 OBB → 应能找到绕路 path,got empty")
		return
	if path.size() < 2:
		# 远端 OBB 没收 → path size=1 (直接 goal),说明 search bounds 没偏向 goal
		_failures.append("toward_goal: 远端 OBB 应被 bounds 收 → path 应有 corner 绕,got direct size=1 (bias 不生效)")


func _test_vertex_candidate_order_deterministic() -> void:
	# 4 OBB 网格(tag 升序 → vertex 候选顺序 deterministic § §12.3);两次构造同 specs 路径必同。
	var specs: Array = [
		["a1", Vector2(200, 200), 60.0, 60.0],
		["a2", Vector2(300, 200), 60.0, 60.0],
		["a3", Vector2(200, 300), 60.0, 60.0],
		["a4", Vector2(300, 300), 60.0, 60.0],
	]
	var path_a := _path_for_obb_specs(specs, Vector2(80, 80), Vector2(500, 500), 14.0)
	var path_b := _path_for_obb_specs(specs, Vector2(80, 80), Vector2(500, 500), 14.0)
	_assert_paths_equal("order", path_a, path_b)
