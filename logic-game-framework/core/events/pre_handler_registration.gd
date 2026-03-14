## PreHandlerRegistration - Pre 阶段处理器注册信息
##
## 用于向 EventProcessor 注册 Pre 阶段事件处理器。
## 包含处理器的标识、过滤条件、处理函数等信息。
##
## ========== 使用示例 ==========
##
## @example 注册处理器
## ```gdscript
## var registration := PreHandlerRegistration.new(
##     "buff_armor_pre_damage",      # id
##     "pre_damage",                  # event_kind
##     "unit-1",                      # owner_id
##     "ability-123",                 # ability_id
##     "buff_armor",                  # config_id
##     _handle_pre_damage,            # handler
##     _filter_self_damage,           # filter (optional)
##     "护甲减伤"                      # name (optional)
## )
## var unregister := event_processor.register_pre_handler(registration)
## ```
class_name PreHandlerRegistration
extends RefCounted


## 处理器唯一标识
var id: String

## 监听的事件类型
var event_kind: String

## 处理器所属的 Actor ID
var owner_id: String

## 处理器所属的 Ability ID
var ability_id: String

## 处理器所属的 Ability Config ID
var config_id: String

## 处理函数：func(mutable: MutableEvent, ctx: HandlerContext) -> Intent
var handler: Callable

## 过滤函数：func(event_dict: Dictionary) -> bool（可选）
var filter: Callable

## 处理器显示名称（用于日志/调试）
var handler_name: String


func _init(
	p_id: String = "",
	p_event_kind: String = "",
	p_owner_id: String = "",
	p_ability_id: String = "",
	p_config_id: String = "",
	p_handler: Callable = Callable(),
	p_filter: Callable = Callable(),
	p_handler_name: String = ""
) -> void:
	id = p_id
	event_kind = p_event_kind
	owner_id = p_owner_id
	ability_id = p_ability_id
	config_id = p_config_id
	handler = p_handler
	filter = p_filter
	handler_name = p_handler_name


## 获取显示名称（优先使用 handler_name，否则使用 config_id）
func get_display_name() -> String:
	if handler_name != "":
		return handler_name
	if config_id != "":
		return config_id
	return id


## 检查过滤条件是否通过
func passes_filter(event_dict: Dictionary) -> bool:
	if not filter.is_valid():
		return true
	return filter.call(event_dict)


## 调用处理函数
func call_handler(mutable: MutableEvent, ctx: HandlerContext) -> Intent:
	if not handler.is_valid():
		return Intent.pass_through()
	var result: Variant = handler.call(mutable, ctx)
	if result is Intent:
		return result
	return Intent.pass_through()


## 转换为 Dictionary（用于日志/调试）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"eventKind": event_kind,
		"ownerId": owner_id,
		"abilityId": ability_id,
		"configId": config_id,
		"handlerName": handler_name,
	}
