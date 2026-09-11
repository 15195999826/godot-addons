## ActivateInstanceComponent - 触发即创建 AbilityExecutionInstance 走 timeline 的 component
##
## Phase B2 (Break) 规则: 本 component 严禁实现 on_passive_disabled / on_passive_enabled hook。
## Ability.tick_executions() 已经顶层短路 disabled passive 的 periodic timeline 推进
## (per Goal: "冻结 periodic timeline, 不 destroy 不 catch-up"); Ability.receive_event()
## 同样顶层短路 GRANTED_SELF / 其它 event trigger 的 activation。本 component 不需要
## component-level break 实现。重复短路会引入不一致 (例如 break 期间 catch-up tick)。
class_name ActivateInstanceComponent
extends AbilityComponent

const TYPE := "ActivateInstanceComponent"

var _triggers: Array[Dictionary] = []
var _trigger_mode: String = "any"
var _timeline: TimelineData = null
var _tag_actions: Array[TagActionsEntry] = []
var _on_timeline_start_actions: Array[Action.BaseAction] = []
var _on_timeline_end_actions: Array[Action.BaseAction] = []
var _on_cancel_actions: Array[Action.BaseAction] = []

func _init(config: ActivateInstanceConfig):
	type = TYPE
	_timeline = config.timeline_data
	Log.assert_crash(_timeline != null, "ActivateInstanceComponent", "config 缺 timeline（builder.timeline(data) 必填）")
	_tag_actions = config.tag_actions
	_on_timeline_start_actions = config.on_timeline_start_actions
	_on_timeline_end_actions = config.on_timeline_end_actions
	_on_cancel_actions = config.on_cancel_actions
	_trigger_mode = config.trigger_mode
	_triggers = AbilityComponent.convert_triggers(config.triggers)
	# Debug: 冻结所有 Action，检测无状态约束
	_freeze_all_actions()

func on_event(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if not _check_triggers(event_dict, context):
		return false
	_activate_execution(event_dict, context)
	return true

func _check_triggers(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	return AbilityComponent.match_triggers(_triggers, _trigger_mode, event_dict, context)

func _activate_execution(event_dict: Dictionary, context: AbilityLifecycleContext) -> void:
	var ability := context.ability
	if ability == null:
		return
	ability.activate_new_execution_instance(
		_timeline,
		_tag_actions,
		_on_timeline_start_actions,
		_on_timeline_end_actions,
		event_dict,
		_on_cancel_actions
	)
	Log.debug("ActivateInstanceComponent", "开始执行")

func serialize() -> Dictionary:
	return {
		"triggersCount": _triggers.size(),
		"triggerMode": _trigger_mode,
		"timelineId": _timeline.id,
		"tagActionsCount": _tag_actions.size(),
	}

## Debug: 冻结所有 Action，用于检测无状态约束
func _freeze_all_actions() -> void:
	for entry in _tag_actions:
		entry.freeze_actions()
	for action in _on_timeline_start_actions:
		action._freeze()
	for action in _on_timeline_end_actions:
		action._freeze()
	for action in _on_cancel_actions:
		action._freeze()
