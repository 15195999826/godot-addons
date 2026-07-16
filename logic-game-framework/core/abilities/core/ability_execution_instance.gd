class_name AbilityExecutionInstance
extends RefCounted

const STATE_EXECUTING := "executing"
const STATE_COMPLETED := "completed"
const STATE_CANCELLED := "cancelled"

var id: String
var timeline_id: String
var _timeline: TimelineData = null
var _tag_actions: Array[TagActionsEntry] = []
var _on_timeline_start_actions: Array[Action.BaseAction] = []
var _on_timeline_end_actions: Array[Action.BaseAction] = []
var _on_cancel_actions: Array[Action.BaseAction] = []
var _trigger_event_dict: Dictionary = {}
var _ability_ref: AbilityRef = null
var _game_state_provider_ref: WeakRef = null
var _elapsed: float = 0.0
var _loops_completed: int = 0
var _state: String = STATE_EXECUTING
var _triggered_tags: Dictionary = {}

## §0.4 execution-local state scratchpad
##
## 表达"同一次施法前段结果影响后段"的短生命周期状态 (例 Shadow Step 把
## CAST 阶段瞬移结果 shadow_step.teleport_success 写进来, HIT 阶段读出来)。
##
## 合同:
## - owner = AbilityExecutionInstance; ExecutionContext 只携带引用作访问入口。
## - 同一次 execution 的所有 tag context / callback context 共享同一 Dictionary。
## - 不同 execution 之间天然隔离 (每次施法新 instance 新字典)。
## - key 必须带 namespace (e.g. "shadow_step.teleport_success"); 由
##   ExecutionContext.set/get_execution_state assert.
## - 写入 action 必须 deterministic; 不写 wall-clock / 随机 / mutable singleton。
## - replay 路径 = 重 execute 推导 (event stream 不记录 execution_state)。
var _execution_state: Dictionary = {}

## game_state_provider 不作为强引用字段缓存。
##
## 正常 tick 仍由调用链传入；这里只保留 WeakRef，供 revoke/expire 等取消路径执行
## on_cancel 清理。这样既能释放 reservation/gate，又不会形成 battle → ability → execution → battle 强引用环。
func _init(
	p_timeline_id: String,
	p_tag_actions: Array[TagActionsEntry],
	p_on_timeline_start_actions: Array[Action.BaseAction],
	p_on_timeline_end_actions: Array[Action.BaseAction],
	p_trigger_event_dict: Dictionary,
	p_ability_ref: AbilityRef,
	p_on_cancel_actions: Array[Action.BaseAction] = [],
	p_game_state_provider: Variant = null
) -> void:
	id = IdGenerator.generate("execution")
	timeline_id = p_timeline_id
	_timeline = TimelineRegistry.get_timeline(timeline_id)
	_tag_actions = p_tag_actions
	_on_timeline_start_actions = p_on_timeline_start_actions
	_on_timeline_end_actions = p_on_timeline_end_actions
	_on_cancel_actions = p_on_cancel_actions
	_trigger_event_dict = p_trigger_event_dict
	_ability_ref = p_ability_ref
	if p_game_state_provider is Object:
		_game_state_provider_ref = weakref(p_game_state_provider)
	if _timeline == null:
		Log.warning("AbilityExecutionInstance", "Timeline not found: %s" % timeline_id)

func get_elapsed() -> float:
	return _elapsed

func get_state() -> String:
	return _state

func is_executing() -> bool:
	return _state == STATE_EXECUTING

func is_completed() -> bool:
	return _state == STATE_COMPLETED

func is_cancelled() -> bool:
	return _state == STATE_CANCELLED

func get_trigger_event() -> Dictionary:
	return _trigger_event_dict

## 同步触发 timeline 生命周期 action（on_timeline_start 在 activate / loop 重启时调；
## on_timeline_end 在 timeline 完成本轮时调）。
## current_tag 用于构建 ExecutionContext 的 current_tag 字段，外部传入描述性标识。
func fire_sync_actions(actions: Array[Action.BaseAction], current_tag: String,
		game_state_provider: Variant, stop_on_terminal: bool = true) -> void:
	if actions.is_empty():
		return
	var exec_context := _build_execution_context(current_tag, game_state_provider)
	for action in actions:
		if action != null:
			action.execute(exec_context)
			action._verify_unchanged()
			if stop_on_terminal and _state != STATE_EXECUTING:
				break
		else:
			Log.warning("AbilityExecutionInstance", "sync action entry is null")

func tick(dt: float, game_state_provider: Variant) -> Array[String]:
	if _state != STATE_EXECUTING:
		return []
	if _timeline == null:
		_state = STATE_COMPLETED
		return []

	# loop 模式下要求 dt <= total_duration，否则单次 tick 会跨越整个周期导致漏 tick
	if _timeline.loop:
		Log.assert_crash(
			dt <= _timeline.total_duration,
			"AbilityExecutionInstance",
			"Loop timeline requires dt <= total_duration (dt=%f, total=%f, timeline=%s)" % [dt, _timeline.total_duration, timeline_id]
		)

	var previous_elapsed := _elapsed
	_elapsed += dt

	var triggered_this_tick: Array[Dictionary] = []
	var tags: Dictionary = _timeline.tags
	for tag_name in tags.keys():
		var tag_time := float(tags[tag_name])
		if _triggered_tags.has(tag_name):
			continue
		if not _should_trigger(previous_elapsed, tag_time):
			continue
		_triggered_tags[tag_name] = true
		triggered_this_tick.append({
			"tagName": tag_name,
			"tagTime": tag_time,
			"elapsed": _elapsed,
		})

	triggered_this_tick.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tagTime"] < b["tagTime"])

	var triggered_tags: Array[String] = []
	for entry in triggered_this_tick:
		var tag_name: String = entry["tagName"]
		var actions := _resolve_actions_for_tag(tag_name)
		Log.debug("AbilityExecutionInstance", "触发 %s" % tag_name)
		_execute_actions_for_tag(tag_name, actions, game_state_provider)
		triggered_tags.append(tag_name)
		if _state != STATE_EXECUTING:
			return triggered_tags

	if _elapsed >= _timeline.total_duration:
		# 本轮结束：先跑 on_timeline_end；回调可取消，取消后不得覆盖为 completed。
		fire_sync_actions(_on_timeline_end_actions, "__timeline_end__", game_state_provider)
		if _state != STATE_EXECUTING:
			return triggered_tags
		if _timeline.loop and (_timeline.max_loops <= 0 or _loops_completed + 1 < _timeline.max_loops):
			# 进入下一轮：重置计时器 + 已触发 tags，跑 on_timeline_start
			_loops_completed += 1
			_elapsed = 0.0
			_triggered_tags.clear()
			fire_sync_actions(_on_timeline_start_actions, "__timeline_start__", game_state_provider)
		else:
			_state = STATE_COMPLETED
			Log.debug("AbilityExecutionInstance", "执行完成")

	return triggered_tags

func cancel(game_state_provider: Variant = null) -> void:
	if _state != STATE_EXECUTING:
		return
	_state = STATE_CANCELLED
	var provider := game_state_provider
	if provider == null and _game_state_provider_ref != null:
		provider = _game_state_provider_ref.get_ref()
	fire_sync_actions(_on_cancel_actions, "__timeline_cancel__", provider, false)
	Log.debug("AbilityExecutionInstance", "执行取消")

## 判断 tag 是否应在当前 tick 触发（纯数学区间判断：previous < tag_time <= current）
func _should_trigger(previous_elapsed: float, tag_time: float) -> bool:
	return previous_elapsed < tag_time and _elapsed >= tag_time

func _execute_actions_for_tag(tag_name: String, actions: Array[Action.BaseAction], game_state_provider: Variant) -> void:
	if actions.is_empty():
		return
	var exec_context := _build_execution_context(tag_name, game_state_provider)
	for action in actions:
		if action != null:
			action.execute(exec_context)
			# Debug: 验证 Action 状态未被修改
			action._verify_unchanged()
			if _state != STATE_EXECUTING:
				break
		else:
			Log.warning("AbilityExecutionInstance", "ExecutionInstance missing action")

func _resolve_actions_for_tag(tag_name: String) -> Array[Action.BaseAction]:
	for entry in _tag_actions:
		if entry.matches(tag_name):
			return entry.get_actions()
	return []

## 构建 Action 执行上下文
##
## 注意：这里将 _trigger_event_dict 包装为 [_trigger_event_dict] 作为 event_dict_chain 的起点。
## chain 的增长由 ExecutionContext.create_callback_context() 负责（Action 产生回调事件时追加）。
## 每次调用都会创建新的单元素数组，确保各 tag 时间点的 ExecutionContext 互相独立。
func _build_execution_context(current_tag: String, game_state_provider: Variant) -> ExecutionContext:
	var exec_info := AbilityExecutionInfo.create(id, timeline_id, _elapsed, current_tag)
	return ExecutionContext.create(
		[_trigger_event_dict],
		game_state_provider,
		GameWorld.event_collector,
		_ability_ref,
		exec_info,
		_execution_state  # §0.4: 引用共享; 同一 execution 跨 tag 可见
	)

func serialize() -> Dictionary:
	return {
		"id": id,
		"timelineId": timeline_id,
		"elapsed": _elapsed,
		"loopsCompleted": _loops_completed,
		"state": _state,
		"triggeredTags": _triggered_tags.keys(),
	}
