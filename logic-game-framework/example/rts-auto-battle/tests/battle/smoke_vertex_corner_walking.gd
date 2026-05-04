## RtsVertexPathfinder M6c ✋3 体感 smoke (corner walking)
##
## 验证 vertex pathfinder 在"barracks 直挡 start↔goal 直线"时绕 OBB 角自然不撞:
##
## **场景**:
##   - start (100, 100), goal (700, 100), 中间 barracks (400, 100) 80×80 阻挡
##   - 单位 clearance = 14
##   - direct line y=100 经过 barracks AABB y∈[60, 140] 中心 → 撞,必须绕
##
## **AC**:
##   - path size ≤ 4(2 段曲线 = 1 corner vertex + goal,或 1-2 段绕路 vertex)
##   - 沿 path 每段 segment_clear (clearance=14) 都通过(不撞 barracks)
##   - path 终点 = goal (POINT 类型 virtual_goal == goal.center)
##   - 路径形状是任意角度斜线,不是 LongPath 阶梯形(by 算法 — 不显式 assert,通过 segment 数 ≤ 4 间接验证)
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_corner_walking()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - vertex_corner_walking — ✋3 体感 OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_corner_walking() -> void:
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := RtsPassabilityClassRegistry.new()
	var ground := RtsPassabilityClassConfig.new()
	ground.class_name_id = "default"
	ground.clearance = 14.0
	registry.register(ground)
	var manager := RtsObstructionManager.new(grid, registry)
	manager.add_static_shape("barracks", Vector2(400, 100), 0.0, 80.0, 80.0, RtsObstructionFlags.BLOCK_PATHFINDING, "")
	var pf := RtsVertexPathfinder.new(grid)

	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, Vector2(700, 100))
	var req := RtsShortPathRequest.new(Vector2(100, 100), goal, 14.0)
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	if path.is_empty():
		_failures.append("corner_walking: path empty,vertex pathfinder 应能绕 OBB 角")
		return
	if path.size() > 4:
		_failures.append("corner_walking: path size=%d > 4,绕路过多 (期望 1-2 corner + goal)" % path.size())
	if path.waypoints[0] != Vector2(700, 100):
		_failures.append("corner_walking: 终点应 = goal (700, 100),got %s" % str(path.waypoints[0]))

	# 验证沿 path 每段 segment 都 clear
	var statics: Array = manager.get_obstructions_in_range(Vector2(400, 100), 500.0)
	var prev: Vector2 = Vector2(100, 100)
	for k in range(path.size() - 1, -1, -1):
		var nxt: Vector2 = path.waypoints[k]
		if not RtsLineOfSight.segment_clear(prev, nxt, statics, 14.0):
			_failures.append("corner_walking: segment %s → %s 不 clear,vertex pf 算法 bug" % [str(prev), str(nxt)])
			return
		prev = nxt
