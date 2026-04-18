class_name Ability
extends RefCounted

const STATE_PENDING := "pending"
const STATE_GRANTED := "granted"
const STATE_EXPIRED := "expired"

var id: String
var config_id: String
var source_actor_id: String
var owner_actor_id: String
var display_name: String = ""
var description: String = ""
var icon: String = ""
var ability_tags: Array[String] = []

## 自定义元数据（从 AbilityConfig 复制）
var metadata: Dictionary = {}

var _state: String = STATE_PENDING
var _expire_reason: String = ""
var _components: Array[AbilityComponent] = []
var _lifecycle_context: AbilityLifecycleContext = null
var _execution_instances: Array[AbilityExecutionInstance] = []
var _on_triggered_callbacks: Array[Callable] = []
var _on_execution_callbacks: Array[Callable] = []

func _init(config: AbilityConfig, owner_actor_id_value: String, source_actor_id_value: String = ""):
	id = IdGenerator.generate("ability")
	config_id = config.config_id
	owner_actor_id = owner_actor_id_value
	source_actor_id = source_actor_id_value if source_actor_id_value != "" else owner_actor_id_value
	display_name = config.display_name
	description = config.description
	icon = config.icon
	ability_tags = config.ability_tags
	metadata = config.metadata

	_components = _resolve_components(config.active_use_components, config.components)

	for component in _components:
		component.initialize(self)

func get_state() -> String:
	return _state

func is_granted() -> bool:
	return _state == STATE_GRANTED

func is_expired() -> bool:
	return _state == STATE_EXPIRED

func get_expire_reason() -> String:
	return _expire_reason

func get_all_components() -> Array[AbilityComponent]:
	return _components

func tick(dt: float) -> void:
	if _state == STATE_EXPIRED:
		return
	for component in _components:
		if component.is_active():
			component.on_tick(dt)

func tick_executions(dt: float) -> Array[String]:
	if _state == STATE_EXPIRED:
		return []
	var all_triggered: Array[String] = []
	for instance in _execution_instances:
		if _is_executing_instance(instance):
			all_triggered.append_array(instance.tick(dt))
	_execution_instances = _execution_instances.filter(_is_executing_instance)
	return all_triggered

func activate_new_execution_instance(
	p_timeline_id: String,
	p_tag_actions: Array[TagActionsEntry],
	p_on_timeline_start_actions: Array[Action.BaseAction],
	p_on_timeline_end_actions: Array[Action.BaseAction],
	p_trigger_event_dict: Dictionary,
	p_game_state_provider: Variant
) -> AbilityExecutionInstance:
	var ability_ref := AbilityRef.from_ability(self)
	var instance := AbilityExecutionInstance.new(
		p_timeline_id,
		p_tag_actions,
		p_on_timeline_start_actions,
		p_on_timeline_end_actions,
		p_trigger_event_dict,
		p_game_state_provider,
		ability_ref
	)
	_execution_instances.append(instance)
	for callback in _on_execution_callbacks:
		if callback.is_valid():
			callback.call(instance)
	# 激活瞬间同步触发 on_timeline_start（如 StageCueAction / reserve_tile）
	instance.fire_sync_actions(p_on_timeline_start_actions, "__timeline_start__")
	return instance

func get_executing_instances() -> Array[AbilityExecutionInstance]:
	return _execution_instances.filter(_is_executing_instance)

func get_all_execution_instances() -> Array[AbilityExecutionInstance]:
	return _execution_instances

func cancel_all_executions() -> void:
	for instance in _execution_instances:
		if instance:
			instance.cancel()
	_execution_instances = []

func receive_event(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> void:
	if _state == STATE_EXPIRED:
		return
	var triggered_components: Array[String] = []
	for comp in _components:
		if not comp.is_active():
			continue
		if comp.on_event(event_dict, context, game_state_provider):
			triggered_components.append(_get_component_name(comp))
	if not triggered_components.is_empty():
		for callback in _on_triggered_callbacks:
			if callback.is_valid():
				callback.call(event_dict, triggered_components)

func add_triggered_listener(callback: Callable) -> Callable:
	return _add_listener(_on_triggered_callbacks, callback)

func add_execution_activated_listener(callback: Callable) -> Callable:
	return _add_listener(_on_execution_callbacks, callback)

func apply_effects(context: AbilityLifecycleContext) -> void:
	if _state == STATE_GRANTED:
		Log.warning("Ability", "Ability already granted: %s" % id)
		return
	_state = STATE_GRANTED
	_lifecycle_context = context
	for component in _components:
		component.on_apply(context)

func remove_effects() -> void:
	if _lifecycle_context == null:
		return
	for component in _components:
		component.on_remove(_lifecycle_context)
	_lifecycle_context = null
	_on_triggered_callbacks.clear()
	_on_execution_callbacks.clear()

func expire(reason: String) -> void:
	if _state == STATE_EXPIRED:
		return
	_expire_reason = reason
	remove_effects()
	_state = STATE_EXPIRED

func has_ability_tag(tag: String) -> bool:
	return ability_tags.has(tag)


## 获取 int 类型的元数据
func get_meta_int(key: String, default: int = 0) -> int:
	return metadata.get(key, default) as int

func serialize() -> Dictionary:
	var serialized_components: Array[Dictionary] = []
	for component in _components:
		serialized_components.append({
			"type": component.type,
			"data": component.serialize(),
		})
	var serialized_instances: Array[Dictionary] = []
	for instance in _execution_instances:
		if instance:
			serialized_instances.append(instance.serialize())
	return {
		"id": id,
		"configId": config_id,
		"source_actor_id": source_actor_id,
		"owner_actor_id": owner_actor_id,
		"state": _state,
		"displayName": display_name,
		"abilityTags": ability_tags,
		"metadata": metadata,
		"components": serialized_components,
		"executionInstances": serialized_instances,
	}

func _resolve_components(active_use_configs: Array[ActiveUseConfig], component_configs: Array[AbilityComponentConfig]) -> Array[AbilityComponent]:
	var result: Array[AbilityComponent] = []
	for cfg in active_use_configs:
		var component := cfg.create_component()
		Log.assert_crash(component != null, "Ability", "ActiveUseConfig.create_component() returned null: %s" % cfg.get_script().get_global_name())
		result.append(component)
	for cfg in component_configs:
		var component := cfg.create_component()
		Log.assert_crash(component != null, "Ability", "AbilityComponentConfig.create_component() returned null: %s" % cfg.get_script().get_global_name())
		result.append(component)
	return result

func _is_executing_instance(instance: AbilityExecutionInstance) -> bool:
	return instance and instance.is_executing()

func _get_component_name(component: AbilityComponent) -> String:
	return component.type if component.type != "" else component.get_class()

func _add_listener(list: Array[Callable], callback: Callable) -> Callable:
	list.append(callback)
	return func() -> void:
		var index := list.find(callback)
		if index != -1:
			list.remove_at(index)
