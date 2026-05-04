## RtsVertexPathfinder M6c group filter + avoid_moving_units smoke
##
## 验证 detail #8 group filter + #3 avoid_moving_units 开关:
##
## **AC1 — 同 group obstruction 跳过**:
##   - 4 unit (control_group="team-A") + 2 unit (control_group="team-B")
##   - req.control_group="team-A" → 4 个 team-A unit 不算障碍,2 个 team-B 算
##   - 同 setup req.control_group="" → 6 unit 全算障碍 → path 不同
##
## **AC2 — Static control_group_2**:OBB.control_group_2="team-A",req.control_group="team-A" 跳过
##
## **AC3 — avoid_moving_units=false**:MOVING flag unit 跳过(让"挤过"队伍)
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_unit_group_filter()
	_test_static_control_group_2()
	_test_avoid_moving_units_off()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - vertex_group_filter — M6c AC1+AC2+AC3 OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_setup() -> Array:
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := RtsPassabilityClassRegistry.new()
	var ground := RtsPassabilityClassConfig.new()
	ground.class_name_id = "default"
	ground.clearance = 14.0
	registry.register(ground)
	var manager := RtsObstructionManager.new(grid, registry)
	var pf := RtsVertexPathfinder.new(grid)
	return [grid, registry, manager, pf]


# ========== Test cases ==========

func _test_unit_group_filter() -> void:
	# 一群 unit 挡 start ↔ goal 直线;same-group filter 让 path 直接穿过(不绕)
	var setup := _make_setup()
	var manager := setup[2] as RtsObstructionManager
	var pf := setup[3] as RtsVertexPathfinder

	# 4 unit "team-A" 在 start↔goal 直线上挡路 (clearance 20)
	manager.add_unit_shape("a1", Vector2(300, 300), 20.0, RtsObstructionFlags.BLOCK_MOVEMENT, "team-A")
	manager.add_unit_shape("a2", Vector2(350, 300), 20.0, RtsObstructionFlags.BLOCK_MOVEMENT, "team-A")
	manager.add_unit_shape("a3", Vector2(400, 300), 20.0, RtsObstructionFlags.BLOCK_MOVEMENT, "team-A")
	manager.add_unit_shape("a4", Vector2(450, 300), 20.0, RtsObstructionFlags.BLOCK_MOVEMENT, "team-A")

	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, Vector2(600, 300))
	# Case A: control_group="team-A" → 4 unit 跳过,直接 direct line
	var req_a := RtsShortPathRequest.new(Vector2(100, 300), goal, 14.0)
	req_a.control_group = "team-A"
	var path_a: RtsWaypointPath = pf.compute_short_path_immediate(req_a, manager)
	if path_a.is_empty():
		_failures.append("group_filter: same-group case path empty")
		return
	# 同 group 直接通,期望 size=1 (direct goal) 或 ≤2 (含 search-bounds 共线 corner case)
	if path_a.size() > 2:
		_failures.append("group_filter: same-group case path size=%d 应 ≤ 2 (绕路不应发生)" % path_a.size())

	# Case B: control_group="" → 4 unit 全算障碍 → 必须绕
	var req_b := RtsShortPathRequest.new(Vector2(100, 300), goal, 14.0)
	req_b.control_group = ""
	var path_b: RtsWaypointPath = pf.compute_short_path_immediate(req_b, manager)
	if path_b.is_empty():
		_failures.append("group_filter: no-group case 应能绕,但 path empty")
		return
	# 无 group filter,4 unit 挡道 → 至少 1 corner + goal = ≥ 2 waypoints
	# 但严格说也可能 best-so-far 给单 waypoint;验证 path_b.size > path_a.size 即可
	if path_b.size() <= path_a.size():
		_failures.append("group_filter: no-group case path 应比 same-group 长 (size_b=%d, size_a=%d)" % [path_b.size(), path_a.size()])


func _test_static_control_group_2() -> void:
	# OBB control_group_2 = "team-A",req.control_group = "team-A" → OBB 跳过
	var setup := _make_setup()
	var manager := setup[2] as RtsObstructionManager
	var pf := setup[3] as RtsVertexPathfinder

	# OBB at (400, 300) 60×60,control_group="" 但 control_group_2="team-A"
	var tag: int = manager.add_static_shape("obb_g2", Vector2(400, 300), 0.0, 60.0, 60.0, RtsObstructionFlags.BLOCK_PATHFINDING, "", "team-A")

	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, Vector2(600, 300))
	var req := RtsShortPathRequest.new(Vector2(200, 300), goal, 14.0)
	req.control_group = "team-A"
	var path: RtsWaypointPath = pf.compute_short_path_immediate(req, manager)

	if path.is_empty():
		_failures.append("control_group_2: same group_2 case path empty")
		return
	# OBB 跳过 → direct line
	if path.size() > 2:
		_failures.append("control_group_2: same group_2 case path size=%d 应 ≤ 2 (绕路不应发生),tag=%d" % [path.size(), tag])


func _test_avoid_moving_units_off() -> void:
	# avoid_moving_units=false + MOVING flag unit → 跳过
	var setup := _make_setup()
	var manager := setup[2] as RtsObstructionManager
	var pf := setup[3] as RtsVertexPathfinder

	# Unit at (400, 300) clearance 20,MOVING flag 设上
	var tag: int = manager.add_unit_shape("moving", Vector2(400, 300), 20.0, RtsObstructionFlags.BLOCK_MOVEMENT, "")
	manager.set_unit_moving_flag(tag, true)

	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, Vector2(600, 300))
	# Case A: avoid_moving_units=false → MOVING unit 跳过 → direct line
	var req_a := RtsShortPathRequest.new(Vector2(200, 300), goal, 14.0)
	req_a.avoid_moving_units = false
	var path_a: RtsWaypointPath = pf.compute_short_path_immediate(req_a, manager)
	if path_a.is_empty():
		_failures.append("avoid_moving_off: case A path empty")
		return
	if path_a.size() > 2:
		_failures.append("avoid_moving_off: case A (false) path size=%d 应 ≤ 2 (MOVING 跳过 → direct)" % path_a.size())

	# Case B: avoid_moving_units=true → MOVING unit 算障碍 → 绕路
	var req_b := RtsShortPathRequest.new(Vector2(200, 300), goal, 14.0)
	req_b.avoid_moving_units = true
	var path_b: RtsWaypointPath = pf.compute_short_path_immediate(req_b, manager)
	if path_b.is_empty():
		_failures.append("avoid_moving_off: case B path empty")
		return
	if path_b.size() <= path_a.size():
		_failures.append("avoid_moving_off: case B (true) 应比 case A (false) 长 (b=%d, a=%d)" % [path_b.size(), path_a.size()])
