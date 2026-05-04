## RtsVertexPathfinder M6a prototype (独立可视化验证 scene)
##
## **本 scene 不进 manifest / 不进 production**。M6a 阶段独立验证算法正确性 — F6 跑或 headless
## 跑都打印 path 经过的 vertex 列表 + 简单 PASS/FAIL 判断,人工肉眼审一下"路径合理"。
##
## **R6 风险缓解(spec §M6 残余风险)**:M6c sub-phase 末必须删除本 scene + .gd + 配套 .tscn,
## 避免"prototype 简化版 vs production 完整版"双实现漂移。
##
## **跟 smoke_vertex_static_obb 区别**:
##   - smoke 是回归 gate,小规模 case + assert,manifest 进 rts/pathfinding;
##   - prototype 是 explore tool,几个"interesting"几何场景 + 打印 path 让人看,manifest 不进
##
## **Setup**:128×128 grid,5 个 OBB(barracks 风格),start (50,50) → goal (1500,1500),clearance 14。
## 期望:vertex pathfinder 输出绕开 OBB 的 path。
extends Node


func _ready() -> void:
	GameWorld.init()

	var grid := RtsNavcellGrid.new(128, 128)
	grid.set_origin_world(Vector2.ZERO)

	var registry := RtsPassabilityClassRegistry.new()
	var ground := RtsPassabilityClassConfig.new()
	ground.class_name_id = "default"
	ground.clearance = 14.0
	registry.register(ground)

	var manager := RtsObstructionManager.new(grid, registry)
	manager.add_static_shape("barracks_1", Vector2(400, 200), 0.0, 200.0, 100.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("barracks_2", Vector2(700, 500), 0.0, 150.0, 200.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("barracks_3", Vector2(300, 800), 0.0, 250.0, 100.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("tower_1", Vector2(1000, 900), 0.0, 80.0, 80.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	manager.add_static_shape("tower_2", Vector2(1200, 600), 0.0, 80.0, 80.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")

	var pf := RtsVertexPathfinder.new(grid)
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, Vector2(1500, 1500))
	var req := RtsShortPathRequest.new(Vector2(50, 50), goal, 14.0)

	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	print("=== RtsVertexPathfinder M6a Prototype ===")
	print("Setup: 128×128 grid, 5 OBB (3 barracks + 2 tower)")
	print("start = (50, 50)  goal = (1500, 1500)  clearance = 14")
	print("Path size = %d" % path.size())
	if path.is_empty():
		print("=== PATH EMPTY (无可达路径) ===")
		printerr("SMOKE_TEST_RESULT: FAIL - prototype 找不到路径")
		print("SMOKE_TEST_RESULT: FAIL - prototype 找不到路径")
		get_tree().quit(1)
		return

	# 反向遍历(unit 走的顺序):next-step 在 size-1,goal 在 0
	var unit_pos: Vector2 = Vector2(50, 50)
	print("Path waypoints (按 unit 走的顺序 = next-step → goal):")
	for k in range(path.size() - 1, -1, -1):
		var wp: Vector2 = path.waypoints[k]
		var dist: float = unit_pos.distance_to(wp)
		print("  step %d: (%.1f, %.1f)  segment_len = %.1f" % [path.size() - 1 - k, wp.x, wp.y, dist])
		unit_pos = wp

	# 验证每段 segment 都 clear
	var statics: Array = manager.get_obstructions_in_range(Vector2(800, 700), 2000.0)
	var prev: Vector2 = Vector2(50, 50)
	var all_clear: bool = true
	for k in range(path.size() - 1, -1, -1):
		var nxt: Vector2 = path.waypoints[k]
		if not RtsLineOfSight.segment_clear(prev, nxt, statics, 14.0):
			print("  ⚠ segment %s → %s 不 clear (擦了某 OBB buffer)" % [str(prev), str(nxt)])
			all_clear = false
		prev = nxt

	if all_clear:
		print("=== ALL SEGMENTS CLEAR (clearance=14) ===")
		print("SMOKE_TEST_RESULT: PASS - prototype 路径几何 OK")
		get_tree().quit(0)
	else:
		printerr("SMOKE_TEST_RESULT: FAIL - prototype 路径有 segment 擦 OBB")
		print("SMOKE_TEST_RESULT: FAIL - prototype 路径有 segment 擦 OBB")
		get_tree().quit(1)
