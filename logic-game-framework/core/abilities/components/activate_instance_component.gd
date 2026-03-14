class_name ActivateInstanceComponent
extends AbilityComponent

const TYPE := "ActivateInstanceComponent"

var _triggers: Array[Dictionary] = []
var _trigger_mode: String = "any"
var _timeline_id: String = ""
var _tag_actions: Array[TagActionsEntry] = []

func _init(config: ActivateInstanceConfig):
	type = TYPE
	_timeline_id = config.timeline_id
	_tag_actions = config.tag_actions
	_trigger_mode = config.trigger_mode
	_triggers = AbilityComponent.convert_triggers(config.triggers)
	# Debug: 冻结所有 Action，检测无状态约束
	_freeze_all_actions()

func on_event(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> bool:
	if _check_triggers(event_dict, context):
		_activate_execution(event_dict, context, game_state_provider)
		return true
	return false

func _check_triggers(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	return AbilityComponent.match_triggers(_triggers, _trigger_mode, event_dict, context)

func _activate_execution(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> void:
	var ability := context.ability
	if ability == null:
		return
	ability.activate_new_execution_instance(
		_timeline_id,
		_tag_actions,
		event_dict,
		game_state_provider
	)
	Log.debug("ActivateInstanceComponent", "开始执行")

func serialize() -> Dictionary:
	return {
		"triggersCount": _triggers.size(),
		"triggerMode": _trigger_mode,
		"timelineId": _timeline_id,
		"tagActionsCount": _tag_actions.size(),
	}

## Debug: 冻结所有 Action，用于检测无状态约束
func _freeze_all_actions() -> void:
	for entry in _tag_actions:
		entry.freeze_actions()
