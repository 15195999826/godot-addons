## Dota2MovementAdapter - battle intent ↔ sim-nav DOTA2 lab 移动原语 的唯一边界
##
## README.md（M1 契约 节） Movement Contract：接 sim-nav-map，以 dota2-rts-pathfinding-lab 为参考
## 实现。controller/ability **永不**直接动 pathfinding / motion 内部 —— 只经本 adapter：
##   Dota2Intent → Dota2MovementAdapter → Dota2Lab{PathfinderWrapper,MotionEngine,Unit}
##
## Fable 移动模型（lab 同款）：长径只认静态世界，单位间避让 = 引擎内的位置分离求解
## （commit-then-resolve）——迎面互挤错开、拱开 idle 友军、无 detour waypoint、无重叠残留。
## 规划同步（issue_move 当场出路径），无请求队列 / ticket / 等待态。
##
## 每 actor 一个 Dota2LabUnit「移动体」，position 双向同步：adapter 推进后把
## body.position 写回 actor.position_2d（战斗判定的权威坐标）。
class_name Dota2MovementAdapter
extends RefCounted


const NAV_CELL_SIZE := 16.0
## 目标移动超过此距离才重发 move order（避免每 tick 重排路径抖动）。
const FOLLOW_REISSUE_DISTANCE := 28.0


var _pathfinder: Dota2LabPathfinderWrapper = null
var _motion: Dota2LabMotionEngine = null
## actor_id → Dota2LabUnit（移动体）。
var _bodies: Dictionary = {}
## 确定性迭代顺序（register 顺序；分离求解需要稳定 body 列表）。
var _body_order: Array[String] = []
var _tick_count: int = 0
## actor_id → 最近一次发出的 follow 目标点（判断是否需要重发 order）。
var _last_follow_goal: Dictionary = {}


func _init() -> void:
	_pathfinder = Dota2LabPathfinderWrapper.new(Dota2LaneConfig.MAP_SIZE, NAV_CELL_SIZE, 12.0)
	# 开阔中路，无静态障碍（M1）：units 之间靠分离求解互相让行。
	# rebuild_context 形参是 Array[Dota2LabObstacle]，必须传同元素类型的空 typed 数组。
	var no_static: Array[Dota2LabObstacle] = []
	_pathfinder.rebuild_context(no_static)
	_motion = Dota2LabMotionEngine.new()


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
	_bodies[actor.get_id()] = body
	_body_order.append(actor.get_id())


func unregister_unit(actor_id: String) -> void:
	if not _bodies.has(actor_id):
		return
	var body: Dota2LabUnit = _bodies[actor_id]
	_motion.cancel_move(body, _tick_count)
	_bodies.erase(actor_id)
	_body_order.erase(actor_id)
	_last_follow_goal.erase(actor_id)


func has_body(actor_id: String) -> bool:
	return _bodies.has(actor_id)


# ========== Intent → 移动原语 ==========

## LaneMarchIntent：朝 lane 终点航点行进。仅在尚未朝该目标行进时下新 order。
## 同目标 fail 过（stalled / no_path）不自动重发 —— is_failed 交 intent 层终结；
## 目标点变化超过重发距离则视为新命令、重新尝试。
func ensure_march(actor: Dota2UnitActor, goal: Vector2) -> void:
	var body: Dota2LabUnit = _bodies.get(actor.get_id(), null)
	if body == null:
		return
	if _needs_new_order(body, goal):
		_motion.issue_move(body, goal, _pathfinder, _tick_count)
		_last_follow_goal.erase(actor.get_id())


## AttackTargetIntent 的接近段：target 在停止距离外 → 追（朝 target 重发 order，
## 仅当 target 移动够远）；在停止距离内 → 停（取消 move order，定身好打）。
func ensure_chase(actor: Dota2UnitActor, target_pos: Vector2, stop_distance: float) -> void:
	var body: Dota2LabUnit = _bodies.get(actor.get_id(), null)
	if body == null:
		return
	var dist := actor.position_2d.distance_to(target_pos)
	if dist <= stop_distance:
		_motion.cancel_move(body, _tick_count)
		_last_follow_goal.erase(actor.get_id())
		return
	var last: Variant = _last_follow_goal.get(actor.get_id(), null)
	var needs := last == null or (last as Vector2).distance_to(target_pos) > FOLLOW_REISSUE_DISTANCE
	if needs or body.state == Dota2LabUnit.STATE_IDLE:
		_motion.issue_move(body, target_pos, _pathfinder, _tick_count)
		_last_follow_goal[actor.get_id()] = target_pos


## 显式停止（intent 完成 / 失败时）。
func request_stop(actor_id: String) -> void:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return
	_motion.cancel_move(body, _tick_count)
	_last_follow_goal.erase(actor_id)


# ========== 每 tick 推进 ==========

## procedure step 5 调一次：引擎 commit-then-resolve 一步，再把 body.position
## 写回 actor（权威坐标）。
func advance(dt_seconds: float, units: Array) -> void:
	var bodies := _ordered_bodies()
	_motion.step(bodies, _pathfinder, dt_seconds, _tick_count)
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


## 最近一单以失败收尾（no_path / stalled / cancelled）且已停 —— lane march
## 失败判定用。fable 模型没有常驻 FAILED 态：失败记录在 last_order 上。
func is_failed(actor_id: String) -> bool:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return false
	return body.state == Dota2LabUnit.STATE_IDLE and body.last_order_failed()


## snapshot / debug 面板用：当前移动状态摘要。
func get_movement_state(actor_id: String) -> Dictionary:
	var body: Dota2LabUnit = _bodies.get(actor_id, null)
	if body == null:
		return { "state": "none", "goal_x": 0.0, "goal_y": 0.0, "block_reason": "" }
	var block_reason := ""
	if body.last_order_failed():
		block_reason = body.last_order.reason
	return {
		"state": body.state,
		"goal_x": body.move_target.x,
		"goal_y": body.move_target.y,
		"block_reason": block_reason,
	}


# ========== 内部 ==========

func _ordered_bodies() -> Array[Dota2LabUnit]:
	var result: Array[Dota2LabUnit] = []
	for actor_id in _body_order:
		var body: Dota2LabUnit = _bodies.get(actor_id, null)
		if body != null:
			result.append(body)
	return result


func _needs_new_order(body: Dota2LabUnit, goal: Vector2) -> bool:
	if body.state == Dota2LabUnit.STATE_MOVING:
		return body.move_target.distance_to(goal) > FOLLOW_REISSUE_DISTANCE
	# IDLE：同目标失败过就不自动重发（防 fail → 重发死循环）。
	if body.last_order_failed() and body.last_order.target.distance_to(goal) <= FOLLOW_REISSUE_DISTANCE:
		return false
	return true
