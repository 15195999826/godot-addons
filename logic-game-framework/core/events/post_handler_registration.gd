## PostHandlerRegistration - Post 阶段处理器注册信息
##
## Ability 对它关心的每种 post event kind 各注册一条：Ability.apply_effects 按 component 声明的 kind
## 注册、remove_effects 用 EventProcessor.register_post_handler 返回的闭包注销。
## 没有 filter：TriggerConfig.filter 在 AbilityComponent.match_triggers 里评估。
##
## handler 只许捕获 id：registration 被 processor 的注册表强持，捕获 Ability / Component / context 就接上
## ability → 注销闭包 → 注册表 → registration → handler → ability 的环（见 Ability._make_post_handler）。
class_name PostHandlerRegistration
extends RefCounted


## Ability 注册的是 "<ability_id>_post_<event_kind>"；注销按它查找
var id: String
var event_kind: String
var owner_id: String
var ability_id: String
var config_id: String

## func(event_dict: Dictionary, ctx: HandlerContext) -> bool；返回 true = 至少一个 component 被触发（只进 trace）
var handler: Callable

## 日志 / trace 里的名字，为空时见 get_display_name
var handler_name: String

## owner 进 registry 的序号（register_post_handler 赋值）：同 kind 的注册按它排定派发顺序
var owner_seq: int = 0

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


## 显示名称：handler_name，为空时退回 config_id，再退回 id
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
