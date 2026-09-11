## NoInstanceComponent - 无 execution instance 的事件被动 component
##
## Phase B2 (Break) 规则: 本 component 严禁实现 on_passive_disabled / on_passive_enabled hook。
## Ability.receive_event() 已经顶层短路 disabled passive 的事件派发, 本 component 的
## trigger / actions 自然不触发, 无需 component-level break 实现。如果在这里另行 implement,
## 会与顶层短路重复, 引入不一致风险。
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


func on_event(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if _check_triggers(event_dict, context):
		_execute_actions(_actions, event_dict, context)
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


## §0.6: lifecycle actions 以一个内部 lifecycle event 作为事件链起点执行。
##
## 合同:
## - event_dict_chain = [{ "kind": "ability_lifecycle", "phase": "on_apply"|"on_remove",
##   "ability_id": ..., "ability_config_id": ... }]; 这条 lifecycle event 不写入 EventCollector 历史。
## - ctx.instance 与事件触发路径同源 (context.instance, 按 owner 反查; owner 未注册时为 null)。
## - lifecycle 行为本身不进 replay; 但 action 修改 tag 时既有 RecordingUtils 记录 tag 变化。
func _execute_lifecycle_actions(actions: Array[Action.BaseAction], context: AbilityLifecycleContext, phase: String) -> void:
	var event_dict := {
		"kind": "ability_lifecycle",
		"phase": phase,
		"ability_id": context.ability.id if context.ability != null else "",
		"ability_config_id": context.ability.config_id if context.ability != null else "",
		"owner_actor_id": context.owner_actor_id,
	}
	_execute_actions(actions, event_dict, context)


func _execute_actions(actions: Array[Action.BaseAction], event_dict: Dictionary, context: AbilityLifecycleContext) -> void:
	var event_dict_chain: Array[Dictionary] = [event_dict]
	var exec_context := ExecutionContext.create(
		event_dict_chain,
		context.instance,
		AbilityRef.from_ability(context.ability),
		null  # NoInstanceComponent 不产生 ExecutionInfo
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


func serialize() -> Dictionary:
	return {
		"triggersCount": _triggers.size(),
		"triggerMode": _trigger_mode,
		"actionsCount": _actions.size(),
		"onApplyActionsCount": _on_apply_actions.size(),
		"onRemoveActionsCount": _on_remove_actions.size(),
	}
