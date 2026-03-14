## PreEvent 组件配置
##
## 用于配置 PreEventComponent，定义事件预处理器。
##
## ========== handler 签名约定 ==========
##
## handler 必须满足：func(MutableEvent, AbilityLifecycleContext) -> Intent
## 返回值必须是 Intent，不可省略 return。运行时会通过 assert 校验返回类型。
##
## 返回值选项：
## - EventPhase.pass_intent()                    → 放行，不做任何修改
## - EventPhase.modify_intent(id, [Modification]) → 修改事件字段（如减伤）
## - EventPhase.cancel_intent(id, reason)         → 取消事件（如免疫）
##
## @example
## ```gdscript
## PreEventConfig.new(
##     "pre_damage",
##     func(mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
##         return EventPhase.modify_intent(ctx.ability.id, [
##             Modification.multiply("damage", 0.7),
##         ]),
##     func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool:
##         return event.get("target_actor_id") == ctx.owner_actor_id,
##     "减伤30%"
## )
## ```
class_name PreEventConfig
extends AbilityComponentConfig


## 事件类型
var event_kind: String

## 过滤器函数
var filter: Callable

## 处理器函数
var handler: Callable

## 处理器名称
var name: String


func _init(
	event_kind: String = "",
	handler: Callable = Callable(),
	filter: Callable = Callable(),
	name: String = ""
) -> void:
	self.event_kind = event_kind
	self.handler = handler
	self.filter = filter
	self.name = name


## 创建对应的 PreEventComponent 实例
func create_component() -> AbilityComponent:
	return PreEventComponent.new(self)
