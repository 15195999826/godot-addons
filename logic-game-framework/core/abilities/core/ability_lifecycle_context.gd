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

## 能力拥有者的 ID
var owner_actor_id: String

## 拥有者的属性集
var attribute_set: BaseGeneratedAttributeSet

## 当前能力实例
var ability: Ability

## 能力集合
var ability_set: AbilitySet

## 事件处理器
var event_processor: EventProcessor

## 拥有者所属的 GameplayInstance（按 owner_actor_id 反查）。
## owner 未注册进 GameWorld（孤立单测）时为 null；依赖它的逻辑应 Log.assert_crash。
var instance: GameplayInstance


func _init(
	p_owner_actor_id: String,
	p_attribute_set: BaseGeneratedAttributeSet,
	p_ability: Ability,
	p_ability_set: AbilitySet,
	p_event_processor: EventProcessor,
	p_instance: GameplayInstance
) -> void:
	owner_actor_id = p_owner_actor_id
	attribute_set = p_attribute_set
	ability = p_ability
	ability_set = p_ability_set
	event_processor = p_event_processor
	instance = p_instance
