## RtsStuckDetector - 单位卡住检测 + 本地重新寻路 + 失败降级 (P2.3, 避障第 3 层)
##
## 在 P2.2 spatial_hash + steering 解决"动态单位互避"之后, 仍有"地形 / 建筑围困"导致单位
## 想动但动不了的情形 (例: 单位被建筑包围 / A* 起点终点都被堵)。本模块每 tick 跟踪单位真实
## 位移; 持续位移 < 阈值且 agent 仍 "想动" → 触发 local repath (重跑 set_target 让 A* 再试);
## 连续 MAX_REPATH_FAILURES 次仍找不到路径 → 调 controller.abandon_command() 降级为原地待命。
##
## 触发"stuck"的判定 (per actor per tick):
##   - controller / agent 存在
##   - controller 未已 abandon
##   - agent.has_target() == true (设过 set_target, 没 clear)
##   - agent.is_at_final_target() == false (actor 还没到目标 ARRIVAL_THRESHOLD 内)
##   - actor 本 tick 位移 < STUCK_DISPLACEMENT_THRESHOLD (1 px)
##
## "进展中" (即任何一帧位移 ≥ 阈值) 立即 reset stuck_ticks + repath_failures (干净状态)。
##
## Local repath:
##   - 重新调 agent.set_target(_final_target) (相同目标, 重跑 A*) — 单位位置可能因 steering 微调
##     已挪到非 blocking cell, A* 这次能找到。
##   - repath 后 path 仍空 → repath_failures += 1
##   - 失败累计 ≥ MAX_REPATH_FAILURES (3) → controller.abandon_command() (清 activity 切 Idle)
##
## 决定性 (replay bit-equal):
##   - tick 入参 actors 顺序由 procedure 保证 (insertion order)
##   - 内部不调 randf
##   - state.last_pos 记录在 _ensure_state 时初值 = 当前 position, 同种子下同初始位置 → 同 stuck 时序
##
## 决策来源: phase-2-core-systems.md §P2.3
class_name RtsStuckDetector
extends RefCounted


# ========== 调参常量 ==========

## 单 tick 位移 < 此阈值 (像素) 视为"未动"。
## 1.0 = nav agent 浮点抖动 / steering deflection 引起的微小位移不算 stuck。
const STUCK_DISPLACEMENT_THRESHOLD: float = 1.0

## 累计未动 tick 数, 达到此值触发 local repath。
## 20 ticks @ 50ms = 1s; 20 ticks @ 33.33ms (30Hz) ≈ 0.67s — 与 spec 的"1s 内未位移"基本对齐。
const STUCK_TICK_THRESHOLD: int = 20

## 连续 local repath 失败上限, 达到此值触发 controller.abandon_command。
## 3 次 = 给 nav steering 三次重试机会 (因 steering 可能 0.6s 内把单位挪到可通行 cell)。
const MAX_REPATH_FAILURES: int = 3


# ========== 内部 state ==========

## per-actor stuck 状态 (RefCounted 内嵌类)。
class _State extends RefCounted:
	var last_pos: Vector2
	var stuck_ticks: int = 0
	var repath_failures: int = 0


## actor_id (String) → _State
var _states: Dictionary = {}


# ========== Tick ==========

## procedure 在 step 4c integrate 之后调用 (整合后位置才是"本帧实际位置")。
##
## @param units 全部存活 RtsUnitActor (procedure 已过滤建筑 / 死亡)
## @param controllers actor_id → RtsUnitController (procedure._unit_runtimes)
func tick(units: Array, controllers: Dictionary) -> void:
	var seen: Dictionary = {}
	for u in units:
		var unit := u as RtsUnitActor
		if unit == null or unit.is_dead():
			continue
		var aid: String = unit.get_id()
		seen[aid] = true

		var ctrl := controllers.get(aid, null) as RtsUnitController
		if ctrl == null or ctrl.agent == null:
			# 没 controller / 没 agent 的单位 (smoke_navigation 类) — 仅初始化 last_pos, 不参与 stuck
			_ensure_state(aid, unit.position_2d)
			continue

		var state := _ensure_state(aid, unit.position_2d)

		# 不算 stuck 的状态 — reset 计数
		if ctrl.is_command_abandoned() \
				or not ctrl.agent.has_target() \
				or ctrl.agent.is_at_final_target():
			state.stuck_ticks = 0
			state.repath_failures = 0
			state.last_pos = unit.position_2d
			continue

		var disp: float = unit.position_2d.distance_to(state.last_pos)
		if disp < STUCK_DISPLACEMENT_THRESHOLD:
			state.stuck_ticks += 1
			if state.stuck_ticks >= STUCK_TICK_THRESHOLD:
				_trigger_repath(unit, ctrl, state)
				state.stuck_ticks = 0  # reset, 给本次 repath 一个完整观察窗口
		else:
			# 单位移动了 — 干净状态
			state.stuck_ticks = 0
			state.repath_failures = 0

		state.last_pos = unit.position_2d

	# 清理本 tick 已死 / 移除单位的 state
	for stale_id in _states.keys().duplicate():
		if not seen.has(stale_id):
			_states.erase(stale_id)


# ========== 查询 (smoke / debug 用) ==========

func get_stuck_ticks(actor_id: String) -> int:
	if not _states.has(actor_id):
		return 0
	return (_states[actor_id] as _State).stuck_ticks


func get_repath_failures(actor_id: String) -> int:
	if not _states.has(actor_id):
		return 0
	return (_states[actor_id] as _State).repath_failures


func get_tracked_count() -> int:
	return _states.size()


# ========== 内部 ==========

func _ensure_state(actor_id: String, init_pos: Vector2) -> _State:
	var state: _State
	if _states.has(actor_id):
		state = _states[actor_id]
	else:
		state = _State.new()
		state.last_pos = init_pos
		_states[actor_id] = state
	return state


## 触发本地 repath: 重跑 agent.set_target(final_target) 让 A* 再算一次。
## path 仍空 → 计入 repath_failures; ≥ MAX_REPATH_FAILURES 调 controller.abandon_command。
func _trigger_repath(_unit: RtsUnitActor, ctrl: RtsUnitController, state: _State) -> void:
	var agent := ctrl.agent
	if agent == null or not agent.has_target():
		return
	var target_pos: Vector2 = agent.get_final_target()
	agent.set_target(target_pos)
	if agent.has_empty_path():
		state.repath_failures += 1
		if state.repath_failures >= MAX_REPATH_FAILURES:
			ctrl.abandon_command()
			state.repath_failures = 0  # abandon 后下次 clear_command_abandon 重新计
