class_name PreEventComponent
extends AbilityComponent

const TYPE := "PreEventComponent"

var _event_kind: String
var _filter: Callable = Callable()
var _handler: Callable
var _handler_name: String = ""
var _unregister: Callable = Callable()
var _lifecycle_context: AbilityLifecycleContext = null

func _init(config: PreEventConfig):
	type = TYPE
	_event_kind = config.event_kind
	_filter = config.filter
	_handler = config.handler
	_handler_name = config.name

func get_event_kind() -> String:
	return _event_kind

func on_apply(context: AbilityLifecycleContext) -> void:
	_lifecycle_context = context
	var proc := context.event_processor
	if proc == null:
		Log.warning("PreEventComponent", "PreEventComponent: EventProcessor not available, handler will not be registered")
		return
	var ability := context.ability
	var handler_filter := func(event_dict: Dictionary) -> bool:
		if _filter.is_valid():
			return _filter.call(event_dict, _lifecycle_context)
		return true
	
	var registration := PreHandlerRegistration.new(
		"%s_pre_%s" % [ability.id, _event_kind],  # id
		_event_kind,  # event_kind
		context.owner_actor_id,  # owner_id
		ability.id,  # ability_id
		ability.config_id,  # config_id
		func(mutable: MutableEvent, handler_ctx: HandlerContext) -> Intent:
			return _handle_pre_event(mutable, handler_ctx),  # handler
		handler_filter,  # filter
		_handler_name if _handler_name != "" else (ability.display_name if ability.display_name != "" else ability.config_id)  # handler_name
	)
	_unregister = proc.register_pre_handler(registration)

func on_remove(_context: AbilityLifecycleContext) -> void:
	if _unregister.is_valid():
		_unregister.call()
		_unregister = Callable()
	_lifecycle_context = null

## 调用用户 handler 并校验返回类型。
## GDScript Callable 无法在编译期约束返回类型，因此在运行时通过 assert 校验。
## handler 签名约定见 PreEventConfig。
func _handle_pre_event(mutable: MutableEvent, _handler_context: HandlerContext) -> Intent:
	if _lifecycle_context == null:
		Log.warning("PreEventComponent", "PreEventComponent: lifecycleContext not available")
		return EventPhase.pass_intent()
	if not _handler.is_valid():
		return EventPhase.pass_intent()
	var result: Variant = _handler.call(mutable, _lifecycle_context)
	Log.assert_crash(result is Intent, "PreEventComponent", "handler '%s' must return Intent, got: %s" % [_handler_name, type_string(typeof(result))])
	return result as Intent


func serialize() -> Dictionary:
	return {
		"eventKind": _event_kind,
		"handlerName": _handler_name,
	}
