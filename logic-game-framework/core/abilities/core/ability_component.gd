class_name AbilityComponent
extends RefCounted
## Ability 组件基类
##
## 所有 Ability 组件都应继承此类。
## 提供可选的生命周期钩子，子类按需覆盖。

var type: String = "AbilityComponent"
var _state: String = "active"
var _ability: Ability = null

func get_state() -> String:
	return _state

func initialize(ability: Ability) -> void:
	_ability = ability
	_state = "active"

func is_active() -> bool:
	return _state == "active"

func mark_expired() -> void:
	_state = "expired"

func is_expired() -> bool:
	return _state == "expired"

func get_ability() -> Ability:
	return _ability

## 每帧 tick（可选覆盖）
func on_tick(_dt: float) -> void:
	pass

## 响应事件（可选覆盖）
## @return true 表示组件被触发
func on_event(_event_dict: Dictionary, _context: AbilityLifecycleContext, _game_state_provider: Variant) -> bool:
	return false

## 能力生效时调用（可选覆盖）
func on_apply(_context: AbilityLifecycleContext) -> void:
	pass

## 能力移除时调用（可选覆盖）
func on_remove(_context: AbilityLifecycleContext) -> void:
	pass

## 序列化组件状态（可选覆盖）
func serialize() -> Dictionary:
	return {}

## 检查事件是否匹配触发器列表
## triggers: 触发器字典数组，每个包含 "eventKind" 和可选 "filter"
## trigger_mode: "any"（任一匹配）或 "all"（全部匹配）
static func match_triggers(triggers: Array[Dictionary], trigger_mode: String, event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if triggers.is_empty():
		return false
	if trigger_mode == "any":
		for trigger in triggers:
			if match_single_trigger(trigger, event_dict, context):
				return true
		return false
	for trigger in triggers:
		if not match_single_trigger(trigger, event_dict, context):
			return false
	return true

## 匹配单个触发器：检查 eventKind 和可选 filter
static func match_single_trigger(trigger: Dictionary, event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if event_dict.get("kind", "") != str(trigger.get("eventKind", "")):
		return false
	if trigger.has("filter") and trigger["filter"] is Callable:
		return trigger["filter"].call(event_dict, context)
	return true

## 将 TriggerConfig 列表转换为内部字典格式
static func convert_triggers(configs: Array[TriggerConfig]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trigger in configs:
		var trigger_dict := { "eventKind": trigger.event_kind }
		if trigger.filter.is_valid():
			trigger_dict["filter"] = trigger.filter
		result.append(trigger_dict)
	return result
