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

## 抵达 waypoint 的距离阈值(像素);跟现有 RtsNavAgent.ARRIVAL_THRESHOLD 一致。
const ARRIVAL_THRESHOLD: float = 4.0


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

## 0ad-refactor Phase B — 当前 turn 速度(单位 px/s)。post_move 内 update_movement_state 写,
## pre_move 内 needUpdate 决策读。0ad CCmpUnitMotion.h:233 m_CurrentSpeed.
var _current_speed: float = 0.0

## 0ad-refactor Phase B — 上一 turn 速度(单位 px/s)。pre_move 内 needUpdate 决策读,post_move
## 内 update_movement_state 把 _current_speed 拷到此(下次 pre_move 时此为"上次")。0ad
## CCmpUnitMotion.h:m_LastTurnSpeed。决策动机:0 A.D. needUpdate 判定 = current OR last OR
## moveRequest 非空 — last 字段让"刚停下"的单位本 turn 仍跑完整 PostMove(写回最终位置)。
var _last_turn_speed: float = 0.0

## 0ad-refactor Phase C — Push pair 力度按 weight ratio 分配:重单位推轻单位多,轻单位推
## 重单位少。0 A.D. CCmpUnitMotion::GetWeight。RtsMotionComponent.attach_default 默认设
## walk_speed × 0.1(0 A.D. template 简化默认等价 — 普通单位 walk_speed=80 → weight=8,
## 重型单位 walk_speed 高 → 重 weight)。
var _weight: float = 8.0

## M7d — 上一次 tick 是否因 _failed_movements 累达阈值 abort(MAX_FAILED_MOVEMENTS=35)。
## RtsMotionComponent 在 motion.tick 后查 has_just_failed() → emit "motion_move_failed"
## event 给 owner_actor → activity 监听 abort/重选目标。consume_just_failed() 清 flag。
##
## **不变量**:flag 只由 _abort_due_to_failure() 设;move_to_*() 通过 _reset_path_state()
## 清(新请求 = 新机会,不要带上次失败的 sticky 状态)。
var _just_failed: bool = false

## M7d — 当前 _move_request 是否走 canonicalize(true=玩家 click 落 impassable 点 mutate
## 到外缘 navcell;false=AI attack/harvest target 是 actor 中心,可能在 footprint 内 → 走
## compute_path_direct,LongPath direct-path fallback,unit 走过去 distance 判定到达)。
##
## 默认 true(对应 nav_agent.set_target 默认 canonicalize=true)。move_to / move_to_entity /
## move_with_offset 重置时由 caller 决定。
var _canonicalize: bool = true

## M7d — 当 long_path facade 返空 / vertex short_path 也返空时是否启用 fallback(直奔 goal)。
##
## **production 默认 true** — production unit spawn 紧贴 building inflate 内时 long path A*
## 返空,fallback push goal 让 unit 走出 inflate 区(等价 nav_agent canonicalize=false 老行为)。
##
## **smoke unreachable 测试可设 false** — smoke_motion_failed_movements 用 MockEmptyPathFacade
## 模拟真 unreachable goal,期望 _failed_movements 累 35 触发 self-abort,fallback 会让 unit
## 永远走 → 测试失效;关 flag 走原 abort 路径。
var _allow_unreachable_fallback: bool = true


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

## M7d — RtsMotionComponent 在 tick 头部写入 RtsUnitSteering.apply 后的 actor.velocity(含
## separation + deflection)。_step 用此 velocity 当方向走;为 ZERO 时 fallback 朝 next_wp 直走。
##
## **不变量**:component 写完 motion.tick 前必须 set_steered_velocity;motion.tick 末由
## component 调 reset(避免下 tick 残留 stale velocity)。
var _steered_velocity: Vector2 = Vector2.ZERO


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

## 走到点附近;距离落入 [min_r, max_r]。清双 path + 清 ticket;**仅在 target 真变化时**重置
## _failed_movements(activity 每 0.2s 限频 refresh 同 target 不应清失败计数,否则真 stuck unit
## 永远累不到 35 → 不 abort → smoke_stuck_recovery 等场景挂)。
##
## **canonicalize**:
##   - true (默认):玩家 click move,goal 落 impassable 时 mutate 到外缘 navcell
##   - false:AI attack/harvest/return target 是 actor 中心(可能 building footprint 内),
##     走 compute_path_direct + LongPath direct-path fallback,unit 走 distance 判定到达
func move_to(pos: Vector2, min_r: float, max_r: float, canonicalize: bool = true) -> void:
	# M7d: target 真变化判定 — < 1px²(0ad refresh 限频 + 2px 抖动阈值之下)算"同 target refresh"
	var same_target: bool = (
		_move_request != null
		and _move_request.type == RtsMoveRequest.Type.POINT
		and _move_request.position.distance_squared_to(pos) < 1.0
	)
	_move_request = RtsMoveRequest.to_point(pos, min_r, max_r)
	_canonicalize = canonicalize
	_short_path.clear()
	_long_path.clear()
	if _expected_path_ticket != null:
		_expected_path_ticket.clear()
	if not same_target:
		# 真新 target → 重置失败计数 + countdown(新机会,不带上次失败 sticky 状态)
		_failed_movements = 0
		_follow_known_imperfect_path_countdown = 0
		_just_failed = false


## 接近 entity 到指定距离;eid 必须非空。清双 path + 清 ticket;**仅在 target 真变化时**
## 重置 _failed_movements(参考 move_to 注释)。
##
## **canonicalize 默认 false** — ENTITY MoveRequest 用于 AI attack/gather,target=actor 中心,
## 通常走 direct path(M4b.3 lesson)。
func move_to_entity(eid: String, min_r: float, max_r: float, canonicalize: bool = false) -> void:
	var same_target: bool = (
		_move_request != null
		and _move_request.type == RtsMoveRequest.Type.ENTITY
		and _move_request.entity_id == eid
	)
	_move_request = RtsMoveRequest.to_entity(eid, min_r, max_r)
	_canonicalize = canonicalize
	_short_path.clear()
	_long_path.clear()
	if _expected_path_ticket != null:
		_expected_path_ticket.clear()
	if not same_target:
		_failed_movements = 0
		_follow_known_imperfect_path_countdown = 0
		_just_failed = false


## 跟随 entity 保持 offset(本地坐标);M9 编队用,M7 阶段留接口。
## 重置 _failed_movements + 清双 path + 清 ticket。
func move_with_offset(eid: String, off: Vector2) -> void:
	_move_request = RtsMoveRequest.with_offset(eid, off)
	_canonicalize = true
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


## 是否上 tick 因 failed_movements 累达阈值 abort(M7d 启用 — RtsMotionComponent 查询)。
##
## consume_just_failed() 清 flag;新 move_to() 也会清(通过 _reset_path_state)。
func has_just_failed() -> bool:
	return _just_failed


## 消费 _just_failed flag(component 在 emit "motion_move_failed" event 后调)。
##
## 同 tick 多次 consume 是 idempotent(consume 后再查 has_just_failed = false)。
func consume_just_failed() -> void:
	_just_failed = false


## 内部:failed_movements 累达阈值时调,set _just_failed flag + stop()。
##
## **不变量**:仅 tick 内部累达阈值时调;move_to_* 重置 _failed_movements 时不调。
## 设计选择:flag 跟 stop() 解耦 — 公开 stop() 不破坏 _failed_movements / _just_failed
## 计数(activity 自己 cancel 走 stop() 路径不应误触发 MoveFailed event)。
func _abort_due_to_failure() -> void:
	_just_failed = true
	stop()


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


## 0ad-refactor Phase C — Push pair 力度 weight ratio 用;> 0 才合法。
## RtsMotionComponent.attach_default 默认设 walk_speed × 0.1。
func get_weight() -> float:
	return _weight


func set_weight(w: float) -> void:
	Log.assert_crash(w > 0.0, "RtsUnitMotion", "set_weight: w must be > 0, got %f" % w)
	_weight = w


## 同步 actor 位置进 motion(M7b/c component 每 tick 在 motion.tick 前调)。
func set_position_2d(pos: Vector2) -> void:
	_position_2d = pos


## 当前 motion 内位置(_step 后 component 读回写 owner.position_2d)。
func get_position_2d() -> Vector2:
	return _position_2d


## M7d — 设 _steered_velocity(component 在 tick 头部 RtsUnitSteering.apply 后调)。
func set_steered_velocity(v: Vector2) -> void:
	_steered_velocity = v


## 当前 _step 推 next_wp 的方向(component 写 actor.velocity 用)。
##
## 返 ZERO 当 motion 没 short path / has_target=false。否则返 (next_wp - position).normalized()
## * _walk_speed(等价 nav_agent 老 compute_desired_velocity 行为)。
func compute_desired_velocity() -> Vector2:
	if _short_path.is_empty():
		return Vector2.ZERO
	var next_wp: Vector2 = _short_path.back()
	var to_next: Vector2 = next_wp - _position_2d
	var dist: float = to_next.length()
	if dist <= 0.0001:
		return Vector2.ZERO
	return (to_next / dist) * _walk_speed


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
	# M7d: tick 拆两步给 RtsMotionComponent 中间插 RtsUnitSteering.apply (separation):
	#   1. handle_path_update — path 请求 / 失败累加 / fallback
	#   2. _step — 渐进位置 update(用 _steered_velocity 当方向)
	# component 在两步之间调 RtsUnitSteering.apply 改 actor.velocity 后 set_steered_velocity。
	# 老 motion.tick 直接调两步 + tail countdown,smoke 单元测试 mock facade 不依赖 component 也兼容。
	handle_path_update(facade, world)
	_step(delta, world)

	# Tail: m_FollowKnownImperfectPathCountdown — short_path 走完后倒数 N tick 触发 long retry
	# (best-so-far short path 可能未到真 goal,countdown 给 long path 重新规划机会)。component
	# 调 _step 而不调本 tick 时也需要倒数,故 component.tick 也要复刻这个 tail(M7d.4)。
	_tail_countdown_tick()


## M7d — countdown tail 单独抽出来给 component.tick 复刻调用。
func _tail_countdown_tick() -> void:
	if _short_path.is_empty() and _follow_known_imperfect_path_countdown > 0:
		_follow_known_imperfect_path_countdown -= 1
		if _follow_known_imperfect_path_countdown == 0:
			_long_path.clear()
			if _expected_path_ticket != null:
				_expected_path_ticket.clear()


## M7d — Motion.tick step 1:path 请求 + 失败累加 + fallback;不渐进 position(留 _step)。
##
## **签名说明**:此 method **public** 是为让 RtsMotionComponent 显式分步调用(中间插
## RtsUnitSteering.apply)。直接 motion.tick 用法不变。
func handle_path_update(facade: RtsPathfinderFacade, world: Variant) -> void:
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
					_abort_due_to_failure()
				return
		else:
			var next_long: Vector2 = _long_path.pop_back()
			_request_short_path_to(next_long, facade, world)
			if _short_path.is_empty() and _allow_unreachable_fallback:
				# M7d FALLBACK: vertex pathfinder simple-case 返空 path(start ≈ next_long
				# 直线无障碍 / vertex algo corner case)→ 直接用 next_long 当 short 单 wp
				# 让 _step 走 long path 的下一段。等价于"没 vertex 绕角效果,但 unit 仍按
				# long path 推进",跟 M5 LongPath-only 行为一致,避免 unit 站桩死锁。
				_short_path.push_back(next_long)

	# m_FollowKnownImperfectPathCountdown:short_path 走完后倒数 N tick 触发 long retry
	# (best-so-far short path 可能未到真 goal,countdown 给 long path 重新规划机会)
	if _short_path.is_empty() and _follow_known_imperfect_path_countdown > 0:
		_follow_known_imperfect_path_countdown -= 1
		if _follow_known_imperfect_path_countdown == 0:
			_long_path.clear()
			if _expected_path_ticket != null:
				_expected_path_ticket.clear()


# ========== 内部 helper ==========

## move_to_* 共用:清双 path、清 ticket、reset _failed_movements、reset countdown、清 just_failed。
func _reset_path_state() -> void:
	_failed_movements = 0
	_follow_known_imperfect_path_countdown = 0
	_just_failed = false
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
	# M7d: canonicalize true=compute_path_immediate(玩家 click)/ false=compute_path_direct
	# (AI attack/harvest target=actor 中心 footprint 内,M4b.3 lesson)
	if _canonicalize:
		_long_path = facade.compute_path_immediate(_position_2d, goal, pass_mask)
	else:
		_long_path = facade.compute_path_direct(_position_2d, goal, pass_mask)
	# 同步寻路:facade 返回后立刻 clear ticket(M7+ async 改 callback 时不清这里)
	_expected_path_ticket.clear()
	if _long_path.is_empty():
		_failed_movements += 1
		# M7d FALLBACK: long path A* 返空(start 在 inflate 内 / unreachable)→ 直接奔 goal
		# 当 _move_request.type == POINT 时,push goal 当 single-wp long path 让 unit 走直线
		# 朝 goal,等价于 nav_agent canonicalize=false 老 fallback(M4b.3 lesson:enemy 中心
		# 在 footprint 内,LongPath direct-path fallback 让 unit 走过去)。production unit
		# spawn 紧贴 ct 时(spawn_offset=28 在 inflate 内),没 fallback 单位永远 stuck。
		if _allow_unreachable_fallback and _move_request != null and _move_request.type == RtsMoveRequest.Type.POINT:
			_long_path.push_back(_move_request.position)


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


# ========== 内部 helper:_step (M7c 真渐进 position update) ==========

## 渐进朝 _short_path.back() (next waypoint) 走 step_len = walk_speed * delta;若 step_len 跨过
## next waypoint(剩余距离 < step_len)则 pop_back + _position_2d = waypoint;path 空时启动 countdown。
##
## **M7d 末态**:component 在 tick 之前给 owner_actor.velocity 写 desired velocity(path 方向)
## 后调 RtsUnitSteering.apply 加 separation;_step 用 owner_actor.velocity 当方向走(已含 sep
## 偏转)。velocity == 0 时 fallback 朝 to_next 方向走(deterministic 兜底)。
##
## **不动 actor / obstr_mgr**(component 桥接):仅 motion 内部 _position_2d。RtsMotionComponent
## 在 motion.tick 后调 owner.position_2d = motion.get_position_2d() + obstr_mgr.move_shape 同步。
func _step(delta: float, _world: Variant) -> void:
	if _short_path.is_empty():
		# M7d: 没 path 但 _steered_velocity 非空 = 静止单位收到 separation push(纯 sep_force,
		# 没 path desired velocity)。让 unit 受推力移动,避免 cluster 重叠。等价于 nav_agent 时代
		# RtsUnitSteering 静止 unit 也 sep 的行为(spec line 10-12)。
		if _steered_velocity != Vector2.ZERO:
			_position_2d += _steered_velocity * delta
		return
	var next_wp: Vector2 = _short_path.back()
	var to_next: Vector2 = next_wp - _position_2d
	var dist_to_next: float = to_next.length()
	var step_len: float = _walk_speed * delta

	# M7d: 永不 snap 让 separation 累积偏离始终保留(M6 nav_agent.integrate 风格)。
	#   1. 渐进朝 next_wp 走(优先 _steered_velocity 含 sep,无 sep fallback to_next 方向)
	#   2. 若 step_amt 跨过 next_wp,cap 到 dist_to_next(避免飞过头)
	#   3. 走完后再判断 ARRIVAL:dist <= ARRIVAL 触发 pop short
	var move_vec: Vector2
	if _steered_velocity != Vector2.ZERO:
		move_vec = _steered_velocity * delta
	else:
		# walk_speed 大 cap 不超 dist(避免飞过头),velocity 已含 sep 不需再 cap
		var cap_step: float = min(step_len, dist_to_next)
		move_vec = (to_next / dist_to_next) * cap_step
	_position_2d += move_vec

	# 走完后判断 ARRIVAL — 距离 <= ARRIVAL_THRESHOLD 触发 pop;不 snap _position_2d 让
	# separation 偏离保留(group formation 4 unit 同 final_pos 时不互相覆盖到一点)
	var dist_after: float = (next_wp - _position_2d).length()
	if dist_after <= ARRIVAL_THRESHOLD:
		_short_path.pop_back()
		if _short_path.is_empty() and _follow_known_imperfect_path_countdown == 0:
			_follow_known_imperfect_path_countdown = KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN


# ========== 0ad-refactor Phase B: PreMove / Move / PostMove (Manager 调用) ==========

## 0ad CCmpUnitMotion::PreMove(MotionState&) 复刻 — Manager 在 5 阶段 step 1 调,所有 unit
## 顺序跑过 一次。
##
## **职责**:把 actor 当前位置 snapshot 进 state.initial_pos / state.pos;按 (currentSpeed,
## lastTurnSpeed, moveRequest) 三元组算 state.need_update;按 `_pushing && moveRequest != NONE`
## 算 state.is_moving + 切 obstr_mgr FLAG_MOVING;state.push 清零(累 push 起点)。
##
## **不变量**(末态):
##   - state.initial_pos == state.pos == actor.position_2d
##   - state.push == ZERO
##   - state.pushing_pressure 上 turn 末已 decay 过(本 turn 累加用此为基础)
##   - state.is_moving == has_target() (老 0ad 还检 m_Pushing flag,我们 unconditional pushing)
##   - obstr_mgr FLAG_MOVING == state.is_moving (如果 actor 注册了 obstr)
##
## **决策来源**:0 A.D. CCmpUnitMotion.h:1036-1058
func pre_move(state: RtsMotionState, actor: RtsBattleActor, world: Variant) -> void:
	state.initial_pos = actor.position_2d
	state.pos = actor.position_2d
	state.push = Vector2.ZERO
	# motion 内部 mirror 也同步,handle_path_update 内部读 _position_2d 算 long path 起点
	_position_2d = actor.position_2d

	state.ignore = not _block_movement
	state.was_obstructed = false
	state.went_straight = false

	# need_update = 在世(暂用 not is_dead 等价) AND (curSpeed != 0 OR lastTurnSpeed != 0 OR
	# moveRequest != NONE)。0 A.D. CCmpUnitMotion.h:1044-1045。
	var alive: bool = actor != null and not actor.is_dead()
	var has_speed: bool = absf(_current_speed) > 0.001 or absf(_last_turn_speed) > 0.001
	var has_request: bool = has_target()
	state.need_update = alive and (has_speed or has_request)

	state.is_moving = _block_movement and has_request
	state.control_group = str(actor.team_id)

	# obstr_mgr FLAG_MOVING 切换(若注册了 unit shape)
	if world != null and world.has_method("get") and actor.obstruction_tag != 0:
		var obstr_mgr_var = world.get("obstruction_manager")
		if obstr_mgr_var != null:
			var obstr_mgr: RtsObstructionManager = obstr_mgr_var as RtsObstructionManager
			obstr_mgr.set_unit_moving_flag(actor.obstruction_tag, state.is_moving)
			# control_group 同步(0ad 也是 PreMove 时 sync;Phase A 起 attach_default 已设过,
			# 此处兜底覆盖,防止 actor.team_id 中途变化时漂)
			obstr_mgr.set_unit_control_group(actor.obstruction_tag, state.control_group)


## 0ad CCmpUnitMotion::Move(MotionState&, dt) 复刻 — Manager 在 5 阶段 step 2 调,所有 unit
## 顺序跑过 一次,推进 state.pos(不直接 mutate actor)。
##
## **职责**:
##   1. handle_path_update:无 long path 时申请,失败累 _failed_movements 阈值后 abort
##   2. perform_move:timeLeft 循环消费 short_path 真 snap 到 waypoint(替代老 _step
##      "永不 snap"),单 tick 可能跨多 waypoint;返 was_obstructed
##
## **不变量**(末态):
##   - state.pos = 走完一段 path 后的位置(可能 snap 到 waypoint,可能在两 waypoint 之间)
##   - state.was_obstructed = perform_move 内是否被 obstacle 阻挡
##   - state.went_straight 仍 false(Phase B try_going_straight_to_target 暂不实现,留 Phase D
##     调优)
##
## **决策来源**:0 A.D. CCmpUnitMotion.h:1060-1070
func move(state: RtsMotionState, _actor: RtsBattleActor, dt: float, world: Variant, facade: RtsPathfinderFacade) -> void:
	if not state.need_update:
		return
	if not has_target():
		return

	# Path 申请 + 失败累加 + fallback。复用 motion 现有 handle_path_update(读 _position_2d,
	# 已在 pre_move 同步)。
	handle_path_update(facade, world)

	# perform_move:timeLeft 循环 + 真 waypoint snap。
	state.was_obstructed = perform_move(state, dt)


## 0ad CCmpUnitMotion::PostMove(MotionState&, dt) 复刻 — Manager 在 5 阶段 step 5 调,把
## state.pos 写回 actor + sync obstr_mgr + update 速度状态 + handle obstructed + emit failed event。
##
## **Phase B 阶段**(push 还没拆 single Push/PushAdjust):PostMove 早跑(Push 之前),让老
## _legacy_pass_2_push_pass 看 PostMove 写回的 actor.position_2d。Phase C 切真 Push/PushAdjust
## 时 PostMove 移到末尾。
##
## **不变量**(末态):
##   - actor.position_2d == state.pos
##   - obstr_mgr.get_shape(actor.obstruction_tag).center == state.pos
##   - _last_turn_speed == _current_speed (本次)→ 下次 pre_move 算 needUpdate 用
##   - _current_speed = (state.pos - state.initial_pos).length() / dt
##   - 若 has_just_failed → emit motion_move_failed event
##
## **决策来源**:0 A.D. CCmpUnitMotion.h:1072-1110
func post_move(state: RtsMotionState, actor: RtsBattleActor, dt: float, world: Variant) -> void:
	if not state.need_update:
		# 完全静止 unit:_last_turn_speed 仍要拷过去(下次 pre_move 算 needUpdate 用)
		_last_turn_speed = _current_speed
		_current_speed = 0.0
		return

	var offset: Vector2 = state.pos - state.initial_pos
	var dist: float = offset.length()

	if state.pos != state.initial_pos:
		actor.position_2d = state.pos
		_position_2d = state.pos
		_update_movement_state(dist / dt)
	else:
		_update_movement_state(0.0)

	# Sync obstr_mgr.move_shape(若注册了 unit shape)
	if world != null and world.has_method("get") and actor.obstruction_tag != 0:
		var obstr_mgr_var = world.get("obstruction_manager")
		if obstr_mgr_var != null:
			var obstr_mgr: RtsObstructionManager = obstr_mgr_var as RtsObstructionManager
			obstr_mgr.move_shape(actor.obstruction_tag, state.pos)

	# Handle obstructed move:若 was_obstructed 且未真位移 → 累 _failed_movements;
	# 若未 obstructed 且有位移 → reset _failed_movements(0ad CCmpUnitMotion.h:1086-1090)。
	if state.was_obstructed and dist < 0.001:
		_failed_movements += 1
		if _failed_movements >= MAX_FAILED_MOVEMENTS:
			_abort_due_to_failure()
	elif not state.was_obstructed and dist > 0.001:
		_failed_movements = 0


## 0ad-refactor Phase B — perform_move:timeLeft 循环 + 真 waypoint snap(替代老 _step "永不
## snap")。0 A.D. CCmpUnitMotion.h:1141-1310 PerformMove 简化复刻(无加减速 / 无转向限制 /
## 无 CheckMovement 验证 — Phase D 调优时按需加)。
##
## **算法**:
##   1. timeLeft = dt 起步
##   2. while timeLeft > 0:
##      a. _short_path 空 → _long_path 非空时 pop next_long 当 short_path single wp;
##         _long_path 也空 → break(到底)
##      b. 算 dist_to_next = ||next_wp - state.pos||;max_dist = walk_speed × timeLeft
##      c. dist_to_next ≤ max_dist:**真 snap** state.pos = next_wp,pop short_path;
##         timeLeft -= dist_to_next / walk_speed;continue
##      d. 否则:走 max_dist 朝 next_wp,timeLeft = 0,break
##
## **关键差异 vs 老 _step**:
##   - 老 _step 每 tick 走 walk_speed × delta 一段,不 snap(ARRIVAL_THRESHOLD pop short 但
##     pos 不 snap 到 waypoint),单 tick 不能跨 waypoint。配 push_pass 互推 → 终态抖动死循环。
##   - 新 perform_move timeLeft 循环 + 真 snap,单 tick 可能 snap 多个 waypoint;到达 final
##     waypoint 时 pos = waypoint,timeLeft 还有剩则 break(没 path 可走)。
##
## **返回**: was_obstructed flag。当前简化版恒 false(Phase D 加 CheckMovement 验证 push 后
## 不穿墙时,fail → return true)。
func perform_move(state: RtsMotionState, dt: float) -> bool:
	var time_left: float = dt
	var was_obstructed: bool = false
	# 0ad-refactor Phase D — 进入时是否有 path:用于区分 "真走完 path"(末态 stop)vs
	# "handle_path_update 给空 path"(_failed_movements 累阈值前不 stop, 让 stuck/unreachable
	# 场景能正常 _abort_due_to_failure)。
	var entered_with_path: bool = (not _short_path.is_empty()) or (not _long_path.is_empty())

	while time_left > 0.0:
		if _short_path.is_empty():
			# 没 short path → 尝试从 long path pop next 当 short
			if _long_path.is_empty():
				break  # 真到底 — pre_move handle_path_update 已申请过 long,空 = 真 unreachable
			var next_long: Vector2 = _long_path.pop_back()
			_short_path.push_back(next_long)

		var next_wp: Vector2 = _short_path.back()
		var to_next: Vector2 = next_wp - state.pos
		var dist_to_next: float = to_next.length()
		var max_dist: float = _walk_speed * time_left

		if dist_to_next <= max_dist:
			# 真 snap 到 waypoint;时间消费 = dist_to_next / walk_speed
			state.pos = next_wp
			_short_path.pop_back()
			if _walk_speed > 0.0001:
				time_left -= dist_to_next / _walk_speed
			else:
				break  # walk_speed = 0 防 div0 死循环
			# 极小步走完,可能 dist_to_next ~ 0 → time_left ~ unchanged;continue 让下次 iter
			# 处理下一 waypoint。loop 上界保护:_short_path.is_empty() + _long_path.is_empty()
			# break 出去。
		else:
			# 一 turn 走不到 next_wp → 朝它走 max_dist
			state.pos += (to_next / dist_to_next) * max_dist
			time_left = 0.0

	# 0ad-refactor Phase D — 真"走完 path" 才 stop():
	#   - entered_with_path: 进入时有 path(handle_path_update 找到 path)
	#   - 末态 short + long 都空:走完了
	#   - 配对 = unit 真抵达 path 终点 → stop(),让 push 不被每 tick handle_path_update 拉回
	#     path 终点(否则 push 推开的位移每 tick 被抹掉,5/6 同 final waypoint 死循环重叠)。
	#
	# 这是 0 A.D. MoveSucceeded 简化版(0ad 用 obstr_mgr.is_in_point_range 判 PossiblyAtDestination,
	# 我们简化为 "path 走完即视为成功")。activity 后续看 actor.position 距 target_pos ≤
	# ARRIVAL_THRESHOLD(4 px)判 activity done;若 path canonicalize 把 goal 推到 unreachable
	# navcell(5/6 case),unit 抵达 path 终点但 distance > ARRIVAL_THRESHOLD,activity 不
	# 会 done — 但 motion 已 stop,push 不被拉回,unit 自然散开。
	#
	# **区分 unreachable**:if entered_with_path = false(handle_path_update 给空 path),
	# 说明 path 真 unreachable,_failed_movements 已在 _request_long_path 内 += 1。不 stop,
	# 让 _failed_movements 累 35 触发 _abort_due_to_failure(stuck_recovery 路径)。
	if entered_with_path and _short_path.is_empty() and _long_path.is_empty():
		stop()
	elif _short_path.is_empty() and _follow_known_imperfect_path_countdown == 0:
		# 还有 long_path 但 short empty → 老 known imperfect 路径(short pathfinder corner case),
		# 等 12 tick 让 long retry。不 stop, 给 path 一次重算机会。
		_follow_known_imperfect_path_countdown = KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN

	return was_obstructed


## 0ad-refactor Phase B — update_movement_state:更新 _current_speed / _last_turn_speed
## (post_move 内调,根据本 turn 实际位移 / dt)。
##
## 0 A.D. CCmpUnitMotion::UpdateMovementState 简化版 — 0ad 还更新 m_LastSpeed / m_FacePointAfterMove
## 等字段,我们 Phase B 阶段不需要(无转向限制)。
func _update_movement_state(actual_speed: float) -> void:
	_last_turn_speed = _current_speed
	_current_speed = actual_speed
