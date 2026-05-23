class_name Ability
extends RefCounted

const STATE_PENDING := "pending"
const STATE_GRANTED := "granted"
const STATE_EXPIRED := "expired"

## Ability 层数的溢出策略
##
## - CAP：超过 max 截断到 max
## - REFRESH：达到 CAP 的同时调用所在 Ability 上 TimeDurationComponent.refresh()
## - REJECT：超过 max 时拒绝本次叠加（stacks 不变）
const OVERFLOW_CAP := 0
const OVERFLOW_REFRESH := 1
const OVERFLOW_REJECT := 2

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

## 叠层数（Ability 一级属性）。
##
## 默认 1/1/CAP：对不可叠加 ability 调 add_stacks 一直 CAP 在 1，语义安全。
## 归 0 不自动触发 expire —— 清理由调用方（Action / 业务代码）决定。
var stacks: int = 1
var max_stacks: int = 1
var overflow_policy: int = OVERFLOW_CAP

var _state: String = STATE_PENDING
var _expire_reason: String = ""
var _components: Array[AbilityComponent] = []
## remove_effects 幂等哨兵：apply_effects 后为 true，remove_effects 后 false。
## 原设计靠 `_lifecycle_context == null` 判定，现不缓存 context 改用独立布尔标志。
var _effects_active: bool = false
var _execution_instances: Array[AbilityExecutionInstance] = []
var _on_triggered_callbacks: Array[Callable] = []
var _on_execution_callbacks: Array[Callable] = []

## Phase B2 (Break) — passive disabled-source 引用计数。
##
## key = source ability id (如 BreakBuff 实例 id)，value = true（Set 语义）。
## 多个 Break source 重叠时, 每个 source 独立贡献; 最后一个 source 移除才恢复 passive。
## is_disabled() 决定 receive_event / tick_executions 是否短路。
## State transitions empty→non-empty 触发 _notify_components_disabled (component
## 撤销外部注册状态如 StatModifier); non-empty→empty 触发 _notify_components_enabled
## (component 重建状态)。
##
## 规则: NoInstanceComponent / ActivateInstanceComponent 严禁实现 break hook —
## passive 事件派发 / timeline 推进由 Ability 顶层短路, 不需要 component-level 实现。
## 外部注册型 component (StatModifierComponent / DynamicStatModifierComponent) 实现 hook。
var _disabled_sources: Dictionary = {}

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
	stacks = config.initial_stacks
	max_stacks = config.max_stacks
	overflow_policy = config.overflow_policy

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

func tick_executions(dt: float, game_state_provider: Variant) -> Array[String]:
	if _state == STATE_EXPIRED:
		return []
	# Phase B2 (Break) 顶层短路: disabled passive ability 冻结 periodic timeline,
	# 不 destroy / 不 catch-up; 期内 elapsed 不推进, missed tick 丢弃 (per Goal)。
	if is_disabled():
		return []
	var all_triggered: Array[String] = []
	for instance in _execution_instances:
		if _is_executing_instance(instance):
			all_triggered.append_array(instance.tick(dt, game_state_provider))
	_execution_instances = _execution_instances.filter(_is_executing_instance)
	return all_triggered

## p_game_state_provider 只用于激活瞬间 fire_sync_actions(__timeline_start__)；
## 不存入 AbilityExecutionInstance 字段，避免 battle ↔ exec_instance 循环强引用。
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
		ability_ref
	)
	_execution_instances.append(instance)
	for callback in _on_execution_callbacks:
		if callback.is_valid():
			callback.call(instance)
	# 激活瞬间同步触发 on_timeline_start（如 StageCueAction / reserve_tile）
	instance.fire_sync_actions(p_on_timeline_start_actions, "__timeline_start__", p_game_state_provider)
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
	# Phase B2 (Break) 顶层短路: disabled passive ability 不派发事件给 NoInstanceComponent
	# triggered passive (Thorn / Deathrattle 等), 也不进 ActiveUseComponent 的 cond/cost 链路。
	# 这样 Break 不需要 NoInstanceComponent / ActivateInstanceComponent 自行实现 break hook。
	if is_disabled():
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


# ========== Phase B2 (Break) passive disabled-source 引用计数 API ==========

## 是否处于 disabled 状态（至少有一个 disabled source 引用）。
func is_disabled() -> bool:
	return not _disabled_sources.is_empty()


## 给本 Ability 添加一个 disabled source 引用 (Break buff 应用时).
## 第一次添加 (empty → non-empty) 触发 _notify_components_disabled。
## source_id 通常是 Break buff 的 ability id; 同一 source 多次 add 幂等。
func add_disabled_source(source_id: String) -> void:
	if source_id.is_empty():
		return
	var was_disabled := is_disabled()
	_disabled_sources[source_id] = true
	if not was_disabled:
		_notify_components_disabled()


## 移除一个 disabled source 引用 (Break buff expire / cleanse 时).
## 最后一个 source 移除 (non-empty → empty) 触发 _notify_components_enabled。
## 未知 source_id 不报错 (幂等)。
func remove_disabled_source(source_id: String) -> void:
	if source_id.is_empty():
		return
	if not _disabled_sources.has(source_id):
		return
	_disabled_sources.erase(source_id)
	if _disabled_sources.is_empty():
		_notify_components_enabled()


func get_disabled_source_count() -> int:
	return _disabled_sources.size()


func _notify_components_disabled() -> void:
	if not _effects_active:
		return
	var ctx := _build_remove_context()
	for component in _components:
		if component.is_active():
			component.on_passive_disabled(ctx)


func _notify_components_enabled() -> void:
	if not _effects_active:
		return
	var ctx := _build_remove_context()
	for component in _components:
		if component.is_active():
			component.on_passive_enabled(ctx)

func add_triggered_listener(callback: Callable) -> Callable:
	return _add_listener(_on_triggered_callbacks, callback)

func add_execution_activated_listener(callback: Callable) -> Callable:
	return _add_listener(_on_execution_callbacks, callback)

func apply_effects(context: AbilityLifecycleContext) -> void:
	if _state == STATE_GRANTED:
		Log.warning("Ability", "Ability already granted: %s" % id)
		return
	_state = STATE_GRANTED
	_effects_active = true
	for component in _components:
		component.on_apply(context)

func remove_effects() -> void:
	if not _effects_active:
		return
	_effects_active = false
	var context := _build_remove_context()
	for component in _components:
		component.on_remove(context)
	_on_triggered_callbacks.clear()
	_on_execution_callbacks.clear()


## 构造 on_remove 阶段专用的精简 context。
##
## on_remove 实际只读取 context.ability / context.attribute_set / context.ability_set 三字段，
## 因此通过 GameWorld.get_actor(owner_actor_id) 查到 actor 并取其 attribute_set / ability_set 即可；
## 其它字段（owner_actor_id / event_processor）on_remove 路径上无消费者，传 null 安全。
##
## 若 actor 未注册到 GameWorld（如隔离单元测试），attribute_set / ability_set 为 null —
## 对 no-op 的 on_remove（如 PreEventComponent / TestComponent）完全不影响；
## 对会读取这些字段的 component（StatModifier / Tag / DynamicStatModifier），测试须注册 mock actor。
func _build_remove_context() -> AbilityLifecycleContext:
	var attr_set: BaseGeneratedAttributeSet = null
	var ab_set: AbilitySet = null
	var actor := GameWorld.get_actor(owner_actor_id)
	if actor != null:
		if "attribute_set" in actor:
			attr_set = actor.get("attribute_set")
		if "ability_set" in actor:
			ab_set = actor.get("ability_set")
	return AbilityLifecycleContext.new(owner_actor_id, attr_set, self, ab_set, null)

func expire(reason: String) -> void:
	if _state == STATE_EXPIRED:
		return
	_expire_reason = reason
	remove_effects()
	_state = STATE_EXPIRED

func has_ability_tag(tag: String) -> bool:
	return ability_tags.has(tag)


func get_stacks() -> int:
	return stacks


func is_stacks_full() -> bool:
	return stacks >= max_stacks


## §0.X reentrance guard: 防止 on_stacks_changed hook 再次调用 add/remove/set_stacks
## 导致嵌套修改死循环。嵌套调用会 Log.assert_crash。
var _notifying_stacks_changed: bool = false


## 按溢出策略叠加层数，返回实际增加量。
##
## REFRESH 策略在叠层的同时顺手调用同 ability 上 TimeDurationComponent.refresh()，
## 让"刷新层数 + 刷新持续时间"成为原子语义。
##
## §0.X: stacks 实际变化后通过 _notify_stacks_changed 触发所有 component.on_stacks_changed。
func add_stacks(count: int) -> int:
	if count <= 0:
		return 0
	var before := stacks
	var new_value := stacks + count
	match overflow_policy:
		OVERFLOW_CAP:
			stacks = mini(new_value, max_stacks)
		OVERFLOW_REFRESH:
			stacks = mini(new_value, max_stacks)
			_refresh_time_duration_components()
		OVERFLOW_REJECT:
			if new_value <= max_stacks:
				stacks = new_value
	var delta := stacks - before
	if delta != 0:
		_notify_stacks_changed(before, stacks)
	return delta


## 减少层数（不归零自动过期；归零后的清理由调用方决定），返回实际减少量。
func remove_stacks(count: int) -> int:
	if count <= 0:
		return 0
	var before := stacks
	stacks = maxi(0, stacks - count)
	var delta := before - stacks
	if delta != 0:
		_notify_stacks_changed(before, stacks)
	return delta


## 强制设置层数（clamp 到 [0, max_stacks]；不自动过期）。
func set_stacks(count: int) -> void:
	var before := stacks
	stacks = clampi(count, 0, max_stacks)
	if stacks != before:
		_notify_stacks_changed(before, stacks)


## §0.X: 触发所有 component.on_stacks_changed 钩子。
##
## reentrance guard: hook 内不允许再调 add/remove/set_stacks 否则 assert。
## 构造与 on_apply / on_remove 同款 lifecycle context (走 GameWorld 取 actor)。
func _notify_stacks_changed(old_stacks: int, new_stacks: int) -> void:
	Log.assert_crash(not _notifying_stacks_changed,
		"Ability",
		"on_stacks_changed re-entry detected; hook must not call add/remove/set_stacks")
	_notifying_stacks_changed = true
	var context := _build_remove_context()  # 复用同款 context build (走 GameWorld 取 actor)
	for component in _components:
		component.on_stacks_changed(context, old_stacks, new_stacks)
	_notifying_stacks_changed = false


func _refresh_time_duration_components() -> void:
	for component in _components:
		if component.has_method("refresh") and component.type == "TimeDurationComponent":
			component.refresh()


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
		"stacks": stacks,
		"maxStacks": max_stacks,
		"overflowPolicy": overflow_policy,
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
