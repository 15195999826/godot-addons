class_name AbilityComponent
extends RefCounted
## Ability 组件基类
##
## 所有 Ability 组件都应继承此类。
## 提供可选的生命周期钩子，子类按需覆盖。

var type: String = "AbilityComponent"
var _state: String = "active"
## 所属 Ability 的弱引用。
##
## 持强引用会与 Ability._components 形成循环引用（GDScript RefCounted 无循环 GC），
## 导致 Ability 及其全部 component 在 GameWorld.shutdown 后仍被锁住无法释放。
## 弱引用让 Ability 的销毁仅由 AbilitySet / GameWorld 层级决定，component 只是附属。
var _ability_ref: WeakRef = null

func get_state() -> String:
	return _state

func initialize(ability: Ability) -> void:
	_ability_ref = weakref(ability) if ability != null else null
	_state = "active"

func is_active() -> bool:
	return _state == "active"

func mark_expired() -> void:
	_state = "expired"

func is_expired() -> bool:
	return _state == "expired"

## 返回所属 Ability；若 Ability 已被销毁则返回 null，调用方需短路。
func get_ability() -> Ability:
	if _ability_ref == null:
		return null
	return _ability_ref.get_ref() as Ability

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

## §0.X: Ability stacks 变化时调用 (可选覆盖)
##
## 触发时机: Ability.add_stacks / remove_stacks / set_stacks 内 stacks 实际变化后。
## 同一次调用如果 stacks 没真正变 (clamp 边界 / count<=0), hook 不触发。
##
## 不允许在 on_stacks_changed 内再调用 add_stacks/remove_stacks/set_stacks (递归更改)。
## Ability 实现了 reentrance guard, 嵌套调用会 Log.assert_crash。
func on_stacks_changed(_context: AbilityLifecycleContext, _old_stacks: int, _new_stacks: int) -> void:
	pass


## Phase B2 (Break): Ability 首次进入 disabled 状态时调用 (empty → non-empty)。
##
## 仅外部注册型 component 应实现 (StatModifierComponent / DynamicStatModifierComponent):
## 撤销外部注册状态 (RawAttributeSet modifier / dynamic dep), 这样 derived stat 立即
## 反映"passive 被禁用"。
##
## ❌ NoInstanceComponent / ActivateInstanceComponent **不应**实现此 hook:
## Ability.receive_event() 和 Ability.tick_executions() 已经顶层短路, 这些 component
## 的事件 / timeline 自然不推进。重复短路会引入不一致风险。
func on_passive_disabled(_context: AbilityLifecycleContext) -> void:
	pass


## Phase B2 (Break): Ability 最后一个 disabled source 移除 (non-empty → empty)。
##
## 与 on_passive_disabled 对称: 外部注册型 component 按当前 Ability state
## (current_scale / stacks / 依赖关系) 重建状态; 不补 Break 期间错过的 tick。
##
## ❌ NoInstanceComponent / ActivateInstanceComponent **不应**实现此 hook。
func on_passive_enabled(_context: AbilityLifecycleContext) -> void:
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
