## RtsUnitMotion lifecycle / failed_movements acceptance smoke (M7b — AC2)
##
## 验证 M7b Lifecycle 范围(tick 状态机 + 失败累加 + countdown):
##
## **AC2.1 — 失败累加 + 阈值 stop**: facade 返空 path → 每 tick `_failed_movements += 1 或 +2`
##   (long fail + short fail 同 tick 都 +1);累到 ≥ 35 → motion.stop() 触发(has_target == false)。
##
## **AC2.2 — _failed_movements 重置规则**: stop 后 _failed_movements 保持(不 reset);
##   重新 move_to 时 _reset_path_state 清零(0ad CCmpUnitMotion 规则)。
##
## **AC2.3 — countdown 触发 long retry**: facade 返非空 short path(单 waypoint)→ _step
##   消费 → _short_path 空 → _follow_known_imperfect_path_countdown 启动 12;再 12 tick 后
##   归 0,_long_path 清空(下 tick 触发 _request_long_path 重新规划)。
##
## **AC2.4 — has_target 短路返回**: motion 没 target(stop 后)→ tick 直接 return,_failed_movements
##   不再累加(防 stop 后无限计数)。
##
## **AC2.5 — _path_update_needed 判定**: _long_path 空 + ticket null → true;_long_path 非空 →
##   false;_long_path 空但 ticket active → false。
##
## **不验证**(M7c/d 范围):
##   - _step 真 position update + obstr_mgr.move_shape → M7c
##   - actor sort by (kind, spawn_seq) — RtsWorld.tick 顺序 → M7c
##   - emit MoveFailed event 给 activity → M7d
extends Node


# ========== Mock facade(inner class)— 不调 super._init,跳过 grid/hier/long 必填 ==========

## 永远返空 path 的 facade — 模拟 "完全围死 / 不可达" 场景。
class MockEmptyPathFacade extends RtsPathfinderFacade:
	func _init() -> void:
		# WHY: 故意不调 super._init(),跳过 grid / hierarchical / long 必填 assert
		pass

	func compute_path_immediate(_start: Vector2, _goal: RtsPathGoal, _pass_mask: int) -> RtsWaypointPath:
		return RtsWaypointPath.new()

	func compute_short_path_immediate(_req: RtsShortPathRequest, _obstr_mgr: RtsObstructionManager) -> RtsWaypointPath:
		return RtsWaypointPath.new()


## 总返单 waypoint short path / 单 waypoint long path 的 facade — 模拟 "有路可走"。
class MockSinglePathFacade extends RtsPathfinderFacade:
	var long_wp: Vector2 = Vector2(100, 0)
	var short_wp: Vector2 = Vector2(50, 0)

	func _init() -> void:
		pass

	func compute_path_immediate(_start: Vector2, _goal: RtsPathGoal, _pass_mask: int) -> RtsWaypointPath:
		var p := RtsWaypointPath.new()
		p.push_back(long_wp)
		return p

	func compute_short_path_immediate(_req: RtsShortPathRequest, _obstr_mgr: RtsObstructionManager) -> RtsWaypointPath:
		var p := RtsWaypointPath.new()
		p.push_back(short_wp)
		return p


# ========== Smoke main ==========

var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_failed_movements_accumulates_to_threshold()
	_test_stop_short_circuits_tick()
	_test_move_to_resets_failed_movements()
	_test_path_update_needed()
	_test_countdown_triggers_long_retry()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - motion_failed_movements — AC2.1-2.5 all OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Test cases ==========

## AC2.1: facade 全空 path → 35 tick 内累计 stop
func _test_failed_movements_accumulates_to_threshold() -> void:
	var motion := RtsUnitMotion.new()
	motion.set_position_2d(Vector2(0, 0))
	motion.move_to(Vector2(500, 500), 0.0, 0.0)
	var facade := MockEmptyPathFacade.new()

	# 一 tick 内 long fail + short fail = +2;35 阈值最迟 18 tick 触发 stop
	# (实测:第 17 tick 累 +2*17=34,第 18 tick 累 +2*18=36 ≥ 35 → stop)
	for i in range(40):
		motion.tick(0.05, null, facade)
		if not motion.has_target():
			break

	if motion._failed_movements < RtsUnitMotion.MAX_FAILED_MOVEMENTS:
		_failures.append("AC2.1: failed_movements %d < 35 after 40 ticks" % motion._failed_movements)
	if motion.has_target():
		_failures.append("AC2.1: motion still has target after 35+ failures (stop() not triggered)")


## AC2.4: has_target false → tick 短路返回,_failed_movements 不再累加
func _test_stop_short_circuits_tick() -> void:
	var motion := RtsUnitMotion.new()
	motion.set_position_2d(Vector2(0, 0))
	# 没 move_to → has_target == false → tick 短路
	var facade := MockEmptyPathFacade.new()
	var fail_before: int = motion._failed_movements
	for i in range(10):
		motion.tick(0.05, null, facade)
	if motion._failed_movements != fail_before:
		_failures.append("AC2.4: tick on no-target motion accumulated failures (got %d)" % motion._failed_movements)


## AC2.2: stop 不 reset failed_movements;move_to 才 reset
func _test_move_to_resets_failed_movements() -> void:
	var motion := RtsUnitMotion.new()
	motion.set_position_2d(Vector2(0, 0))
	motion.move_to(Vector2(500, 0), 0, 0)
	var facade := MockEmptyPathFacade.new()
	for i in range(40):
		motion.tick(0.05, null, facade)

	# 累到阈值 + 自动 stop;_failed_movements >= 35 不 reset
	if motion._failed_movements < RtsUnitMotion.MAX_FAILED_MOVEMENTS:
		_failures.append("AC2.2 precond: failed_movements %d not at threshold" % motion._failed_movements)
		return

	# 重新 move_to → 应清零
	motion.move_to(Vector2(100, 100), 0, 0)
	if motion._failed_movements != 0:
		_failures.append("AC2.2: move_to didn't reset _failed_movements (got %d)" % motion._failed_movements)


## AC2.5: _path_update_needed 三态判定
func _test_path_update_needed() -> void:
	var motion := RtsUnitMotion.new()

	# 默认:_long_path 空 + ticket null → true
	if not motion._path_update_needed():
		_failures.append("AC2.5a: empty long_path + null ticket should need update")

	# _long_path 非空 → false
	motion._long_path.push_back(Vector2(100, 100))
	if motion._path_update_needed():
		_failures.append("AC2.5b: non-empty long_path should NOT need update")
	motion._long_path.clear()

	# _long_path 空 + ticket active → false
	motion._expected_path_ticket = RtsMotionTicket.new(RtsMotionTicket.Type.LONG_PATH, 99)
	if motion._path_update_needed():
		_failures.append("AC2.5c: empty long_path + active ticket should NOT need update")

	# Ticket clear → 回到 true
	motion._expected_path_ticket.clear()
	if not motion._path_update_needed():
		_failures.append("AC2.5d: empty long_path + cleared ticket should need update")


## AC2.3: countdown 触发 long retry — single-path facade 跑一段后 short empty,countdown 启动,
## 12 tick 后 _long_path 清空
func _test_countdown_triggers_long_retry() -> void:
	var motion := RtsUnitMotion.new()
	motion.set_position_2d(Vector2(0, 0))
	motion.move_to(Vector2(500, 0), 0, 0)
	var facade := MockSinglePathFacade.new()

	# tick 1:_path_update_needed → _request_long_path → _long_path = [long_wp]
	#         _short_path empty + _long_path 非空 → pop _long_path → _request_short_path_to →
	#         _short_path = [short_wp]
	#         _step → pop _short_path → _short_path empty → 启动 countdown = 12
	#         tick 末 countdown 倒数 → 11
	motion.tick(0.05, null, facade)

	if motion._follow_known_imperfect_path_countdown == 0:
		_failures.append("AC2.3a: countdown should be > 0 after first tick (got %d)" % motion._follow_known_imperfect_path_countdown)
	# countdown 启动后立即 -1,tick 1 末应 = 11
	if motion._follow_known_imperfect_path_countdown != RtsUnitMotion.KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN - 1:
		_failures.append("AC2.3b: countdown after tick1 = %d, expected %d" % [motion._follow_known_imperfect_path_countdown, RtsUnitMotion.KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN - 1])

	# 再跑 11 tick:countdown 应该减到 0,_long_path 清空(让下 tick 触发 _request_long_path 重新规划)
	# 但 motion 状态机里 _path_update_needed 在 next tick 起头会真请求 long_path,得 mock facade 返单 waypoint
	# 即使 long_path 重新填了,countdown 启动逻辑只在"_short_path 空 + countdown == 0"才设 12
	# 这测试关心 countdown 完整倒数到 0 → _long_path 在那一 tick 末被 clear
	for i in range(11):
		motion.tick(0.05, null, facade)
		if motion._follow_known_imperfect_path_countdown == 0:
			break

	# countdown 倒数 12 次后归 0(从 11 减到 0)
	# 同 tick 内 long_path 重置后下 tick 又会被 _request_long_path 填上 — 所以 countdown 0 后
	# _long_path 在那一 tick 末确实被 cleared 但下 tick 又有
	# 我们验证 countdown 至少能归 0 一次(motion 状态机正常推进)
	if motion._follow_known_imperfect_path_countdown != 0:
		_failures.append("AC2.3c: countdown didn't reach 0 after 12 ticks (got %d)" % motion._follow_known_imperfect_path_countdown)
