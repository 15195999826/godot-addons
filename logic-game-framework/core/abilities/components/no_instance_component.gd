class_name NoInstanceComponent
extends AbilityComponent

const TYPE := "NoInstanceComponent"

var _triggers: Array[Dictionary] = []
var _trigger_mode: String = "any"
var _actions: Array[Action.BaseAction] = []

func _init(config: NoInstanceConfig):
	type = TYPE
	_trigger_mode = config.trigger_mode
	_actions.assign(config.actions)
	_triggers = AbilityComponent.convert_triggers(config.triggers)
	# Debug: 冻结所有 Action
	_freeze_all_actions()

func get_triggers() -> Array[Dictionary]:
	return _triggers

func matches_event(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	return _check_triggers(event_dict, context)

func on_event(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> bool:
	if _check_triggers(event_dict, context):
		_execute_actions(event_dict, context, game_state_provider)
		return true
	return false

func _check_triggers(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	return AbilityComponent.match_triggers(_triggers, _trigger_mode, event_dict, context)

func _execute_actions(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> void:
	var exec_context := _build_execution_context(event_dict, context, game_state_provider)
	for action in _actions:
		action.execute(exec_context)
		action._verify_unchanged()

## Debug: 冻结所有 Action，用于检测无状态约束
func _freeze_all_actions() -> void:
	for action in _actions:
		action._freeze()

func _build_execution_context(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> ExecutionContext:
	var ability_ref := AbilityRef.from_ability(context.ability)
	var event_dict_chain: Array[Dictionary] = [event_dict]
	return ExecutionContext.create(
		event_dict_chain,
		game_state_provider,
		GameWorld.event_collector,
		ability_ref,
		null  # NoInstanceComponent 不产生 ExecutionInfo
	)

func serialize() -> Dictionary:
	return {
		"triggersCount": _triggers.size(),
		"triggerMode": _trigger_mode,
		"actionsCount": _actions.size(),
	}
