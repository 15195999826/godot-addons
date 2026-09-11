class_name Ability
extends RefCounted

const STATE_PENDING := "pending"
const STATE_GRANTED := "granted"
const STATE_EXPIRED := "expired"

## Ability 层数的溢出策略
##
## - CAP：超过 max 截断到 max
## - REFRESH：达到 CAP 的同时广播 on_ability_stack_refreshed() 钩子（时长类 component 刷新持续时间）
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
## 注册在 owner 所属 EventProcessor 上的 post handler 的注销闭包：apply_effects 注册、remove_effects 注销。
## 闭包只捕获注册表与 id（见 EventProcessor._make_unregister），表里的 handler 只带 id，不回指本 ability。
var _post_unregisters: Array[Callable] = []

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

func tick_executions(dt: float) -> Array[String]:
	if _state == STATE_EXPIRED:
		return []
	# Phase B2 (Break) 顶层短路: disabled passive ability 冻结 periodic timeline,
	# 不 destroy / 不 catch-up; 期内 elapsed 不推进, missed tick 丢弃 (per Goal)。
	if is_disabled():
		return []
	var all_triggered: Array[String] = []
	for instance in _execution_instances:
		if _is_executing_instance(instance):
			all_triggered.append_array(instance.tick(dt))
	_execution_instances = _execution_instances.filter(_is_executing_instance)
	return all_triggered

func activate_new_execution_instance(
	p_timeline: TimelineData,
	p_tag_actions: Array[TagActionsEntry],
	p_on_timeline_start_actions: Array[Action.BaseAction],
	p_on_timeline_end_actions: Array[Action.BaseAction],
	p_trigger_event_dict: Dictionary,
	p_on_cancel_actions: Array[Action.BaseAction] = []
) -> AbilityExecutionInstance:
	var ability_ref := AbilityRef.from_ability(self)
	var instance := AbilityExecutionInstance.new(
		p_timeline,
		p_tag_actions,
		p_on_timeline_start_actions,
		p_on_timeline_end_actions,
		p_trigger_event_dict,
		ability_ref,
		p_on_cancel_actions
	)
	_execution_instances.append(instance)
	for callback in _on_execution_callbacks:
		if callback.is_valid():
			callback.call(instance)
	# Callback 可同步取消；取消后不得再执行 start Action（否则会在 cleanup 后重新占用资源）。
	if instance.is_executing():
		instance.fire_sync_actions(p_on_timeline_start_actions, "__timeline_start__")
	return instance

func get_executing_instances() -> Array[AbilityExecutionInstance]:
	return _execution_instances.filter(_is_executing_instance)

func get_all_execution_instances() -> Array[AbilityExecutionInstance]:
	return _execution_instances

## 是否有执行中的 instance。与 get_executing_instances().size() > 0 同义，但不构造
## 中间数组——战斗主循环每 actor 每 tick 都问一次。
func has_executing_instance() -> bool:
	for instance in _execution_instances:
		if _is_executing_instance(instance):
			return true
	return false

func cancel_all_executions() -> void:
	for instance in _execution_instances:
		if instance:
			instance.cancel()
	_execution_instances = []

## 把事件交给全部 active component（trigger 在各 component 的 on_event 里匹配）；返回是否有 component 被触发。
## 两条入口：post 派发经本 ability 注册的 handler 进来，定向投递经 AbilitySet.receive_event 进来。
func receive_event(event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if _state == STATE_EXPIRED:
		return false
	# Phase B2 (Break) 顶层短路: disabled passive ability 不派发事件给 NoInstanceComponent
	# triggered passive (Thorn / Deathrattle 等), 也不进 ActiveUseComponent 的 cond/cost 链路。
	# 这样 Break 不需要 NoInstanceComponent / ActivateInstanceComponent 自行实现 break hook。
	if is_disabled():
		return false
	var triggered_components: Array[String] = []
	for comp in _components:
		if not comp.is_active():
			continue
		if comp.on_event(event_dict, context):
			triggered_components.append(_get_component_name(comp))
	if not triggered_components.is_empty():
		for callback in _on_triggered_callbacks:
			if callback.is_valid():
				callback.call(event_dict, triggered_components)
	return not triggered_components.is_empty()


## 激活门的纯查询干跑（零副作用、可重入）：本 Ability 现在能否通过 ActiveUse 激活门。
##
## 先镜像 receive_event 的顶层短路（未 granted / disabled 时事件根本到不了组件，
## 查询必须给出同一答案），再逐个评估全部 active ActiveUseComponent 的
## Condition/Cost（见 ActiveUseComponent.can_activate），首个失败即返回。
## 没有 ActiveUseComponent 时门控空真通过——本查询回答"门会不会拦"，
## "这是不是一个可施放技能"属 ability metadata 的声明式判断，不在此处。
##
## 返回形状见 AbilityActivationQuery。通常经 AbilitySet.can_activate 调用
## （由它构造 lifecycle context）。
func can_activate(
	context: AbilityLifecycleContext,
	event_dict: Dictionary = {},
) -> Dictionary:
	if _state != STATE_GRANTED:
		return AbilityActivationQuery.denied(
			"ability is not granted: %s" % _state, AbilityActivationQuery.FAILED_ABILITY)
	if is_disabled():
		return AbilityActivationQuery.denied(
			"ability is disabled", AbilityActivationQuery.FAILED_ABILITY)
	for component in _components:
		var active_use := component as ActiveUseComponent
		if active_use == null or not active_use.is_active():
			continue
		var gate_result := active_use.can_activate(context, event_dict)
		if not AbilityActivationQuery.is_allowed(gate_result):
			return gate_result
	return AbilityActivationQuery.allowed()


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
	var ctx := AbilityLifecycleContext.for_ability(self)
	for component in _components:
		if component.is_active():
			component.on_passive_disabled(ctx)


func _notify_components_enabled() -> void:
	if not _effects_active:
		return
	var ctx := AbilityLifecycleContext.for_ability(self)
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
	# on_apply 里本 ability 已过期（remove_effects 已跑完）时再注册，就没有人注销了
	if _effects_active:
		_register_post_handlers(context)

## on_remove / 叠层 / Break 钩子的 context 由 AbilityLifecycleContext.for_ability 按 owner id 反查建出。
## 先注销 post handler：移除中的 ability 不再响应 on_remove 期间派发的事件。
func remove_effects() -> void:
	if not _effects_active:
		return
	_effects_active = false
	for unregister in _post_unregisters:
		unregister.call()
	_post_unregisters.clear()
	var context := AbilityLifecycleContext.for_ability(self)
	for component in _components:
		component.on_remove(context)
	_on_triggered_callbacks.clear()
	_on_execution_callbacks.clear()


## 按 component 声明的 kind（去掉定向投递 kind）各注册一条 post handler，派发时经 receive_event 交给全部 component。
## owner 取 context 的（本 ability 所在 AbilitySet 的 owner）：派发按它找回本 ability，remove_actor 按它注销。
## owner 未注册进 GameWorld（孤立单测）时 context 没有 processor：不注册，这样的 ability 只收得到 AbilitySet 的定向投递。
func _register_post_handlers(context: AbilityLifecycleContext) -> void:
	var processor := context.event_processor
	if processor == null:
		return
	var kinds: Array[String] = []
	for component in _components:
		for kind in component.get_post_event_kinds():
			if not kinds.has(kind) and not EventProcessor.DIRECT_DELIVERY_KINDS.has(kind):
				kinds.append(kind)
	var owner_id := context.owner_actor_id
	for kind in kinds:
		var registration := PostHandlerRegistration.new(
			"%s_post_%s" % [id, kind],
			kind,
			owner_id,
			id,
			config_id,
			_make_post_handler(owner_id, id),
			display_name
		)
		_post_unregisters.append(processor.register_post_handler(registration))


## post handler 在 static 上下文里建：没有 self 可捕获，lambda 只带 owner / ability 两个 id，派发时按 id 取回 ability。
## 捕获本 ability（或它的 component / context）就接上 ability → _post_unregisters → 注册表 → registration → handler → ability 的环。
static func _make_post_handler(owner_id: String, ability_id: String) -> Callable:
	return func(event_dict: Dictionary, _handler_context: HandlerContext) -> bool:
		var context := AbilityLifecycleContext.rebuild_for_handler(owner_id, ability_id, event_dict, EventPhase.PHASE_POST)
		if context == null:
			return false
		return context.ability.receive_event(event_dict, context)

func expire(reason: String) -> void:
	if _state == STATE_EXPIRED:
		return
	_expire_reason = reason
	cancel_all_executions()
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
## REFRESH 策略在叠层的同时广播 on_ability_stack_refreshed() 钩子（时长类
## component 借此刷新持续时间），让"刷新层数 + 刷新持续时间"成为原子语义。
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
			_notify_stack_refreshed()
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
## context 与 on_remove 同款（AbilityLifecycleContext.for_ability，按 owner id 反查）。
func _notify_stacks_changed(old_stacks: int, new_stacks: int) -> void:
	Log.assert_crash(not _notifying_stacks_changed,
		"Ability",
		"on_stacks_changed re-entry detected; hook must not call add/remove/set_stacks")
	_notifying_stacks_changed = true
	var context := AbilityLifecycleContext.for_ability(self)
	for component in _components:
		component.on_stacks_changed(context, old_stacks, new_stacks)
	_notifying_stacks_changed = false


func _notify_stack_refreshed() -> void:
	for component in _components:
		component.on_ability_stack_refreshed()


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
