## RtsUnitMotion - 单位移动核心(0 A.D. CCmpUnitMotion 复刻;M7 引入)
##
## 0 A.D. `CCmpUnitMotion`(`CCmpUnitMotion.h` + `_System.cpp`)的 GDScript 复刻;替换现有
## `RtsNavAgent` + `RtsUnitSteering` 双类。把 long+short 双轨整合到统一 motion update tick。
##
## **本 milestone 拆 4 sub-phase**:
##   - M7a:Path Storage — 字段 + 公开 API + path 双持(state-only,不 tick)
##   - **M7b (本文件已含)**:Lifecycle — `tick()` 状态机 + `_failed_movements` 累计 + KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN 触发 long retry
##   - M7c:Movement + Obstruction sync — `_step()` 真 position update + `move_shape` + `set_unit_moving_flag`
##   - M7d:Activity 集成 — `RtsActivity` 子类全走 motion API + emit MoveFailed 事件
##
## **M7b 范围**:tick() 状态机框架 + _failed_movements 累加规则(每 long path / short path
## 失败 += 1)+ MAX_FAILED_MOVEMENTS=35 触发 stop() + countdown 12 ticks 触发 long retry。
## 仍**不接 production callsite**(activity / nav_agent / move_units_command 还走旧 RtsNavAgent),
## 只验状态机本身。_step 在 M7b 是 stub(消费 short_path 一个 waypoint 模拟"前进"),M7c 接
## 真 position update + obstr_mgr 同步。
##
## **核心数据**:
##   - `_move_request` — 当前移动请求(NONE / POINT / ENTITY / OFFSET)
##   - `_long_path` — 长路径,LongPath A* on navcell 给的 32 px 阶梯路径
##   - `_short_path` — 短路径,VertexPath visibility graph 给的任意角度直线段路径(贴 OBB / unit 边)
##   - `_expected_path_ticket` — 当前 active 寻路 ticket(同步阶段:发请求时 set,facade 返回后立刻 clear)
##
## **状态机契约**(M7b 启用):
##   - 跟随时优先消费 `_short_path`(若有);next short 走完触发 long advance(从 `_long_path` pop 一个 waypoint 作下一目标)
##   - `_failed_movements` 累 ≥ MAX_FAILED_MOVEMENTS(35) → activity 收到 MoveFailed 事件 abort
##   - `_follow_known_imperfect_path_countdown`(12 ticks)在 best-so-far short path 完后触发 long retry
##
## **API 调方**:M7c 起 RtsMotionComponent 在 actor 上挂 motion + 在 set_clearance 时同步
## obstr_mgr.unit_shape.clearance 字段(D2 不变量:clearance ≡ obstruction.radius)。M7a
## 阶段 set_clearance 仅更新 _clearance 字段,obstr 同步逻辑由 component 层负责(M7c 接)。
##
## **决策来源**:
##   - data-structures.md §8.3 (RtsUnitMotion 字段表)
##   - milestones/M7-unit-motion.md §M7a (sub-phase 拆分 + AC)
##   - 0 A.D. CCmpUnitMotion.h:130-260
class_name RtsUnitMotion
extends RefCounted


# ========== 常量 ==========

## 失败 movement 累计阈值;activity 收到 MoveFailed 事件后 abort(M7b 启用)。
const MAX_FAILED_MOVEMENTS: int = 35

## best-so-far short path 走完后等多少 tick 触发 long retry(M7b 启用)。
const KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN: int = 12


# ========== 字段:模板(unit_kind config 读) ==========

## Template walk speed (px/sec);从 unit_kind config 读。
var _template_walk_speed: float = 80.0

## Passability class config(`default` / `air`);从 unit_kind config 读。
var _pass_class: RtsPassabilityClassConfig = null


# ========== 字段:动态身体属性 ==========

## 单位避让半径(px)— 必须 ≡ obstruction shape.clearance(D2 不变量,M7c 由 component 同步)。
var _clearance: float = 14.0

## 当前 walk speed(可被 buff / slow 修改);初始 = _template_walk_speed。
var _walk_speed: float = 80.0

## 是否阻挡其他单位移动(false 时 push 不到 unit);死者 / spawn 中 / 飞行单位可设 false。
var _block_movement: bool = true


# ========== 字段:反馈计数 ==========

## 累计失败 movement 数;move_to / move_to_entity / stop 调用时清零(M7b 启用)。
var _failed_movements: int = 0

## best-so-far short path 走完后倒数 N tick 触发 long retry(M7b 启用)。
var _follow_known_imperfect_path_countdown: int = 0


# ========== 字段:当前请求 + 异步 ticket ==========

## 当前移动请求(NONE = 无目标 / POINT / ENTITY / OFFSET)。
var _move_request: RtsMoveRequest = null

## Active 寻路请求 ticket(同步阶段:发请求时 set,facade 返回后立刻 clear)。
var _expected_path_ticket: RtsMotionTicket = null


# ========== 字段:双 path 持有 ==========

## Long path — LongPath A* on navcell 给的 32 px 阶梯路径(全图)。
var _long_path: RtsWaypointPath = null

## Short path — VertexPath visibility graph 给的任意角度直线段路径(贴 OBB / unit 边)。
var _short_path: RtsWaypointPath = null


# ========== 字段:位置 mirror(M7b/c component 每 tick sync) ==========

## 当前世界位置(actor.position_2d 的 mirror)— RtsMotionComponent 每 tick 在 motion.tick 前
## 调 set_position_2d 同步,_step 内更新后 component 读回写 owner.position_2d。
##
## **不变量**:tick 期间 _position_2d 是 motion 唯一的位置真相;tick 外 owner 是真相。
var _position_2d: Vector2 = Vector2.ZERO


# ========== Static 计数器 ==========

## 单调递增 ticket sequence(同步寻路实现下保留 ticket 递增,M7+ 改 async 时直接接);
## class-level shared counter,从 1 开始(0 = no ticket)。
static var _next_ticket_seq: int = 1


# ========== 初始化 ==========

func _init(p_pass_class: RtsPassabilityClassConfig = null, p_template_walk_speed: float = 80.0) -> void:
	_pass_class = p_pass_class
	_template_walk_speed = p_template_walk_speed
	_walk_speed = p_template_walk_speed
	# WHY: motion 创建后处于 NONE / 无 path 状态,等 activity / player command 调 move_to_* 触发请求
	_move_request = RtsMoveRequest.new()
	_long_path = RtsWaypointPath.new()
	_short_path = RtsWaypointPath.new()


# ========== 公开 API:移动请求 ==========

## 走到点附近;距离落入 [min_r, max_r]。重置 _failed_movements + 清双 path + 清 ticket。
func move_to(pos: Vector2, min_r: float, max_r: float) -> void:
	_move_request = RtsMoveRequest.to_point(pos, min_r, max_r)
	_reset_path_state()


## 接近 entity 到指定距离;eid 必须非空。重置 _failed_movements + 清双 path + 清 ticket。
func move_to_entity(eid: String, min_r: float, max_r: float) -> void:
	_move_request = RtsMoveRequest.to_entity(eid, min_r, max_r)
	_reset_path_state()


## 跟随 entity 保持 offset(本地坐标);M9 编队用,M7 阶段留接口。
## 重置 _failed_movements + 清双 path + 清 ticket。
func move_with_offset(eid: String, off: Vector2) -> void:
	_move_request = RtsMoveRequest.with_offset(eid, off)
	_reset_path_state()


## 取消当前请求 — _move_request 设 NONE,清双 path,清 ticket。activity stop / idle 调。
func stop() -> void:
	_move_request = RtsMoveRequest.new()
	_short_path.clear()
	_long_path.clear()
	if _expected_path_ticket != null:
		_expected_path_ticket.clear()
	# WHY: stop 不清 _failed_movements — activity 决定是否重新 move_to(届时由 move_to 清);
	# 跟 0ad CCmpUnitMotion 行为一致(StopMoving 不重置 m_FailedMovements)。


# ========== 公开 API:状态查询 ==========

## 当前是否有 active 移动请求(_move_request 非空且 type != NONE)。
func has_target() -> bool:
	return _move_request != null and _move_request.type != RtsMoveRequest.Type.NONE


## 当前 clearance(单位避让半径,px)。
func get_clearance() -> float:
	return _clearance


## 设 clearance — 仅更新 _clearance 字段;obstruction shape.clearance 同步由
## RtsMotionComponent 负责(M7c 接,D2 不变量:clearance ≡ obstruction.radius)。
##
## **不变量**:c > 0;0 / 负值 触发 assert_crash(motion 不应被设无效半径)。
func set_clearance(c: float) -> void:
	Log.assert_crash(c > 0.0, "RtsUnitMotion", "set_clearance: c must be > 0, got %f" % c)
	_clearance = c


## 同步 actor 位置进 motion(M7b/c component 每 tick 在 motion.tick 前调)。
func set_position_2d(pos: Vector2) -> void:
	_position_2d = pos


## 当前 motion 内位置(_step 后 component 读回写 owner.position_2d)。
func get_position_2d() -> Vector2:
	return _position_2d


# ========== 公开 API:tick 状态机(M7b) ==========

## 主 tick — 推进 motion 一步;调用前 component 必须 `set_position_2d(owner.position_2d)`,
## 调用后 component 必须 `owner.position_2d = motion.get_position_2d()`(M7c 接)。
##
## **流程**(spec §M7b.1):
##   1. has_target() == false → 直接 return
##   2. _path_update_needed() → _request_long_path(start = _position_2d)
##   3. _short_path empty:
##      a. _long_path empty → _request_short_path 直接到 goal;空 → _failed_movements += 1
##         + 阈值检查 stop()
##      b. _long_path 非空 → pop 一个 waypoint 作下一目标 → _request_short_path_to
##   4. _step(delta, world)— 消费一个 short_path waypoint(M7b stub;M7c 真 position update)
##   5. countdown 倒数 — 走完触发 long retry
##
## **签名说明**:
##   - `world: Variant`(M7b 暂不强类型,M7c 接 RtsWorld 后改 RtsWorld)— ENTITY MoveRequest
##     的 goal 中心需要 world.get_actor(eid).position_2d,M7b 阶段 ENTITY 路径返 null goal
##   - `facade: RtsPathfinderFacade` — 寻路调用方
func tick(delta: float, world: Variant, facade: RtsPathfinderFacade) -> void:
	if not has_target():
		return

	if _path_update_needed():
		_request_long_path(facade, world)

	if _short_path.is_empty():
		if _long_path.is_empty():
			_request_short_path(facade, world)
			if _short_path.is_empty():
				_failed_movements += 1
				if _failed_movements >= MAX_FAILED_MOVEMENTS:
					stop()
				return
		else:
			var next_long: Vector2 = _long_path.pop_back()
			_request_short_path_to(next_long, facade, world)

	_step(delta, world)

	# m_FollowKnownImperfectPathCountdown:short_path 走完后倒数 N tick 触发 long retry
	# (best-so-far short path 可能未到真 goal,countdown 给 long path 重新规划机会)
	if _short_path.is_empty() and _follow_known_imperfect_path_countdown > 0:
		_follow_known_imperfect_path_countdown -= 1
		if _follow_known_imperfect_path_countdown == 0:
			_long_path.clear()
			if _expected_path_ticket != null:
				_expected_path_ticket.clear()


# ========== 内部 helper ==========

## move_to_* 共用:清双 path、清 ticket、reset _failed_movements、reset countdown。
func _reset_path_state() -> void:
	_failed_movements = 0
	_follow_known_imperfect_path_countdown = 0
	_short_path.clear()
	_long_path.clear()
	if _expected_path_ticket != null:
		_expected_path_ticket.clear()


## 是否需要请求新 long path(_long_path 空 + 没 active ticket)。
func _path_update_needed() -> bool:
	if not _long_path.is_empty():
		return false
	if _expected_path_ticket != null and _expected_path_ticket.is_active():
		return false
	return true


## 请求 long path → facade.compute_path_immediate;空 path → _failed_movements += 1。
##
## 同步寻路实现下 ticket 仅作"已请求"标记,facade 返回后立刻 clear。
func _request_long_path(facade: RtsPathfinderFacade, world: Variant) -> void:
	if facade == null:
		_failed_movements += 1
		return
	var goal: RtsPathGoal = _make_path_goal_from_request(world)
	if goal == null:
		# ENTITY MoveRequest 在 M7b 阶段 world == null 不能解析 → 视为失败
		_failed_movements += 1
		return
	_expected_path_ticket = RtsMotionTicket.new(RtsMotionTicket.Type.LONG_PATH, _alloc_ticket())
	var pass_mask: int = _resolve_pass_mask()
	_long_path = facade.compute_path_immediate(_position_2d, goal, pass_mask)
	# 同步寻路:facade 返回后立刻 clear ticket(M7+ async 改 callback 时不清这里)
	_expected_path_ticket.clear()
	if _long_path.is_empty():
		_failed_movements += 1


## 请求 short path 直接到 goal(没 long path 中转时);空 path → 调方累加 _failed_movements。
func _request_short_path(facade: RtsPathfinderFacade, world: Variant) -> void:
	if facade == null:
		return
	var goal: RtsPathGoal = _make_path_goal_from_request(world)
	if goal == null:
		return
	_short_path = _do_short_path(facade, goal, world)


## 请求 short path 到 long path 给的中间 waypoint。
func _request_short_path_to(target: Vector2, facade: RtsPathfinderFacade, world: Variant = null) -> void:
	if facade == null:
		return
	var goal: RtsPathGoal = RtsPathGoal.new(RtsPathGoal.Type.POINT, target)
	_short_path = _do_short_path(facade, goal, world)


## 共用:调 facade.compute_short_path_immediate;obstr_mgr 从 world 取(M7c 接 RtsWorld 时
## world.obstruction_manager 一等公民字段);world == null 时传 null obstr_mgr,facade 内部
## 是否能处理 null 由 facade 自己定(M7b smoke 用 mock facade override compute_short_path_immediate
## 返空,根本不读 obstr_mgr)。
func _do_short_path(facade: RtsPathfinderFacade, goal: RtsPathGoal, world: Variant) -> RtsWaypointPath:
	var req := RtsShortPathRequest.new(
		_position_2d,
		goal,
		_clearance,
		RtsShortPathRequest.DEFAULT_RANGE_PX,
		_resolve_pass_mask(),
	)
	var obstr_mgr_var = null
	if world != null and world.has_method("get"):
		obstr_mgr_var = world.get("obstruction_manager")
	return facade.compute_short_path_immediate(req, obstr_mgr_var)


## 把当前 _move_request 转成 RtsPathGoal(LongPath / ShortPath 接受统一抽象)。
##
## - POINT → POINT goal at position
## - ENTITY → 需 world.get_actor(eid).position_2d 作 goal 中心(M7c 接 RtsWorld);M7b world
##   传 null 时返 null 让调方累 _failed_movements
## - OFFSET → 类似 ENTITY + offset(M9 编队;M7 阶段返 null)
##
## 返 null = 失败,调方应当作 "no goal" 累加 _failed_movements。
func _make_path_goal_from_request(world: Variant) -> RtsPathGoal:
	if _move_request == null:
		return null
	match _move_request.type:
		RtsMoveRequest.Type.POINT:
			return RtsPathGoal.new(RtsPathGoal.Type.POINT, _move_request.position)
		RtsMoveRequest.Type.ENTITY:
			# M7b stub: world == null → 无法解析 entity → 返 null 失败
			# M7c 接 RtsWorld:world.get_actor(eid).position_2d → POINT goal
			if world == null:
				return null
			# Best-effort:走 duck typing,适配 M7c RtsWorld API
			if not world.has_method("get_actor"):
				return null
			var target = world.get_actor(_move_request.entity_id)
			if target == null:
				return null
			return RtsPathGoal.new(RtsPathGoal.Type.POINT, target.position_2d)
		RtsMoveRequest.Type.OFFSET:
			# M9 编队 — M7 阶段不实现
			return null
		_:
			return null


## passability mask = pass_class.bit_index(M7b 阶段单 class;M7c 接 unit_kind config 时按 type
## 取 ground / air)。pass_class null 时返默认 mask 1(default class)。
func _resolve_pass_mask() -> int:
	if _pass_class == null:
		return 1
	# bit_index 是 0..15,mask = 1 << bit_index
	return 1 << _pass_class.bit_index


## 分配下一个 ticket sequence(static counter,deterministic 跨 procedure reset 由 caller 处理)。
static func _alloc_ticket() -> int:
	var t: int = _next_ticket_seq
	_next_ticket_seq += 1
	return t


# ========== 内部 helper:_step (M7b stub;M7c 真 position update) ==========

## **M7b stub**:消费一个 short_path waypoint 模拟"我前进了一段",更新 _position_2d
## 到该 waypoint。M7c 接 walk_speed * delta 渐进 + obstr_mgr.move_shape 同步。
##
## 设计上 M7b stub 行为:每 tick 直接 pop short_path 一个 waypoint 设 _position_2d = waypoint。
## 这让 short_path 走完时 countdown 触发逻辑能进入。
##
## **不动 actor / obstr_mgr**(M7c 接);仅 motion 内部 _position_2d mirror。
func _step(_delta: float, _world: Variant) -> void:
	if _short_path.is_empty():
		return
	# M7b stub:直接到 next waypoint;M7c 加 walk_speed * delta 渐进 + obstr.move_shape
	var next_wp: Vector2 = _short_path.pop_back()
	_position_2d = next_wp
	# short_path 走完(本次 pop 后空)→ 启动 countdown 给 long retry 机会
	if _short_path.is_empty() and _follow_known_imperfect_path_countdown == 0:
		_follow_known_imperfect_path_countdown = KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN
