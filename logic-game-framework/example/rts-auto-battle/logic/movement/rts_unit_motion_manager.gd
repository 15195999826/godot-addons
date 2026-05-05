## RtsUnitMotionManager - 中央协调 motion + push 的 manager(0 A.D. CCmpUnitMotionManager 复刻)
##
## **职责**:每 sim tick 走 5 阶段处理所有 motion-bearing actor:
##   1. PreMove — snapshot state, set need_update / is_moving / FLAG_MOVING
##   2. Move — 调 motion.move 消费 path,推进 state.pos(不直接 mutate actor)
##   3. Push — pairwise (i, j) i.id < j.id 累 state.push,不直接 apply
##   4. PushAdjust — push.length < MinimalPushing 清零,pressure dampen,验证不穿墙,state.pos += state.push
##   5. PostMove — state.pos → actor.position_2d + obstr_mgr.move_shape sync
##
## **Phase A (当前 skeleton)**: 5 阶段方法已存在但 default 走老路径 — move_units 内部 = Pass 1
## component.tick + Pass 2 push_pass × M8_PUSH_PASS_ITERATIONS,行为等价 procedure 老
## `_tick_motion_bearing_actors`。Phase B 切 PreMove/Move/PostMove 真实现替代 Pass 1, Phase C
## 切 Push/PushAdjust 真实现替代 Pass 2, 13 处 fix 全落。
##
## **生命周期**:procedure._init 末构造,持 world 引用。procedure._world_tick step 4g 调
## `move_units(alive_actors, dt)` 一行替代老 `_tick_motion_bearing_actors`。
##
## **Determinism**:`_collect_motion_actors` + sort by `RtsAutoBattleProcedure._compare_motion_actor`
## (kind, spawn_seq) 数值复合 key (R5 P1 #1) — replay seed=42 deep-equal 关键。
##
## **决策来源**:
##   - 0 A.D. CCmpUnitMotionManager(CCmpUnitMotionManager.h:31-162 + _System.cpp:406-642)
##   - plan: async-herding-newt.md
class_name RtsUnitMotionManager
extends RefCounted


# ========== 常量(0ad pathfinder.xml 默认值,_System.cpp:180-273 Init 加载) ==========

## 0 A.D. 用 5/7(_System.cpp:54-58 注释:"Clearances are full-width instead of half + sqrt(2)/2
## 圆内切方校正"),意思是 0ad 的 clearance 是**全宽方边**,要 / 2 转半径 + sqrt(2)/2 内切修正,
## 合并 ≈ 5/7 ≈ 0.71。
##
## **我们的 clearance 是 collision_radius**(直接半径圆),不需要"全宽 / 2"—— 也不需要圆内切方
## 修正(我们物理就是圆,不是方),所以 PUSHING_CORRECTION = 1.0。
##
## 改 5/7 → 1.0 是 unit conversion fix,不是调参数(0 A.D. 算法精神保持)。
const PUSHING_CORRECTION: float = 1.0

## 单位互推半径乘子 — Push 触发距离 = combinedClearance × PUSHING_RADIUS_MULTIPLIER。
const PUSHING_RADIUS_MULTIPLIER: float = 1.6  # 8/5

## 移动单位之间额外触发距离扩展(像素)。
const MOVING_PUSH_EXTENSION: float = 2.5  # 5/2

## 静止单位之间额外触发距离扩展(像素)。
const STATIC_PUSH_EXTENSION: float = 2.0

## 移动单位之间 spread 比例 — combinedClearance × PUSHING_RADIUS_MULTIPLIER × spread = "全力 push"
## 距离;超过此距离 distanceFactor < 1 衰减,在 maxDist 处 = 0。
const MOVING_PUSHING_SPREAD: float = 0.625  # 5/8

## 静止单位之间 spread 比例。
const STATIC_PUSHING_SPREAD: float = 0.625  # 5/8

## 单 tick push 长度阈值 — 低于此值视为静态平衡,push 清零不动(防微抖关键)。
##
## **dt-aware 修正**:0 A.D. 默认 0.2 是 5 Hz turn (200 ms) 阈值 = 1 px/s 速度。我们 30 Hz tick
## 同速度阈值 = 1 × 0.0333 = 0.033 px/tick。0.025 给 pressure dampen 后浮点累积余量(避免
## dampen 后 push 跌破阈值 → 单位永久卡住边界)。
##
## **重要**:用 0.2(0ad 默认)直接套 30 Hz 会让单 tick push (~0.04 px) × dampen (~0.9) 永远
## 跌破 0.2 → push 完全失效,trace 验证 8 unit 终态有完全重叠对(d=0)。0.025 阈值跑 trace
## verified 不再卡住。
const MINIMAL_PUSHING: float = 0.025

## Pressure 累加强度乘子(per-pair-per-tick,单 push pair 累 STATIC_FACTOR + DISTANCE_FACTOR
## 加权值)。
##
## **dt-aware 修正**:0 A.D. 默认 1.0 是 5 Hz turn rate;我们 30 Hz tick 累 6 倍频次,
## 单 tick 应缩 1/6 ≈ 0.167 让稳态 pressure 跟 0ad 等价。
const PUSHING_PRESSURE_STRENGTH: float = 1.0 / 6.0

## Pressure per-tick 衰减乘子 — pressure *= decay each tick(0ad Move 后立刻 decay,
## _System.cpp:474)。
##
## **dt-aware 修正**:0 A.D. 默认 0.6 是 5 Hz turn 衰减率;我们 30 Hz tick, 6 tick 后累乘
## decay 应 = 0.6 → 单 tick decay = pow(0.6, 1/6) ≈ 0.918。
const PUSHING_PRESSURE_DECAY: float = 0.918  # pow(0.6, 1.0/6.0) ≈ 0.6 per "0ad turn" (6 tick)

## dt 时间因子分母 — Push 力 = dir × distanceFactor × weight_ratio × (dt / PUSHING_REDUCTION_FACTOR)。
const PUSHING_REDUCTION_FACTOR: float = 2.0

## 单 pair Push 最大 multiplier 系数(数值稳定性,_System.cpp:76)。
const MAX_PUSHING_MULTIPLIER: float = 4.0

## 距离因子上限(完全重叠时取此值,_System.cpp:70)。
const MAX_DISTANCE_FACTOR: float = 2.5  # 5/2

## 擦肩交叉判定阈值 —(a.pos - b.pos).Dot(a.initial - b.initial) < 此值时给 perpendicular nudge。
const PERPENDICULAR_NUDGE_THRESHOLD: float = -0.1

## Pressure 上限 / 阻塞最小压力 / Push 阻尼上限。
const MAX_PRESSURE: int = 255
const MAX_PUSH_DAMPING_PRESSURE: int = 160
const MIN_PRESSURE_IF_OBSTRUCTED: int = 80

## Pressure 累加常量(_System.cpp:98-99)。
const PRESSURE_STATIC_FACTOR: float = 2.0
const PRESSURE_DISTANCE_FACTOR: float = 5.0


# ========== 持有 ==========

## World 引用 — Manager 通过此拿 obstruction_manager / pathfinder_facade。
var _world: RtsWorldGameplayInstance = null

## actor_id → RtsMotionState;Manager 自己维护。Phase A 阶段空字典(legacy 路径不依赖 state),
## Phase B 起 register / unregister 真用,跟 motion-bearing actor spawn / death 同步。
var _states: Dictionary = {}


# ========== 初始化 ==========

func _init(p_world: RtsWorldGameplayInstance) -> void:
	Log.assert_crash(p_world != null, "RtsUnitMotionManager", "_init: world is null")
	_world = p_world


# ========== Tick 入口 ==========

## procedure._world_tick step 4g 调用 — 完整 0ad CCmpUnitMotionManager 5 阶段 + decay。
##
## **Phase C (当前)**:完整 0ad pipeline:
##   1. PreMove — snapshot state, set need_update / is_moving / FLAG_MOVING
##   2. Move — perform_move (timeLeft 循环 + 真 snap) 推 state.pos
##   3. DecayPressure — 0ad Move 后立刻 decay (_System.cpp:474)
##   4. Push (pairwise) — i.id < j.id 累 state.push, 累 state.pushing_pressure
##   5. PushAdjust — push.length < MinimalPushing 清零 / pressure dampen / state.pos += push
##   6. PostMove — state.pos → actor.position_2d + obstr_mgr.move_shape
##   7. EmitFailed — has_just_failed → emit motion_move_failed event
##
## abort dispatch 留 procedure(_unit_runtimes 私有),procedure 在 move_units 后调
## `_dispatch_motion_failed(world, alive_actors)`。
func move_units(alive_actors: Array, dt: float) -> void:
	var motion_actors: Array = _collect_motion_actors(alive_actors)
	if motion_actors.is_empty():
		_states.clear()  # 全离场 — 清 stale state
		return
	motion_actors.sort_custom(RtsAutoBattleProcedure._compare_motion_actor)

	_ensure_states(motion_actors)

	_pre_move_pass(motion_actors)
	_move_pass(motion_actors, dt)
	_decay_pressure_pass(motion_actors)
	_push_pairwise_pass(motion_actors, dt)
	_push_adjust_pass(motion_actors)
	_post_move_pass(motion_actors, dt)
	_emit_motion_failed_pass(motion_actors)


# ========== Phase B: PreMove / Move / PostMove ==========

## Step 1 — PreMove: snapshot state (initial_pos = actor.position_2d, push=0, need_update,
## is_moving + obstr_mgr FLAG_MOVING 切换). 0ad CCmpUnitMotion.h:1036-1058。
func _pre_move_pass(motion_actors: Array) -> void:
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var state: RtsMotionState = _states[actor.get_id()]
		var component: RtsMotionComponent = actor.motion_component as RtsMotionComponent
		component.motion.pre_move(state, actor, _world)


## Step 2 — Move: handle_path_update + perform_move (timeLeft 循环 + 真 snap)推进 state.pos
## 不直接 mutate actor。0ad CCmpUnitMotion.h:1060-1070。
func _move_pass(motion_actors: Array, dt: float) -> void:
	var facade: RtsPathfinderFacade = _world.pathfinder_facade
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var state: RtsMotionState = _states[actor.get_id()]
		var component: RtsMotionComponent = actor.motion_component as RtsMotionComponent
		component.motion.move(state, actor, dt, _world, facade)


## Step 3 — PostMove (Phase B 早跑, push 之前): state.pos → actor.position_2d, sync obstr_mgr,
## update _current_speed / _last_turn_speed。0ad CCmpUnitMotion.h:1072-1110。
##
## **Phase C** 切真 Push/PushAdjust 时,PostMove 移到末尾(write back after push apply)。
func _post_move_pass(motion_actors: Array, dt: float) -> void:
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var state: RtsMotionState = _states[actor.get_id()]
		var component: RtsMotionComponent = actor.motion_component as RtsMotionComponent
		component.motion.post_move(state, actor, dt, _world)


## Step 4 — Emit MoveFailed event 给 actor(post_move 内部累 _failed_movements 阈值后调
## _abort_due_to_failure 设 _just_failed flag,这里 walk 全部 actor emit event)。
##
## 不 consume flag — procedure._dispatch_motion_failed 还会 consume + dispatch controller
## (两件事独立:event for replay log, dispatch for activity reaction)。
func _emit_motion_failed_pass(motion_actors: Array) -> void:
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var component: RtsMotionComponent = actor.motion_component as RtsMotionComponent
		component._emit_motion_failed_if_needed()


# ========== Phase C: 真 Push + PushAdjust + Pressure decay(0ad 完整复刻) ==========

## Step 3 — Decay pressure(0ad CCmpUnitMotion_System.cpp:473-474:Move 完后 decay,让本 turn
## Push pass 看到的是 decay 后的 pressure)。
##
## **Pressure 累加循环**:Push pass 累 → PushAdjust dampen 用此 pressure → 下 turn Move 后 decay。
func _decay_pressure_pass(motion_actors: Array) -> void:
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var state: RtsMotionState = _states[actor.get_id()]
		state.pushing_pressure = int(floor(PUSHING_PRESSURE_DECAY * float(state.pushing_pressure)))


## Step 4 — Push (pairwise) — 0ad CCmpUnitMotionManager::Push 完整复刻(_System.cpp:645-778)。
##
## **13 处 0ad diff fix 全在此**:
##   #1 — sameControlGroup → movingPush=0, maxDist=combinedClearance, 不做 nudge
##   #2 — pushing_pressure 累加(后续 PushAdjust dampen)
##   #3 — movingPush == 1: return (一动一静不互推)
##   #5 — PERPENDICULAR_NUDGE for 擦肩交叉
##   #6 — 中央协调:累 state.push 不直接 mutate actor
##   #8 — average position offset (state.pos + state.initial_pos) / 2
##   #9 — PUSHING_CORRECTION (5/7) 圆/方校正
##   #10 — timeFactor = dt / PUSHING_REDUCTION_FACTOR
##   #11 — weight ratio
##
## **Pairwise i.id < j.id**:确保 each pair 算一次,a 累正向 push,b 累负向 push 同时。
func _push_pairwise_pass(motion_actors: Array, dt: float) -> void:
	var n: int = motion_actors.size()
	for i in n:
		var actor_i: RtsBattleActor = motion_actors[i] as RtsBattleActor
		var state_i: RtsMotionState = _states[actor_i.get_id()]
		if state_i.ignore:
			continue
		var motion_i: RtsUnitMotion = (actor_i.motion_component as RtsMotionComponent).motion
		for j in range(i + 1, n):
			var actor_j: RtsBattleActor = motion_actors[j] as RtsBattleActor
			var state_j: RtsMotionState = _states[actor_j.get_id()]
			if state_j.ignore:
				continue
			var motion_j: RtsUnitMotion = (actor_j.motion_component as RtsMotionComponent).motion
			_push(state_i, motion_i, actor_i, state_j, motion_j, actor_j, dt)


## 单 pair Push 计算 — 累 state.push (a += pushDir, b -= pushDir) + 累 state.pushing_pressure。
##
## 严格按 0ad CCmpUnitMotionManager::Push (_System.cpp:645-778) 复刻;参数命名 a/b 同 0ad 原文。
func _push(
	a_state: RtsMotionState,
	a_motion: RtsUnitMotion,
	a_actor: RtsBattleActor,
	b_state: RtsMotionState,
	b_motion: RtsUnitMotion,
	b_actor: RtsBattleActor,
	dt: float,
) -> void:
	# Layer mismatch 不互推(GROUND vs AIR — 0ad 用 ICmpObstruction filter, 我们直接 layer 比)
	if a_actor.movement_layer != b_actor.movement_layer:
		return

	var moving_push: int = (1 if a_state.is_moving else 0) + (1 if b_state.is_moving else 0)
	var same_control_group: bool = (
		a_state.control_group != "" and a_state.control_group == b_state.control_group
	)

	# **fix #1**: sameControlGroup → movingPush = 0(同队按 STATIC pair 处理,maxDist 严格更小,
	# 不做 perpendicular nudge,push 力度小)
	if same_control_group:
		moving_push = 0

	# **fix #3**: movingPush == 1 (一动一静) 不互推
	if moving_push == 1:
		return

	# **fix #9**: combinedClearance × PUSHING_CORRECTION (5/7 圆/方校正)
	var combined_clearance: float = (a_motion.get_clearance() + b_motion.get_clearance()) * PUSHING_CORRECTION
	var max_dist: float = combined_clearance
	if not same_control_group:
		max_dist = combined_clearance * PUSHING_RADIUS_MULTIPLIER + (
			MOVING_PUSH_EXTENSION if moving_push > 0 else STATIC_PUSH_EXTENSION
		)
	combined_clearance = max_dist * (
		MOVING_PUSHING_SPREAD if moving_push > 0 else STATIC_PUSHING_SPREAD
	)

	# **fix #8**: average position offset((a.pos + a.initial) - (b.pos + b.initial)) / 2
	var offset: Vector2 = ((a_state.pos + a_state.initial_pos) - (b_state.pos + b_state.initial_pos)) * 0.5

	if offset.length() > max_dist:
		return  # 距离超出 — 不互推

	var offset_length: float = 0.0
	var perpendicular_nudge: bool = false

	# **fix #5**: PERPENDICULAR_NUDGE — 擦肩交叉(pos diff 与 initial diff 反向,Dot < 阈值)
	# 给侧推而不是直推。sameControlGroup 跳过(formation 内部不做 nudge,0ad 设计如此)
	if not same_control_group:
		var pos_diff: Vector2 = a_state.pos - b_state.pos
		var initial_diff: Vector2 = a_state.initial_pos - b_state.initial_pos
		if pos_diff.dot(initial_diff) < PERPENDICULAR_NUDGE_THRESHOLD:
			# perpendicular nudge
			var pos_delta: Vector2 = pos_diff - initial_diff
			var perp: Vector2 = Vector2(-pos_delta.y, pos_delta.x)
			# 选 dot 更 negative 的方向 = 远离对手
			if offset.dot(perp) < (-offset).dot(perp):
				offset = -perp
			else:
				offset = perp
			var olen: float = offset.length()
			if olen > 0.0001:
				offset = offset / olen * 3.0  # 强 effect
			offset_length = 0.0  # 标记跳过 distanceFactor 距离衰减(用 MAX 直接)
			perpendicular_nudge = true

	if not perpendicular_nudge:
		offset_length = offset.length()
		if offset_length <= 0.0001:
			# 完全重叠 — parity 选 arbitrary 方向(deterministic, 不调 randf)
			# 0ad: bool dir = a.first % 2; 我们用 entity_id char-sum parity
			var parity: int = _actor_id_parity(a_actor.get_id())
			offset = Vector2(1.0 if parity == 0 else 0.0, 0.0 if parity == 0 else 1.0)
			offset_length = 0.0001
		else:
			offset = offset / offset_length

	# distanceFactor (重叠时 MAX,远离时衰减到 0)
	var distance_factor: float
	var spread_diff: float = max_dist - combined_clearance
	if spread_diff <= 0.0 or offset_length < combined_clearance * 0.5:
		distance_factor = MAX_DISTANCE_FACTOR
	else:
		distance_factor = clampf((max_dist - offset_length) / spread_diff, 0.0, MAX_DISTANCE_FACTOR)

	a_state.need_update = true
	b_state.need_update = true

	var pushing_dir: Vector2 = offset * distance_factor

	# **fix #10**: timeFactor = dt / PUSHING_REDUCTION_FACTOR
	var time_factor: float = dt / PUSHING_REDUCTION_FACTOR
	var max_pushing: float = time_factor * MAX_PUSHING_MULTIPLIER

	# **fix #11**: weight ratio — a 累 (b_weight / a_weight) × time, b 累 -(a_weight / b_weight) × time
	var a_weight: float = a_motion.get_weight()
	var b_weight: float = b_motion.get_weight()
	a_state.push += pushing_dir * minf(b_weight * time_factor / a_weight, max_pushing)
	b_state.push -= pushing_dir * minf(a_weight * time_factor / b_weight, max_pushing)

	# **fix #2**: pushing_pressure 累加(后续 PushAdjust 用此 dampen push)
	var added_pressure: int = int(maxf(0.0, (
		PRESSURE_STATIC_FACTOR + (distance_factor - 2.0 / 3.0) * PRESSURE_DISTANCE_FACTOR
	) * PUSHING_PRESSURE_STRENGTH))
	a_state.pushing_pressure = mini(MAX_PRESSURE, a_state.pushing_pressure + added_pressure)
	b_state.pushing_pressure = mini(MAX_PRESSURE, b_state.pushing_pressure + added_pressure)


## Step 5 — PushAdjust:apply state.push 到 state.pos(_System.cpp:546-622)。
##
## **fix #7**: push 后位置不穿墙验证 — Phase C 简化为 distance check(完整 obstruction
## CheckMovement 留 Phase D 调优)
##
## Push 后清零(下 turn 重新累)。
func _push_adjust_pass(motion_actors: Array) -> void:
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var state: RtsMotionState = _states[actor.get_id()]
		if state.ignore:
			state.push = Vector2.ZERO
			continue

		# MinimalPushing 阈值 — 防微抖
		if state.push.length() < MINIMAL_PUSHING:
			state.push = Vector2.ZERO
			continue

		# wasObstructed 检查:本 turn 有移动尝试 + push 把 pos 推离 initial 走向 → 单位被强行
		# 推开,标 obstructed 升 pressure。0ad _System.cpp:584-590。
		if state.pos != state.initial_pos:
			var moved: Vector2 = state.pos - state.initial_pos
			var pushed: Vector2 = state.pos + state.push - state.initial_pos
			if moved.dot(pushed) < 0.5 and state.pushing_pressure > 30:
				state.was_obstructed = true
				state.pushing_pressure = maxi(MIN_PRESSURE_IF_OBSTRUCTED, state.pushing_pressure)

		# Pressure dampen — 拥挤区单位"陷"住,push 力度被吃掉(_System.cpp:600)
		var damping: int = mini(MAX_PUSH_DAMPING_PRESSURE, state.pushing_pressure)
		var damped_factor: float = float(MAX_PRESSURE - damping) / float(MAX_PRESSURE)
		state.push *= damped_factor

		# 应用 push 到 state.pos (PostMove 后续写回 actor)
		state.pos += state.push
		state.push = Vector2.ZERO


## actor_id 字符 unicode 之和的奇偶性(0ad 用 `bool dir = a.first % 2`,我们 entity_id 是
## 字符串无 numeric ID, 用 char-sum parity 等价)。
##
## **deterministic** — 同 id 同结果, 不依赖 RNG / hash 实现细节。复刻自 RtsUnitSteering 老
## helper(M7d.5b 本来就有, 移到 Manager 用)。
static func _actor_id_parity(actor_id: String) -> int:
	var s: int = 0
	for i in range(actor_id.length()):
		s += actor_id.unicode_at(i)
	return s % 2


# ========== 内部: 工具 ==========

## 过滤 motion-bearing(motion_component != null);返回新 Array(不破坏调方 alive_actors)。
func _collect_motion_actors(alive_actors: Array) -> Array:
	var motion_actors: Array = []
	for a in alive_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		if actor != null and actor.motion_component != null:
			motion_actors.append(actor)
	return motion_actors


## Register / unregister _states 字典 — 第一次见到的 actor 创建 RtsMotionState, 集合里没出现
## 的 actor 移除 state(死亡 / 离场)。
##
## **Phase B 阶段** 此为唯一 lifecycle 入口;Phase C/D 可改成 spawn / death event 驱动 真 lifecycle。
func _ensure_states(motion_actors: Array) -> void:
	var seen: Dictionary = {}
	for a in motion_actors:
		var actor: RtsBattleActor = a as RtsBattleActor
		var aid: String = actor.get_id()
		seen[aid] = true
		if not _states.has(aid):
			_states[aid] = RtsMotionState.new(aid, str(actor.team_id))
	# Drop stale state (motion_component cleared / actor dead removed)
	for aid in _states.keys():
		if not seen.has(aid):
			_states.erase(aid)
