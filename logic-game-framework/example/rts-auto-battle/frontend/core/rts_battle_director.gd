## RtsBattleDirector - RTS 实时战斗 frontend 调度器 (P2.7 接入流式 events)
##
## 与 hex 例子的 FrontendBattleDirector 不同:
##   - hex Director 是 "离线 replay" 模式: 加载完 ReplayData → 累计 dt 推 frame → 翻译 events 为
##     animator actions 播放; 不持 logic procedure 引用
##   - RTS Director 是 "实时 sim" 模式: 持 procedure 引用, 每 _process(delta) 累 dt 到 SIM_DT
##     就推一次 procedure.tick_once, 当场把 events 与 actor 渲染状态广播给 visualizer
##
## 数据流:
##   _process(delta):
##     accumulator_ms += delta * 1000
##     while accumulator_ms >= SIM_DT_MS and not ended:
##       _capture_prev_positions()        # 把当前 _render_states curr → prev
##       procedure.tick_once()             # logic 推一帧, events 通过 _on_event_sink 进 director
##       _capture_curr_state_and_emit()    # 从 actor.position_2d / hp 投影到 _render_states.curr,
##                                         #   emit actor_render_state_updated 给 visualizer
##       frame_advanced.emit(tick)
##       accumulator_ms -= SIM_DT_MS
##     # 渲染插值: visualizer _process 走 director.get_alpha() 在 prev/curr 间 lerp
##
## 与 actor.position_2d 直读边界:
##   - Director 在 tick boundary 单次读 actor.position_2d / hp (state projection, 不是逐帧 polling)
##   - WorldView / Visualizer 0 处直读 actor (AC6 主断言)
##
## P2.7 不接 hex 的 ReplayData / RenderWorld / ActionScheduler — 那是离线 replay 用的; RTS 是
## 在线 sim, 视觉表演由 visualizer 自己管理动画 / 飘字 (M1 范围: 简化 stub, 不上 RenderWorld)。
##
## 决策来源: phase-2-core-systems.md P2.7 (frontend 流式 events 接入)
class_name RtsBattleDirector
extends Node


# ========== 常量 ==========

## 逻辑帧间隔 (毫秒). 与 RtsAutoBattleProcedure.RTS_TICK_INTERVAL_MS 对齐 (30Hz fixed-tick D3-A).
##
## 调方可通过 set_sim_dt_ms 覆盖 (smoke 走 50ms 老 tick rate 兼容). 一旦 attach() 调用后, 应保持不变.
const DEFAULT_SIM_DT_MS: float = 1000.0 / 30.0


# ========== 信号 ==========

## 每完成一个 sim tick 后 emit (含 visualizer 同步完毕的事件).
signal frame_advanced(tick: int)

## Actor 渲染状态更新 (每 tick 边界 emit 一次).
##   - prev_pos: 上 tick actor.position_2d 的快照
##   - curr_pos: 本 tick actor.position_2d 的快照 (visualizer 在 _process 内 lerp(prev, curr, alpha))
##   - hp / max_hp: 当前 attribute_set 值
##   - is_dead: actor.is_dead()
##
## 建筑也走此信号 (建筑 prev_pos == curr_pos 永远相等, 因为不移动).
signal actor_render_state_updated(
	actor_id: String,
	prev_pos: Vector2,
	curr_pos: Vector2,
	hp: float,
	max_hp: float,
	is_dead: bool,
)

## Attack 事件 (供 visualizer 表演攻击特效 / 飘字).
signal attack_resolved(event: Dictionary)

## Actor 死亡事件 (供 visualizer 切换死亡视觉).
signal actor_died(actor_id: String)

## 战斗结束 emit; result 来自 procedure.get_result() ("left_win" / "right_win" / "draw" / "timeout").
signal battle_ended(result: String)


# ========== 字段 ==========

## 关联 world (持 weakref 防循环引用; world 是 GameWorld owned).
var _world_ref: WeakRef = null

## 关联 procedure (持普通引用 — RtsAutoBattleProcedure 本身是 RefCounted, director attach 期间
## 保活, detach / battle 结束后释放; procedure._event_sink 写到 director 后 director 必须比
## procedure 长寿, 否则 sink callback 调到已释放的 director 会崩).
var _procedure: RtsAutoBattleProcedure = null

## 累积时间 (ms); _process(delta) 累加 delta * 1000.
var _accumulator_ms: float = 0.0

## sim dt (ms). attach() 后从 procedure.get_tick_interval() 读, 默认 DEFAULT_SIM_DT_MS.
var _sim_dt_ms: float = DEFAULT_SIM_DT_MS

## 是否在跑 (attach 后置 true; battle_ended 或 detach 置 false).
var _running: bool = false

## 战斗是否已结束 (避免重复 emit battle_ended).
var _ended: bool = false

## 渲染状态字典: actor_id → { prev_pos: Vector2, curr_pos: Vector2, hp: float, max_hp: float,
##                            is_dead: bool }.
##
## 在 tick boundary 维护; visualizer 通过 actor_render_state_updated signal 拿 (prev, curr).
var _render_states: Dictionary = {}


# ========== 公共 API ==========

## 把 director 接到 world + procedure. 必须在 procedure.start() 之后, tick_once 之前调用.
##
## director 内部:
##   - 接管 procedure._event_sink (设到 director._on_event_sink, 把所有 events 转给 visualizer)
##   - 初始化 _render_states (走 world.get_actors 拿到 RtsBattleActor, hydrate 初始 prev=curr=position_2d)
##   - emit 一次初始 actor_render_state_updated 让已 spawn 的 visualizer 收到起手位置
##
## 注意: 调方若要保留自己的 logger sink, 需要在 director attach 之前包装一层 — 或者用 listener
## 模式扩 director (P2.7 范围内不需要; 主 smoke / logger 不走 director).
func attach(world: RtsWorldGameplayInstance, procedure: RtsAutoBattleProcedure) -> void:
	Log.assert_crash(world != null, "RtsBattleDirector", "attach: world is null")
	Log.assert_crash(procedure != null, "RtsBattleDirector", "attach: procedure is null")
	_world_ref = weakref(world)
	_procedure = procedure
	_sim_dt_ms = procedure.get_tick_interval()

	# 接管 event_sink — director 内部转发给 signal
	# (旧 sink 用法: smoke logger 直接给 procedure 写 sink; director 与那条路径互斥)
	procedure._event_sink = Callable(self, "_on_event_sink")

	# Hydrate 初始渲染状态 (起手 actor 的 position_2d / hp)
	for actor in world.get_actors():
		if actor is RtsBattleActor:
			_seed_render_state(actor as RtsBattleActor)

	_running = true

	# Broadcast 一次起手 render state 让已 spawn 的 visualizer 收到第一帧位置
	# (典型用法: WorldView.bind 在 director.attach 之前完成, visualizer.bind 时
	# director.get_render_state 还是空; attach 后这里补一次 push)
	for actor_id in _render_states.keys():
		var s: Dictionary = _render_states[actor_id]
		actor_render_state_updated.emit(
			actor_id,
			s["prev_pos"],
			s["curr_pos"],
			s["hp"],
			s["max_hp"],
			s["is_dead"],
		)


## 从 procedure 解绑. 战斗 finalize / scene 切换时调用 (防止 sink callback 调到已 free director).
func detach() -> void:
	if _procedure != null and _procedure._event_sink.is_valid():
		var current_sink: Callable = _procedure._event_sink
		# 仅当 sink 还指向 director 时才清; 防止误清调方写的别的 sink (例如 attach 之后又被覆盖)
		if current_sink.get_object() == self:
			_procedure._event_sink = Callable()
	_procedure = null
	_world_ref = null
	_running = false


## 当前 alpha (0.0 → 1.0): 用于 visualizer _process 内对 prev_pos / curr_pos 做 lerp.
##
## 战斗结束后 (ended=true) 永远返回 1.0, 让 visualizer 停在最终位置.
func get_alpha() -> float:
	if _ended:
		return 1.0
	if _sim_dt_ms <= 0.0:
		return 0.0
	return clamp(_accumulator_ms / _sim_dt_ms, 0.0, 1.0)


## 是否还在跑 (attach 之后 → battle_ended 之前).
func is_running() -> bool:
	return _running and not _ended


## 战斗是否已结束.
func is_ended() -> bool:
	return _ended


## 当前 sim tick (procedure 跑了多少帧).
func get_current_tick() -> int:
	if _procedure == null:
		return 0
	return _procedure.get_current_tick()


## 取某 actor 的当前渲染状态 (供 smoke 验证 / debug).
##
## 返回 dict 含 { prev_pos, curr_pos, hp, max_hp, is_dead }; actor 不存在返回空 dict.
func get_render_state(actor_id: String) -> Dictionary:
	var state: Dictionary = _render_states.get(actor_id, {})
	if state.is_empty():
		return {}
	return state.duplicate()


## 当前已注册渲染状态的 actor id 集 (visualizer / smoke 遍历用).
func get_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for k in _render_states.keys():
		result.append(k as String)
	return result


# ========== 生命周期 ==========

func _process(delta: float) -> void:
	if not _running or _ended:
		return
	if _procedure == null:
		return

	# 战斗 already ended (procedure.should_end 但 director 还没 emit) — 立即收尾
	if _procedure.should_end():
		_finalize()
		return

	_accumulator_ms += delta * 1000.0
	while _accumulator_ms >= _sim_dt_ms:
		_step_one_tick()
		_accumulator_ms -= _sim_dt_ms
		if _ended:
			return


# ========== 内部: tick 推进 ==========

## 推一个 sim tick: prev snapshot → procedure.tick_once → curr snapshot + emit signals.
func _step_one_tick() -> void:
	if _procedure == null or _ended:
		return

	var world := _get_world()
	if world == null:
		_finalize()
		return

	# 1. Snapshot prev_pos (把上 tick 的 curr 拷成 prev)
	for state in _render_states.values():
		var s := state as Dictionary
		s["prev_pos"] = s["curr_pos"]

	# 2. Logic tick (events 通过 _on_event_sink 进 director, attack_resolved / actor_died 已 emit)
	_procedure.tick_once()

	# 3. Snapshot curr_pos / hp / dead, 处理新增 actor / 移除 actor
	_refresh_render_states_post_tick(world)

	# 4. 通知所有 visualizer (建筑也走 — prev == curr 不动)
	for actor_id in _render_states.keys():
		var s2: Dictionary = _render_states[actor_id]
		actor_render_state_updated.emit(
			actor_id,
			s2["prev_pos"],
			s2["curr_pos"],
			s2["hp"],
			s2["max_hp"],
			s2["is_dead"],
		)

	# 5. tick advanced + 战斗结束判定
	frame_advanced.emit(_procedure.get_current_tick())

	if _procedure.should_end():
		_finalize()


## 起手 hydrate 渲染状态: 走 world.get_actors 把当前 RtsBattleActor 写入 _render_states.
##
## 与 _refresh_render_states_post_tick 不同点: 这里是创建期, prev = curr (无动画起点).
func _seed_render_state(actor: RtsBattleActor) -> void:
	if actor == null:
		return
	var actor_id := actor.get_id()
	if actor_id == "":
		return
	var pos: Vector2 = actor.position_2d
	var hp: float = 0.0
	var max_hp: float = 0.0
	var attrs: BaseGeneratedAttributeSet = actor.get_attribute_set()
	if attrs != null:
		var raw: RawAttributeSet = attrs.get_raw()
		if raw != null:
			hp = raw.get_current_value("hp")
			max_hp = raw.get_current_value("max_hp")
	_render_states[actor_id] = {
		"prev_pos": pos,
		"curr_pos": pos,
		"hp": hp,
		"max_hp": max_hp,
		"is_dead": actor.is_dead(),
		"team_id": actor.get_team_id(),
	}


## 每 tick 后从 world 拉最新状态: 新增 actor 入字典 (prev=curr=当前 pos), 移除的清掉,
## 仍在的更新 curr_pos / hp / is_dead.
func _refresh_render_states_post_tick(world: RtsWorldGameplayInstance) -> void:
	var seen: Dictionary = {}
	for actor in world.get_actors():
		if not (actor is RtsBattleActor):
			continue
		var ra := actor as RtsBattleActor
		var actor_id := ra.get_id()
		seen[actor_id] = true
		if not _render_states.has(actor_id):
			# 新增 actor (P2.5 起 spawner / P2.6 PlaceBuildingCommand 战斗中创建)
			_seed_render_state(ra)
			continue
		var state: Dictionary = _render_states[actor_id]
		state["curr_pos"] = ra.position_2d
		var attrs: BaseGeneratedAttributeSet = ra.get_attribute_set()
		if attrs != null:
			var raw: RawAttributeSet = attrs.get_raw()
			if raw != null:
				state["hp"] = raw.get_current_value("hp")
				state["max_hp"] = raw.get_current_value("max_hp")
		state["is_dead"] = ra.is_dead()

	# 清掉不再存在的 actor (world.remove_actor 之类)
	var to_remove: Array[String] = []
	for actor_id in _render_states.keys():
		if not seen.has(actor_id):
			to_remove.append(actor_id as String)
	for rid in to_remove:
		_render_states.erase(rid)


# ========== 内部: events ==========

## procedure 主循环 step 5 调; events 是 EventCollector.collect() 返回的 array (不消费).
##
## director 转发关心的 event kinds 为 signal: attack_resolved / actor_died.
## damage_dealt 没单独 signal, 因为 hp 变化已通过 _refresh_render_states_post_tick →
## actor_render_state_updated.hp 字段广播.
func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		if event == null:
			continue
		var kind: String = event.get("kind", "") as String
		if kind == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			attack_resolved.emit(event)
		elif kind == RtsBattleEvents.ACTOR_DIED_EVENT:
			var dead_id: String = event.get("actor_id", "") as String
			if dead_id != "":
				actor_died.emit(dead_id)


# ========== 内部: finalize ==========

func _finalize() -> void:
	if _ended:
		return
	_ended = true
	_running = false

	# 用 finish 把 procedure 收尾 (mark in_combat=false, recorder 停掉返回 timeline dict).
	# director 不存 timeline (smoke 用 procedure.get_recorder().stop_recording 自己拿; 同步走完
	# director.detach 后 procedure 可继续被调方持有, recorder 再通过 procedure 拿).
	#
	# 注意: 不能在这里调 _procedure.finish() — procedure.finish 会改 finished 状态, 但调方
	# (demo_rts_frontend / smoke) 可能还要拿 procedure.get_result(). 让调方决定何时 finish.
	var result: String = ""
	if _procedure != null:
		result = _procedure.get_result()
	battle_ended.emit(result)


# ========== 工具 ==========

func _get_world() -> RtsWorldGameplayInstance:
	if _world_ref == null:
		return null
	return _world_ref.get_ref() as RtsWorldGameplayInstance
