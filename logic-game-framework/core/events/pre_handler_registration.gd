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

## 第二段过滤：func(event_dict: Dictionary) -> bool（可选）。PreEventComponent 包出来的闭包，里面先按 id 重建
## AbilityLifecycleContext 再调用户的 context_filter——所以它贵，派发时排在 event_filter 之后。
var filter: Callable

## 第一段过滤：func(event_dict: Dictionary, me: HandlerContext) -> bool（可选）。只看事件 + 三个 id、不建 context，
## 派发时最先跑，不过就整条跳过。
var event_filter: Callable

## 处理器显示名称（用于日志/调试）
var handler_name: String

## 派发时交给 handler 的上下文：构造时按本条注册的 id 建好，每次派发复用（id 构造后不再改）
var handler_context: HandlerContext


func _init(
	p_id: String = "",
	p_event_kind: String = "",
	p_owner_id: String = "",
	p_ability_id: String = "",
	p_config_id: String = "",
	p_handler: Callable = Callable(),
	p_filter: Callable = Callable(),
	p_handler_name: String = "",
	p_event_filter: Callable = Callable()
) -> void:
	id = p_id
	event_kind = p_event_kind
	owner_id = p_owner_id
	ability_id = p_ability_id
	config_id = p_config_id
	handler = p_handler
	filter = p_filter
	handler_name = p_handler_name
	event_filter = p_event_filter
	handler_context = HandlerContext.new(owner_id, ability_id, config_id)


## 显示名称：handler_name，为空时退回 config_id，再退回 id
func get_display_name() -> String:
	if handler_name != "":
		return handler_name
	if config_id != "":
		return config_id
	return id


## 第一段：event_filter 用登记里现成的 HandlerContext 判，不建 context；没声明直接放行。
func passes_event_filter(event_dict: Dictionary) -> bool:
	if not event_filter.is_valid():
		return true
	return event_filter.call(event_dict, handler_context)


## 第二段：filter（重建 context 后的 context_filter）；没声明直接放行。
func passes_filter(event_dict: Dictionary) -> bool:
	if not filter.is_valid():
		return true
	return filter.call(event_dict)


## 调用处理函数
func call_handler(mutable: MutableEvent) -> Intent:
	if not handler.is_valid():
		return Intent.pass_through()
	var result: Variant = handler.call(mutable, handler_context)
	if result is Intent:
		return result
	return Intent.pass_through()


## 转换为 Dictionary（用于日志/调试）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"event_kind": event_kind,
		"owner_id": owner_id,
		"ability_id": ability_id,
		"config_id": config_id,
		"handler_name": handler_name,
	}
