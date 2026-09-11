class_name AbilityLifecycleContext
extends RefCounted
## Ability 生命周期上下文
##
## 在 Ability 的 apply/remove/event 等生命周期方法中传递的上下文对象。
## 包含 Ability 运行所需的所有依赖引用。
##
## 栈作用域：只活在一次生命周期调用的调用栈上。`instance` 是强引用——Component / Ability
## 把 context（或 context.instance）存进字段，就接上 instance → actor → ability_set → ability
## → component → context → instance 这条环；RefCounted 没有循环 GC，整张图从此不再释放。

## debug 构建下的存活计数（release 不计）：测试在调用返回后断言它回到基线。
static var _debug_live_count := 0

## 能力拥有者的 ID
var owner_actor_id: String

## 拥有者的属性集
var attribute_set: BaseGeneratedAttributeSet

## 当前能力实例
var ability: Ability

## 能力集合
var ability_set: AbilitySet

## 拥有者所属的 GameplayInstance（按 owner_actor_id 反查）。
## owner 未注册进 GameWorld（孤立单测、注册前的 grant）时为 null：必须有世界的逻辑判空后响亮报错，允许缺席的判空降级。
var instance: GameplayInstance

## 事件处理器：派生自 instance（`instance.event_processor`），instance 为 null 时为 null。
## 不可赋值（setter 报错）；backing 字段恒为空，调试器里读到的 null 不代表 processor 缺席。
var event_processor: EventProcessor:
	get:
		return instance.event_processor if instance != null else null
	set(_value):
		Log.assert_crash(false, "AbilityLifecycleContext", "event_processor 派生自 instance，不可赋值")


func _init(
	p_owner_actor_id: String,
	p_attribute_set: BaseGeneratedAttributeSet,
	p_ability: Ability,
	p_ability_set: AbilitySet,
	p_instance: GameplayInstance
) -> void:
	owner_actor_id = p_owner_actor_id
	attribute_set = p_attribute_set
	ability = p_ability
	ability_set = p_ability_set
	instance = p_instance
	if OS.is_debug_build():
		_debug_live_count += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and OS.is_debug_build():
		_debug_live_count -= 1


## 当前存活的实例数（debug 构建；release 恒为 0）。
static func get_debug_live_count() -> int:
	return _debug_live_count
