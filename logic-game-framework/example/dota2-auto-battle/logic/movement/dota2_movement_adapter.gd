## Dota2MovementAdapter - battle intent ↔ sim-nav DOTA2 lab 移动原语 的唯一边界
##
## README.md（M1 契约 节） Movement Contract：接 sim-nav-map，以 dota2-rts-pathfinding-lab 为参考
## 实现。controller/ability **永不**直接动 pathfinding / motion 内部 —— 只经本 adapter：
##   Dota2Intent → Dota2MovementAdapter → Dota2Lab{PathfinderWrapper,MotionController,Unit}
##
## DOTA2 移动手感约束（不下沉进 sim-nav core）：硬阻挡 OK、无友军穿插、无编队/打包/
## 群体寻路、无 push pressure。每 actor 一个 Dota2LabUnit「移动体」，position 双向同步：
## adapter 推进后把 body.position 写回 actor.position_2d（战斗判定的权威坐标）。
##
## 每 tick 固定相位（Dota2LabWorld.step §motion-controller-design §4，顺序不可错）：
##   1 apply_path_results(每 body)  2 refresh_dynamic + step_unit(FOLLOWING)
##   3 drain motion updates         4 process_budget(预算推进 path 请求队列)
class_name Dota2MovementAdapter
extends RefCounted


const NAV_CELL_SIZE := 16.0
## 目标移动超过此距离才重发 follow move order（避免每 tick 重排路径抖动 / 队列爆）。
const FOLLOW_REISSUE_DISTANCE := 28.0


var _pathfinder: Dota2LabPathfinderWrapper = null
var _motion: Dota2LabMotionController = null
## actor_id → Dota2LabUnit（移动体）。
var _bodies: Dictionary = {}
## 确定性迭代顺序（register 顺序；refresh_dynamic / step_unit 需要稳定 body 列表）。
var _body_order: Array[String] = []
var _tick_count: int = 0
## actor_id → 最近一次发出的 follow 目标点（判断是否需要重发 order）。
var _last_follow_goal: Dictionary = {}


func _init() -> void:
	_pathfinder = Dota2LabPathfinderWrapper.new(Dota2LaneConfig.MAP_SIZE, NAV_CELL_SIZE, 12.0)
	# 开阔中路，无静态障碍（M1）：units 之间靠 DOTA2 硬阻挡互相避让。
	# rebuild_context 形参是 Array[Dota2LabObstacle]，必须传同元素类型的空 typed 数组。
	var no_static: Array[Dota2LabObstacle] = []
	_pathfinder.rebuild_context(no_static)
	_motion = Dota2LabMotionController.new()


# ========== 注册 / 注销移动体 ==========

func register_unit(actor: Dota2UnitActor) -> void:
	if _bodies.has(actor.get_id()):
		return
	var body := Dota2LabUnit.new(
		actor.get_id(), "",
		actor.position_2d,
		actor.collision_radius,
		actor.attribute_set.move_speed,
		true,
	)
	body.blocks_pathfinding = true
	_bodies[actor.get_id()] = body
	_body_order.append(actor.get_id())


func unregister_unit(actor_id: String) -> void:
	if not _bodies.has(actor_id):
		return
	var body: Dota2LabUnit = _bodies[actor_id]
	# 注销前取消 pending path ticket，否则 Dota2LabUnit 析构 assert 会报。
	if body.state != Dota2LabUnit.STATE_IDLE and body.state != Dota2LabUnit.STATE_FAILED:
		_motion.cancel_move_order(body, _pathfinder, _tick_count, "unregister")
	_bodies.erase(actor_id)
	_body_order.erase(actor_id)
	_last_follow_goal.erase(actor_id)


func has_body(actor_id: String) -> bool:
	return _bodies.has(actor_id)


# ========== Intent → 移动原语 ==========

## LaneMarchIntent：朝 lane 终点航点行进。仅在尚未朝该目标行进时下新 order
## （intent 持久 —— 不每 tick 重发，靠 body 内部 path runtime 续跑）。
func ensure_march(actor: Dota2UnitActor, goal: Vector2) -> void:
	var body: Dota2LabUnit = _bodies.get(actor.get_id(), null)
	if body == null:
		return
	if _needs_new_order(body, goal):
		_motion.begin_new_move_order(body, goal, _pathfinder, _tick_count)
		_last_follow_goal.erase(actor.get_id())


## AttackTargetIntent 的接近段：target 在停止距离外 → 追（朝 target 重发 order，
## 仅当 target 移动够远）；在停止距离内 → 停（取消 move order，定身好打）。
func ensure_chase(actor: Dota2UnitActor, target_pos: Vector2, stop_distance: float) -> void:
	var body: Dota2LabUnit = _bodies.get(actor.get_id(), null)
	if body == null:
		return
	var dist := actor.position_2d.distance_to(target_pos)
	if dist <= stop_distance:
		_stop_body(body)
		_last_follow_goal.erase(actor.get_id())
		return
	var last: Variant = _last_follow_goal.get(actor.get_id(), null)
	var needs := last == null or (last as Vector2).distance_to(target_pos) > FOLLOW_REISSUE_DISTANCE
	if needs or body.state == Dota2LabUnit.STATE_IDLE or body.state == Dota2LabUnit.STATE_FAILED:
		_motion.begin_new_move_order(body, target_pos, _pathfinder, _tick_count)
		_last_follow_goal[actor.get_id()] = target_pos


## 显式停止（intent 完成 / 失败时）。
func request_stop(actor_id: String) -> void:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return
	_stop_body(body)
	_last_follow_goal.erase(actor_id)


# ========== 每 tick 推进（固定相位）==========

## procedure step 5 调一次：跑 lab 四相位，再把 body.position 写回 actor（权威坐标）。
func advance(dt_seconds: float, units: Array) -> void:
	var bodies := _ordered_bodies()
	# 相位 1：收 path 结果（驱动 WAITING_* → FOLLOWING / FAILED）。
	for body in bodies:
		_motion.apply_path_results(body, _pathfinder, _tick_count)
	# 相位 2：刷新动态障碍后步进 FOLLOWING（step_unit 内部对非 FOLLOWING 提前返回）。
	_pathfinder.refresh_dynamic_units(bodies)
	for body in bodies:
		if body.mobile:
			_motion.step_unit(body, dt_seconds, _pathfinder, bodies, _tick_count)
	# 相位 3：drain motion 事件（M1 不分发到 view，仅清空缓冲让 lab 不积压）。
	_motion.drain_motion_updates()
	# 相位 4：预算推进 path 请求队列（结果落到下 tick 的相位 1）。
	_pathfinder.process_budget(bodies, _path_budget())
	_tick_count += 1
	# 同步权威坐标：body.position → actor.position_2d（战斗 range/aggro 读此）。
	for actor in units:
		var u: Dota2UnitActor = actor as Dota2UnitActor
		if u == null:
			continue
		var body: Dota2LabUnit = _bodies.get(u.get_id(), null)
		if body == null:
			continue
		var prev := u.position_2d
		u.position_2d = body.position
		u.velocity = (body.position - prev) / dt_seconds if dt_seconds > 0.0 else Vector2.ZERO


# ========== 移动事实查询（systems 据此映射 IntentStepResult）==========

## body 是否抵达 goal 附近（lane march 完成判定用）。
func is_arrived(actor_id: String, goal: Vector2, epsilon: float = 24.0) -> bool:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return false
	return body.position.distance_to(goal) <= epsilon


## body 是否处于不可达终态（FAILED）—— lane march 失败判定用。
func is_failed(actor_id: String) -> bool:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return false
	return body.state == Dota2LabUnit.STATE_FAILED


## snapshot / debug 面板用：当前移动状态摘要。
func get_movement_state(actor_id: String) -> Dictionary:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return { "state": "none", "goal_x": 0.0, "goal_y": 0.0, "block_reason": "", "path_source": "" }
	return {
		"state": body.state,
		"goal_x": body.move_target.x,
		"goal_y": body.move_target.y,
		"block_reason": body.last_path_failure_reason,
		"path_source": body.path_source,
	}


# ========== 内部 ==========

## 单波最多 4 + 4 = 8 body；预算给足让所有 long-path 同 tick 入队不饿死。
func _path_budget() -> int:
	return maxi(6, _bodies.size())


func _ordered_bodies() -> Array[Dota2LabUnit]:
	var result: Array[Dota2LabUnit] = []
	for actor_id in _body_order:
		var body: Dota2LabUnit = _bodies.get(actor_id, null)
		if body != null:
			result.append(body)
	return result


func _needs_new_order(body: Dota2LabUnit, goal: Vector2) -> bool:
	if body.state == Dota2LabUnit.STATE_IDLE or body.state == Dota2LabUnit.STATE_FAILED:
		return true
	return body.move_target.distance_to(goal) > FOLLOW_REISSUE_DISTANCE


func _stop_body(body: Dota2LabUnit) -> void:
	if body.state == Dota2LabUnit.STATE_IDLE or body.state == Dota2LabUnit.STATE_FAILED:
		return
	_motion.cancel_move_order(body, _pathfinder, _tick_count, "stop_in_range")
