class_name NoInstanceComponent
extends AbilityComponent

const TYPE := "NoInstanceComponent"

var _triggers: Array[Dictionary] = []
var _trigger_mode: String = "any"
var _actions: Array[Action.BaseAction] = []

## §0.6 Ability lifecycle actions
var _on_apply_actions: Array[Action.BaseAction] = []
var _on_remove_actions: Array[Action.BaseAction] = []


func _init(config: NoInstanceConfig):
	type = TYPE
	_trigger_mode = config.trigger_mode
	_actions.assign(config.actions)
	_on_apply_actions.assign(config.on_apply_actions)
	_on_remove_actions.assign(config.on_remove_actions)
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


## §0.6: lifecycle apply hook
func on_apply(context: AbilityLifecycleContext) -> void:
	if _on_apply_actions.is_empty():
		return
	_execute_lifecycle_actions(_on_apply_actions, context, "on_apply")


## §0.6: lifecycle remove hook
func on_remove(context: AbilityLifecycleContext) -> void:
	if _on_remove_actions.is_empty():
		return
	_execute_lifecycle_actions(_on_remove_actions, context, "on_remove")


func _check_triggers(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	return AbilityComponent.match_triggers(_triggers, _trigger_mode, event_dict, context)


func _execute_actions(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> void:
	var exec_context := _build_execution_context(event_dict, context, game_state_provider)
	for action in _actions:
		action.execute(exec_context)
		action._verify_unchanged()


## §0.6: lifecycle actions 走单独的 execution context (lifecycle event)。
##
## 合同:
## - event_dict_chain = [{ "kind": "ability_lifecycle", "phase": "on_apply"|"on_remove",
##   "ability_id": ..., "ability_config_id": ... }]; 不写入 EventCollector 历史。
## - game_state_provider 当前传 null (lifecycle actions 不应依赖 battle 状态;
##   读取缺失字段的 action 应 Log.assert_crash)。
## - lifecycle 行为本身不进 replay; 但 action 修改 tag 时既有 RecordingUtils 记录 tag 变化。
func _execute_lifecycle_actions(actions: Array[Action.BaseAction], context: AbilityLifecycleContext, phase: String) -> void:
	var ability_ref := AbilityRef.from_ability(context.ability)
	var event_dict := {
		"kind": "ability_lifecycle",
		"phase": phase,
		"ability_id": context.ability.id if context.ability != null else "",
		"ability_config_id": context.ability.config_id if context.ability != null else "",
		"owner_actor_id": context.owner_actor_id,
	}
	var exec_context := ExecutionContext.create(
		[event_dict] as Array[Dictionary],
		null,  # game_state_provider; lifecycle actions 不依赖
		GameWorld.event_collector,
		ability_ref,
		null
	)
	for action in actions:
		action.execute(exec_context)
		action._verify_unchanged()


## Debug: 冻结所有 Action，用于检测无状态约束
func _freeze_all_actions() -> void:
	for action in _actions:
		action._freeze()
	for action in _on_apply_actions:
		action._freeze()
	for action in _on_remove_actions:
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
		"onApplyActionsCount": _on_apply_actions.size(),
		"onRemoveActionsCount": _on_remove_actions.size(),
	}
