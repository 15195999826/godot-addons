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
## ========== 条件分两段（同 TriggerConfig）==========
##
## - event_filter(event_dict, me: HandlerContext) -> bool：只看事件 + 本 ability 的三个 id，派发时在重建 context 之前跑，
##   不过就整条跳过。「是不是我造成的 / 打在我身上的」写这里。
## - context_filter(event_dict, ctx: AbilityLifecycleContext) -> bool：要完整 ctx，只对通过 event_filter 的登记、重建
##   context 之后跑。构造函数的第三个位置参数是同一个字段（旧写法，保留兼容，新代码用链式）。
## 两段都可选；链式方法是 copy-with，不改原对象。
##
## @example
## ```gdscript
## PreEventConfig.new(
##     "pre_damage",
##     func(mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
##         return EventPhase.modify_intent(ctx.ability.id, [
##             Modification.multiply("damage", 0.7),
##         ]),
##     Callable(),
##     "减伤30%"
## ).event_filter(func(event: Dictionary, me: HandlerContext) -> bool:
##     return event.get("target_actor_id") == me.owner_id)
## ```
class_name PreEventConfig
extends AbilityComponentConfig


## 事件类型
var event_kind: String

## 第二段过滤（context_filter）：func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool
var filter: Callable

## 处理器函数
var handler: Callable

## 处理器名称
var name: String

## 第一段过滤：func(event: Dictionary, me: HandlerContext) -> bool。经 event_filter() 设置。
var _event_filter: Callable


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


## 返回带第一段条件的新 PreEventConfig（copy-with）。
func event_filter(fn: Callable) -> PreEventConfig:
	var copy := _copy()
	copy._event_filter = fn
	return copy


## 返回带第二段条件的新 PreEventConfig（copy-with）。
func context_filter(fn: Callable) -> PreEventConfig:
	var copy := _copy()
	copy.filter = fn
	return copy


func get_event_filter() -> Callable:
	return _event_filter


func has_event_filter() -> bool:
	return _event_filter.is_valid()


## 创建对应的 PreEventComponent 实例
func create_component() -> AbilityComponent:
	return PreEventComponent.new(self)


func _copy() -> PreEventConfig:
	var copy := PreEventConfig.new(event_kind, handler, filter, name)
	copy._event_filter = _event_filter
	return copy
