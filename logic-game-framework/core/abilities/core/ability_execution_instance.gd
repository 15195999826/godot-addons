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
var _trigger_event_dict: Dictionary = {}
var _ability_ref: AbilityRef = null
var _elapsed: float = 0.0
var _loops_completed: int = 0
var _state: String = STATE_EXECUTING
var _triggered_tags: Dictionary = {}

## game_state_provider 不再作为字段缓存。
##
## 框架约定 provider 是"调用时参数流"（对齐 HandlerContext / ExecutionContext / Component.on_event 等），
## 由 tick 调用链每次传入。缓存会形成循环强引用（battle → ability → exec_instance → provider=battle），
## 导致战斗对象图无法释放。
func _init(
	p_timeline_id: String,
	p_tag_actions: Array[TagActionsEntry],
	p_on_timeline_start_actions: Array[Action.BaseAction],
	p_on_timeline_end_actions: Array[Action.BaseAction],
	p_trigger_event_dict: Dictionary,
	p_ability_ref: AbilityRef
) -> void:
	id = IdGenerator.generate("execution")
	timeline_id = p_timeline_id
	_timeline = TimelineRegistry.get_timeline(timeline_id)
	_tag_actions = p_tag_actions
	_on_timeline_start_actions = p_on_timeline_start_actions
	_on_timeline_end_actions = p_on_timeline_end_actions
	_trigger_event_dict = p_trigger_event_dict
	_ability_ref = p_ability_ref
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
func fire_sync_actions(actions: Array[Action.BaseAction], current_tag: String, game_state_provider: Variant) -> void:
	if actions.is_empty():
		return
	var exec_context := _build_execution_context(current_tag, game_state_provider)
	for action in actions:
		if action != null:
			action.execute(exec_context)
			action._verify_unchanged()
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

	if _elapsed >= _timeline.total_duration:
		# 本轮结束：先跑 on_timeline_end
		fire_sync_actions(_on_timeline_end_actions, "__timeline_end__", game_state_provider)
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

func cancel() -> void:
	if _state == STATE_EXECUTING:
		_state = STATE_CANCELLED
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
		exec_info
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
