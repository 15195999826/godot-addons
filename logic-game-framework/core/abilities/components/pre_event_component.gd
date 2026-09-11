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
## 绝不捕获 self（PreEventComponent 实例），也不捕获本方法收到的 context（它带 instance 强引用）。
## 触发时经 AbilityLifecycleContext.rebuild_for_handler 按 id 重建 context 传给用户 filter / handler；
## 重建返回 null（owner 此刻不响应这条事件、ability 已被移除等）时 filter 不通过、handler 放行。
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
		var ctx := AbilityLifecycleContext.rebuild_for_handler(owner_id, ability_id, event_dict, EventPhase.PHASE_PRE)
		if ctx == null:
			return false
		return user_filter.call(event_dict, ctx)

	var handler_lambda := func(mutable: MutableEvent, _handler_context: HandlerContext) -> Intent:
		if not user_handler.is_valid():
			return EventPhase.pass_intent()
		var ctx := AbilityLifecycleContext.rebuild_for_handler(owner_id, ability_id, mutable.original, EventPhase.PHASE_PRE)
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


func serialize() -> Dictionary:
	return {
		"eventKind": _event_kind,
		"handlerName": _handler_name,
	}
