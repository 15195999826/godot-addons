class_name PreEventComponent
extends AbilityComponent

const TYPE := "PreEventComponent"

var _event_kind: String
var _filter: Callable = Callable()
var _handler: Callable
var _handler_name: String = ""
var _unregister: Callable = Callable()

func _init(config: PreEventConfig):
	type = TYPE
	_event_kind = config.event_kind
	_filter = config.filter
	_handler = config.handler
	_handler_name = config.name

func get_event_kind() -> String:
	return _event_kind

## on_apply：注册 handler 到 EventProcessor。
##
## 关键设计：handler/filter lambda 只捕获 String ID + 用户传入的 Callable，
## 绝不捕获 self（PreEventComponent 实例）。触发时按需通过 GameWorld.get_actor
## 重建 AbilityLifecycleContext 传给用户 handler。
##
## 这样 event_processor._pre_handlers 不会形成回指 Ability / PreEventComponent 的强引用链，
## Ability 从 AbilitySet._abilities 移除后即可被 GC。
func on_apply(context: AbilityLifecycleContext) -> void:
	var proc := context.event_processor
	if proc == null:
		Log.warning("PreEventComponent", "EventProcessor not available, handler will not be registered")
		return

	# 抽出所有需要的 ID / 用户 Callable / 名字 —— lambda 只捕获这些
	var owner_id: String = context.owner_actor_id
	var ability_id: String = context.ability.id
	var config_id: String = context.ability.config_id
	var user_handler: Callable = _handler
	var user_filter: Callable = _filter
	var handler_name: String = _handler_name
	var display_name: String = handler_name if handler_name != "" else (context.ability.display_name if context.ability.display_name != "" else config_id)

	var filter_lambda := func(event_dict: Dictionary) -> bool:
		if not user_filter.is_valid():
			return true
		var ctx := _rebuild_context(owner_id, ability_id)
		if ctx == null:
			return false
		return user_filter.call(event_dict, ctx)

	var handler_lambda := func(mutable: MutableEvent, _handler_context: HandlerContext) -> Intent:
		if not user_handler.is_valid():
			return EventPhase.pass_intent()
		var ctx := _rebuild_context(owner_id, ability_id)
		if ctx == null:
			return EventPhase.pass_intent()
		var result: Variant = user_handler.call(mutable, ctx)
		Log.assert_crash(result is Intent, "PreEventComponent", "handler '%s' must return Intent, got: %s" % [handler_name, type_string(typeof(result))])
		return result as Intent

	var registration := PreHandlerRegistration.new(
		"%s_pre_%s" % [ability_id, _event_kind],
		_event_kind,
		owner_id,
		ability_id,
		config_id,
		handler_lambda,
		filter_lambda,
		display_name
	)
	_unregister = proc.register_pre_handler(registration)

func on_remove(_context: AbilityLifecycleContext) -> void:
	if _unregister.is_valid():
		_unregister.call()
		_unregister = Callable()

## 静态重建 context 辅助：不捕获 self，避免形成 event_processor → lambda → self 的循环。
##
## 返回 null 的条件：
## - actor 不存在（已从 GameWorld 移除 / 测试未注册）
## - actor 覆盖了 is_pre_event_responsive 返回 false（如死亡/沉默）
## - ability 已从 AbilitySet._abilities 移除（revoke 后的幽灵 handler 兜底）
##
## 任一条件不满足 → 上层 lambda 返回 pass_intent，handler 不执行。
static func _rebuild_context(owner_id: String, ability_id: String) -> AbilityLifecycleContext:
	var actor := GameWorld.get_actor(owner_id)
	if actor == null:
		return null
	if not actor.is_pre_event_responsive():
		return null

	var ab_set: AbilitySet = null
	if "ability_set" in actor:
		ab_set = actor.get("ability_set")
	if ab_set == null:
		return null

	var ability := ab_set.find_ability_by_id(ability_id)
	if ability == null:
		return null

	var attr_set: BaseGeneratedAttributeSet = null
	if "attribute_set" in actor:
		attr_set = actor.get("attribute_set")

	return AbilityLifecycleContext.new(owner_id, attr_set, ability, ab_set, GameWorld.event_processor)


func serialize() -> Dictionary:
	return {
		"eventKind": _event_kind,
		"handlerName": _handler_name,
	}
