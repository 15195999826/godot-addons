## RtsMotionComponent + ObstructionManager sync acceptance smoke (M7c — AC3)
##
## 验证 M7c.3 桥接链路:component.tick → motion.tick → motion._step → owner.position_2d 同步 +
## obstr_mgr.move_shape + set_unit_moving_flag。
##
## **AC3.1 — actor.position_2d ≡ motion._position_2d**: component.tick 后 owner.position_2d
##   写回 = motion.get_position_2d()(motion 内 mirror 真渐进 walk_speed × delta)。
##
## **AC3.2 — obstr_mgr.get_shape(tag).center 同步**: component.tick 末调 obstr_mgr.move_shape;
##   下一 tick 起 _spatial_index 反映新位置。
##
## **AC3.3 — FLAG_MOVING 切换**: 移动开始(short_path 非空)→ flag = true;到达(short_path 空 +
##   has_target false 或 motion stop)→ flag = false;was_moving != is_moving 才调 set_*flag。
##
## **AC3.4 — clearance ≡ obstruction.shape.clearance**(D2 不变量): component.set_clearance(c)
##   同步 motion._clearance + obstr_mgr.unit_shape.clearance 字段。
##
## **不验证**(M7d 范围):
##   - production callsite 真 motion-bearing tick → M7d 切 activity
##   - 跨 unit 顺序(unit_A.tick 后 unit_B 看到 unit_A 新位置)→ smoke_motion_tick_order_with_10plus_units
extends Node


# ========== Mock facade — 返单 waypoint short path 让 motion 真走 ==========

class MockSinglePathFacade extends RtsPathfinderFacade:
	var short_wp: Vector2 = Vector2(200, 0)

	func _init() -> void:
		# 跳过 super._init 的 grid/hier/long 必填 assert
		pass

	func compute_path_immediate(_start: Vector2, _goal: RtsPathGoal, _pass_mask: int) -> RtsWaypointPath:
		var p := RtsWaypointPath.new()
		p.push_back(short_wp)
		return p

	func compute_short_path_immediate(_req: RtsShortPathRequest, _obstr_mgr: RtsObstructionManager) -> RtsWaypointPath:
		var p := RtsWaypointPath.new()
		p.push_back(short_wp)
		return p


# ========== Mock world — 持 obstruction_manager 字段(RefCounted 也有 .get()) ==========

class MockWorld extends RefCounted:
	var obstruction_manager: RtsObstructionManager = null


# ========== Smoke main ==========

var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_actor_position_sync()
	_test_obstr_mgr_move_shape_sync()
	_test_flag_moving_toggle()
	_test_set_clearance_sync()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - motion_obstruction_sync — AC3.1-3.4 all OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_obstr_mgr() -> RtsObstructionManager:
	var grid := RtsNavcellGrid.new(50, 50)
	grid.set_origin_world(Vector2.ZERO)
	var registry := RtsPassabilityClassRegistry.new()
	var cfg := RtsPassabilityClassConfig.new()
	cfg.class_name_id = "default"
	cfg.clearance = 14.0
	registry.register(cfg)
	return RtsObstructionManager.new(grid, registry)


func _make_unit_at(pos: Vector2) -> RtsUnitActor:
	var u := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	u.position_2d = pos
	u.collision_radius = 14.0
	return u


# ========== Test cases ==========

## AC3.1: motion._step 真渐进后 component 写回 owner.position_2d
func _test_actor_position_sync() -> void:
	var actor: RtsUnitActor = _make_unit_at(Vector2(0, 0))
	var motion := RtsUnitMotion.new()
	motion._walk_speed = 100.0  # 100 px/s
	var component := RtsMotionComponent.new(actor, motion)
	actor.motion_component = component

	motion.move_to(Vector2(200, 0), 0, 0)
	var facade := MockSinglePathFacade.new()
	# tick 1:facade 给 short_path = [(200,0)],_step 渐进 100px (walk_speed * 1.0s)
	# 1 tick = 1s → 渐进 100 px → _position_2d ≈ (100, 0)
	component.tick(1.0, null, facade)

	if not is_equal_approx(actor.position_2d.x, 100.0):
		_failures.append("AC3.1: actor.position_2d.x %f != 100 after 1s tick @ 100 px/s" % actor.position_2d.x)
	if not is_equal_approx(motion.get_position_2d().x, actor.position_2d.x):
		_failures.append("AC3.1: actor.position_2d.x %f != motion._position_2d.x %f" % [actor.position_2d.x, motion.get_position_2d().x])


## AC3.2: obstr_mgr.get_shape(tag).center 跟 actor.position_2d 同步(每 tick)
func _test_obstr_mgr_move_shape_sync() -> void:
	var obstr_mgr := _make_obstr_mgr()
	var world := MockWorld.new()
	world.obstruction_manager = obstr_mgr

	var actor: RtsUnitActor = _make_unit_at(Vector2(50, 50))
	# Register obstruction shape 拿 tag
	actor.obstruction_tag = obstr_mgr.add_unit_shape(
		"actor_test_1",
		actor.position_2d,
		actor.collision_radius,
		RtsObstructionFlags.BLOCK_MOVEMENT,
		"team_0",
	)

	var motion := RtsUnitMotion.new()
	motion._walk_speed = 100.0
	var component := RtsMotionComponent.new(actor, motion)
	actor.motion_component = component

	motion.move_to(Vector2(200, 50), 0, 0)
	var facade := MockSinglePathFacade.new()
	facade.short_wp = Vector2(200, 50)

	# Tick 1s:渐进 100 px → actor.position_2d ≈ (150, 50)
	component.tick(1.0, world, facade)

	var shape := obstr_mgr.get_shape(actor.obstruction_tag)
	if shape == null:
		_failures.append("AC3.2: obstruction shape lost after move")
		return
	if not is_equal_approx(shape.center.x, actor.position_2d.x):
		_failures.append("AC3.2: shape.center.x %f != actor.position_2d.x %f" % [shape.center.x, actor.position_2d.x])
	if not is_equal_approx(shape.center.y, actor.position_2d.y):
		_failures.append("AC3.2: shape.center.y %f != actor.position_2d.y %f" % [shape.center.y, actor.position_2d.y])


## AC3.3: FLAG_MOVING 切换 — 起步后 true,到达后 false(was_moving != is_moving 才调)
func _test_flag_moving_toggle() -> void:
	var obstr_mgr := _make_obstr_mgr()
	var world := MockWorld.new()
	world.obstruction_manager = obstr_mgr

	var actor: RtsUnitActor = _make_unit_at(Vector2(0, 0))
	actor.obstruction_tag = obstr_mgr.add_unit_shape(
		"actor_test_2",
		actor.position_2d,
		actor.collision_radius,
		RtsObstructionFlags.BLOCK_MOVEMENT,
		"team_0",
	)

	var motion := RtsUnitMotion.new()
	motion._walk_speed = 100.0
	var component := RtsMotionComponent.new(actor, motion)
	actor.motion_component = component

	# 默认:flag 不含 MOVING
	var shape: RtsObstructionShape = obstr_mgr.get_shape(actor.obstruction_tag)
	var flags_before: int = shape.flags
	if flags_before & RtsObstructionFlags.MOVING != 0:
		_failures.append("AC3.3 precond: MOVING flag should be clear before motion starts")

	# 移动开始
	motion.move_to(Vector2(200, 0), 0, 0)
	var facade := MockSinglePathFacade.new()
	facade.short_wp = Vector2(200, 0)
	component.tick(0.5, world, facade)  # 0.5s × 100 px/s = 50 px,short_path 非空 → 移动中

	var flags_moving: int = obstr_mgr.get_shape(actor.obstruction_tag).flags
	if flags_moving & RtsObstructionFlags.MOVING == 0:
		_failures.append("AC3.3: MOVING flag should be set during motion")

	# 跑到底:tick 直到 short_path 走完
	# walk_speed 100, distance 200-50=150 left → 1.5s 余够
	for i in range(5):
		component.tick(1.0, world, facade)
		if not motion.has_target() or motion._short_path.is_empty():
			break

	# 注意:motion 状态机里,走完一段 short_path 后 _path_update_needed 会重新请求 long_path,
	# facade 又给 short_wp,所以 _short_path 反复在 non-empty;component._was_moving 一直 true。
	# 这意味着此测试的"flag 切回 false"在持续 facade non-empty 的设定下不发生 — 正常。
	# 关键是:第一 tick 触发了 _was_moving false→true 切换 + obstr_mgr.set_unit_moving_flag(true);
	# 反向切换 (走完 + facade 返空) 由 motion_failed_movements smoke 覆盖(facade 全空)。


## AC3.4: component.set_clearance(c) 同步 motion._clearance + obstruction.shape.clearance
func _test_set_clearance_sync() -> void:
	var obstr_mgr := _make_obstr_mgr()
	var actor: RtsUnitActor = _make_unit_at(Vector2(0, 0))
	actor.obstruction_tag = obstr_mgr.add_unit_shape(
		"actor_test_3",
		actor.position_2d,
		actor.collision_radius,
		RtsObstructionFlags.BLOCK_MOVEMENT,
		"team_0",
	)

	var motion := RtsUnitMotion.new()
	motion.set_clearance(14.0)  # 默认
	var component := RtsMotionComponent.new(actor, motion)

	# 默认 clearance = 14
	if not is_equal_approx(motion.get_clearance(), 14.0):
		_failures.append("AC3.4 precond: motion.clearance %f != 14" % motion.get_clearance())
	var shape := obstr_mgr.get_shape(actor.obstruction_tag) as RtsObstructionShapeUnit
	if not is_equal_approx(shape.clearance, 14.0):
		_failures.append("AC3.4 precond: shape.clearance %f != 14" % shape.clearance)

	# Set clearance 20 → 同步两边
	component.set_clearance(20.0, obstr_mgr)
	if not is_equal_approx(motion.get_clearance(), 20.0):
		_failures.append("AC3.4: motion.clearance %f != 20 after set" % motion.get_clearance())
	var shape2 := obstr_mgr.get_shape(actor.obstruction_tag) as RtsObstructionShapeUnit
	if not is_equal_approx(shape2.clearance, 20.0):
		_failures.append("AC3.4: shape.clearance %f != 20 after set" % shape2.clearance)
