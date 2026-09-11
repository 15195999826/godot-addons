## PostHandlerRegistration - Post 阶段处理器注册信息
##
## Ability 对它关心的每种 post event kind 各注册一条：Ability.apply_effects 按 component 声明的 kind
## 注册、remove_effects 用 EventProcessor.register_post_handler 返回的闭包注销。
## 没有 filter：TriggerConfig.filter 在 AbilityComponent.match_triggers 里评估。
##
## handler 只许捕获 id：registration 被 processor 强持，捕获 Ability / Component / context 就接上
## ability → 注销闭包 → processor → registration → handler → ability 的环（见 Ability._make_post_handler）。
class_name PostHandlerRegistration
extends RefCounted


## 处理器唯一标识（Ability 注册的是 "<ability_id>_post_<event_kind>"）
var id: String

## 监听的事件类型
var event_kind: String

## 处理器所属的 Actor ID
var owner_id: String

## 处理器所属的 Ability ID
var ability_id: String

## 处理器所属的 Ability Config ID
var config_id: String

## 处理函数：func(event_dict: Dictionary, ctx: HandlerContext) -> bool；返回 true = 至少一个 component 被触发（只进 trace）
var handler: Callable

## 处理器显示名称（用于日志/调试）
var handler_name: String

## 派发顺序键一：owner 进 registry 的序号（register_post_handler 赋值）
var owner_seq: int = 0

## 派发顺序键二：注册序号（register_post_handler 赋值）
var seq: int = 0

## 派发时交给 handler 的上下文：构造时按本条注册的 id 建好，每次派发复用（id 构造后不再改）
var handler_context: HandlerContext


func _init(
	p_id: String,
	p_event_kind: String,
	p_owner_id: String,
	p_ability_id: String,
	p_config_id: String,
	p_handler: Callable,
	p_handler_name: String = ""
) -> void:
	id = p_id
	event_kind = p_event_kind
	owner_id = p_owner_id
	ability_id = p_ability_id
	config_id = p_config_id
	handler = p_handler
	handler_name = p_handler_name
	handler_context = HandlerContext.new(owner_id, ability_id, config_id)


## 获取显示名称（优先使用 handler_name，否则使用 config_id）
func get_display_name() -> String:
	if handler_name != "":
		return handler_name
	if config_id != "":
		return config_id
	return id


## 调用处理函数；handler 无效或没返回 bool 时按未触发算
func call_handler(event_dict: Dictionary) -> bool:
	if not handler.is_valid():
		return false
	var result: Variant = handler.call(event_dict, handler_context)
	return result is bool and result
