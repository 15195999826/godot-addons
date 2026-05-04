## RtsUnitMotion path storage acceptance smoke (M7a — AC1)
##
## 验证 M7a Path Storage 范围(纯 data class API,不接 production):
##
## **AC1.1 — RtsMoveRequest factory + 字段**: to_point / to_entity / with_offset 工厂
##   - to_point 设 type=POINT + position + min/max_range
##   - to_entity 设 type=ENTITY + entity_id + min/max_range(eid 必须非空,assert_crash 验证)
##   - with_offset 设 type=OFFSET + entity_id + position(本地 offset)
##
## **AC1.2 — RtsMotionTicket 字段 + 状态切换**: is_active / clear
##   - new(SHORT_PATH, 0) 默认 is_active() == false(ticket = 0)
##   - new(LONG_PATH, 5) is_active() == true,type 字段正确
##   - clear() 后 is_active() == false
##
## **AC1.3 — RtsUnitMotion 雏形字段 + 公开 API**:
##   - 新建 motion 默认 has_target() == false(_move_request type=NONE)
##   - move_to(pos, 0, 100) 后 has_target() == true,_move_request.type == POINT
##   - move_to_entity("enemy_1", 0, 50) 后 has_target() == true,type == ENTITY
##   - move_with_offset("leader_1", Vector2(10,0)) 后 has_target() == true,type == OFFSET
##   - stop() 后 has_target() == false,_short_path 和 _long_path 全空
##
## **AC1.4 — get/set_clearance 语义**:
##   - 默认 _clearance = 14.0(_init template default)
##   - set_clearance(20.0) 后 get_clearance() == 20.0
##   - set_clearance(0.0) / set_clearance(-1.0) 触发 assert_crash(本 smoke 不验,assert_crash 直接 quit)
##
## **AC1.5 — move_to_* 调用清 path 状态**:
##   - 创建 motion + 手动塞 _long_path / _short_path 几个 waypoint(模拟"上次寻路有结果")
##   - 调 move_to() / stop() / move_to_entity() 后双 path 全清 + _failed_movements = 0 + countdown = 0
##
## **不验证**(M7b/c/d 范围):
##   - tick() 状态机 → M7b
##   - _step() 实际位置 update + obstr_mgr 同步 → M7c
##   - activity 集成 + MoveFailed 事件 → M7d
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_move_request_factory()
	_test_motion_ticket()
	_test_motion_default_state()
	_test_move_to_sets_target()
	_test_move_to_entity_sets_target()
	_test_move_with_offset_sets_target()
	_test_stop_clears_target()
	_test_clearance_get_set()
	_test_move_to_resets_path_state()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - motion_path_storage — AC1.1-AC1.5 all OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Test cases ==========

func _test_move_request_factory() -> void:
	# to_point
	var p := RtsMoveRequest.to_point(Vector2(100, 200), 5.0, 50.0)
	if p.type != RtsMoveRequest.Type.POINT:
		_failures.append("move_request: to_point type wrong (expected POINT)")
	if p.position != Vector2(100, 200):
		_failures.append("move_request: to_point position %s != (100,200)" % p.position)
	if not is_equal_approx(p.min_range, 5.0) or not is_equal_approx(p.max_range, 50.0):
		_failures.append("move_request: to_point ranges (%f,%f) != (5,50)" % [p.min_range, p.max_range])
	if p.entity_id != "":
		_failures.append("move_request: to_point entity_id should be '', got %s" % p.entity_id)

	# to_entity
	var e := RtsMoveRequest.to_entity("enemy_1", 0.0, 100.0)
	if e.type != RtsMoveRequest.Type.ENTITY:
		_failures.append("move_request: to_entity type wrong")
	if e.entity_id != "enemy_1":
		_failures.append("move_request: to_entity eid '%s' != 'enemy_1'" % e.entity_id)
	if not is_equal_approx(e.max_range, 100.0):
		_failures.append("move_request: to_entity max_range %f != 100" % e.max_range)

	# with_offset
	var o := RtsMoveRequest.with_offset("leader_1", Vector2(10, 5))
	if o.type != RtsMoveRequest.Type.OFFSET:
		_failures.append("move_request: with_offset type wrong")
	if o.entity_id != "leader_1":
		_failures.append("move_request: with_offset eid wrong")
	if o.position != Vector2(10, 5):
		_failures.append("move_request: with_offset position %s != (10,5)" % o.position)

	# default _init NONE
	var n := RtsMoveRequest.new()
	if n.type != RtsMoveRequest.Type.NONE:
		_failures.append("move_request: default new() type %d != NONE" % n.type)


func _test_motion_ticket() -> void:
	# default new — ticket=0,is_active=false
	var t0 := RtsMotionTicket.new()
	if t0.is_active():
		_failures.append("ticket: default new() is_active should be false")
	if t0.type != RtsMotionTicket.Type.SHORT_PATH:
		_failures.append("ticket: default type %d != SHORT_PATH" % t0.type)

	# active long path ticket
	var t1 := RtsMotionTicket.new(RtsMotionTicket.Type.LONG_PATH, 5)
	if not t1.is_active():
		_failures.append("ticket: ticket=5 is_active should be true")
	if t1.type != RtsMotionTicket.Type.LONG_PATH:
		_failures.append("ticket: type %d != LONG_PATH" % t1.type)
	if t1.ticket != 5:
		_failures.append("ticket: ticket field %d != 5" % t1.ticket)

	# clear
	t1.clear()
	if t1.is_active():
		_failures.append("ticket: after clear() is_active should be false")
	if t1.ticket != 0:
		_failures.append("ticket: after clear() ticket %d != 0" % t1.ticket)


func _test_motion_default_state() -> void:
	var motion := RtsUnitMotion.new()

	if motion.has_target():
		_failures.append("motion: default has_target should be false")
	if motion._move_request == null:
		_failures.append("motion: default _move_request should not be null")
	if motion._move_request.type != RtsMoveRequest.Type.NONE:
		_failures.append("motion: default _move_request.type %d != NONE" % motion._move_request.type)
	if motion._long_path == null or motion._short_path == null:
		_failures.append("motion: default _long_path / _short_path should not be null")
	if not motion._long_path.is_empty() or not motion._short_path.is_empty():
		_failures.append("motion: default paths should be empty")
	if not is_equal_approx(motion.get_clearance(), 14.0):
		_failures.append("motion: default clearance %f != 14.0" % motion.get_clearance())


func _test_move_to_sets_target() -> void:
	var motion := RtsUnitMotion.new()
	motion.move_to(Vector2(500, 300), 0.0, 32.0)
	if not motion.has_target():
		_failures.append("move_to: has_target should be true after move_to")
	if motion._move_request.type != RtsMoveRequest.Type.POINT:
		_failures.append("move_to: type %d != POINT" % motion._move_request.type)
	if motion._move_request.position != Vector2(500, 300):
		_failures.append("move_to: position wrong")


func _test_move_to_entity_sets_target() -> void:
	var motion := RtsUnitMotion.new()
	motion.move_to_entity("target_actor_42", 5.0, 64.0)
	if not motion.has_target():
		_failures.append("move_to_entity: has_target should be true")
	if motion._move_request.type != RtsMoveRequest.Type.ENTITY:
		_failures.append("move_to_entity: type %d != ENTITY" % motion._move_request.type)
	if motion._move_request.entity_id != "target_actor_42":
		_failures.append("move_to_entity: entity_id '%s' != 'target_actor_42'" % motion._move_request.entity_id)


func _test_move_with_offset_sets_target() -> void:
	var motion := RtsUnitMotion.new()
	motion.move_with_offset("leader_actor", Vector2(20, -10))
	if not motion.has_target():
		_failures.append("move_with_offset: has_target should be true")
	if motion._move_request.type != RtsMoveRequest.Type.OFFSET:
		_failures.append("move_with_offset: type %d != OFFSET" % motion._move_request.type)
	if motion._move_request.entity_id != "leader_actor":
		_failures.append("move_with_offset: entity_id wrong")
	if motion._move_request.position != Vector2(20, -10):
		_failures.append("move_with_offset: offset position wrong")


func _test_stop_clears_target() -> void:
	var motion := RtsUnitMotion.new()
	motion.move_to(Vector2(100, 100), 0.0, 10.0)
	if not motion.has_target():
		_failures.append("stop: precondition failed (move_to didn't set target)")
		return

	motion.stop()
	if motion.has_target():
		_failures.append("stop: has_target should be false after stop")
	if motion._move_request.type != RtsMoveRequest.Type.NONE:
		_failures.append("stop: _move_request.type %d != NONE" % motion._move_request.type)
	if not motion._long_path.is_empty() or not motion._short_path.is_empty():
		_failures.append("stop: paths should be empty after stop")


func _test_clearance_get_set() -> void:
	var motion := RtsUnitMotion.new()
	if not is_equal_approx(motion.get_clearance(), 14.0):
		_failures.append("clearance: default %f != 14.0" % motion.get_clearance())

	motion.set_clearance(20.0)
	if not is_equal_approx(motion.get_clearance(), 20.0):
		_failures.append("clearance: after set 20 got %f" % motion.get_clearance())

	motion.set_clearance(8.5)
	if not is_equal_approx(motion.get_clearance(), 8.5):
		_failures.append("clearance: after set 8.5 got %f" % motion.get_clearance())


func _test_move_to_resets_path_state() -> void:
	var motion := RtsUnitMotion.new()

	# 模拟 motion 已有上次寻路结果(M7b/c 真实 tick 状态机会写),手工塞数据测 reset 行为
	motion._long_path.push_back(Vector2(100, 100))
	motion._long_path.push_back(Vector2(200, 100))
	motion._short_path.push_back(Vector2(50, 50))
	motion._failed_movements = 17
	motion._follow_known_imperfect_path_countdown = 8
	motion._expected_path_ticket = RtsMotionTicket.new(RtsMotionTicket.Type.LONG_PATH, 99)

	# move_to 必须清光所有 path 状态
	motion.move_to(Vector2(800, 600), 0.0, 32.0)
	if not motion._long_path.is_empty():
		_failures.append("reset: move_to should clear _long_path")
	if not motion._short_path.is_empty():
		_failures.append("reset: move_to should clear _short_path")
	if motion._failed_movements != 0:
		_failures.append("reset: move_to should reset _failed_movements (got %d)" % motion._failed_movements)
	if motion._follow_known_imperfect_path_countdown != 0:
		_failures.append("reset: move_to should reset countdown (got %d)" % motion._follow_known_imperfect_path_countdown)
	if motion._expected_path_ticket.is_active():
		_failures.append("reset: move_to should clear ticket (still active)")

	# 再用 stop() 验证清 path
	motion._long_path.push_back(Vector2(1, 1))
	motion._short_path.push_back(Vector2(2, 2))
	motion.stop()
	if not motion._long_path.is_empty() or not motion._short_path.is_empty():
		_failures.append("reset: stop should clear paths")
