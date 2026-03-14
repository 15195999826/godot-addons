class_name AbilityExecutionInstance
extends RefCounted

const STATE_EXECUTING := "executing"
const STATE_COMPLETED := "completed"
const STATE_CANCELLED := "cancelled"

var id: String
var timeline_id: String
var _timeline: TimelineData = null
var _tag_actions: Array[TagActionsEntry] = []
var _trigger_event_dict: Dictionary = {}
var _game_state_provider: Variant = null
var _ability_ref: AbilityRef = null
var _elapsed: float = 0.0
var _state: String = STATE_EXECUTING
var _triggered_tags: Dictionary = {}

func _init(
	p_timeline_id: String,
	p_tag_actions: Array[TagActionsEntry],
	p_trigger_event_dict: Dictionary,
	p_game_state_provider: Variant,
	p_ability_ref: AbilityRef
) -> void:
	id = IdGenerator.generate("execution")
	timeline_id = p_timeline_id
	_timeline = TimelineRegistry.get_timeline(timeline_id)
	_tag_actions = p_tag_actions
	_trigger_event_dict = p_trigger_event_dict
	_game_state_provider = p_game_state_provider
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

func tick(dt: float) -> Array[String]:
	if _state != STATE_EXECUTING:
		return []
	if _timeline == null:
		_state = STATE_COMPLETED
		return []

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
		_execute_actions_for_tag(tag_name, actions)
		triggered_tags.append(tag_name)

	if _elapsed >= _timeline.total_duration:
		_state = STATE_COMPLETED
		Log.debug("AbilityExecutionInstance", "执行完成")

	return triggered_tags

func cancel() -> void:
	if _state == STATE_EXECUTING:
		_state = STATE_CANCELLED
		Log.debug("AbilityExecutionInstance", "执行取消")

## 判断 tag 是否应在当前 tick 触发
func _should_trigger(previous_elapsed: float, tag_time: float) -> bool:
	if tag_time == 0.0:
		return previous_elapsed == 0.0 and _elapsed >= 0.0
	return previous_elapsed < tag_time and _elapsed >= tag_time

func _execute_actions_for_tag(tag_name: String, actions: Array[Action.BaseAction]) -> void:
	if actions.is_empty():
		return
	var exec_context := _build_execution_context(tag_name)
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
func _build_execution_context(current_tag: String) -> ExecutionContext:
	var exec_info := AbilityExecutionInfo.create(id, timeline_id, _elapsed, current_tag)
	return ExecutionContext.create(
		[_trigger_event_dict],
		_game_state_provider,
		GameWorld.event_collector,
		_ability_ref,
		exec_info
	)

func serialize() -> Dictionary:
	return {
		"id": id,
		"timelineId": timeline_id,
		"elapsed": _elapsed,
		"state": _state,
		"triggeredTags": _triggered_tags.keys(),
	}
