class_name AbilityLifecycleContext
extends RefCounted
## Ability 生命周期上下文
##
## 在 Ability 的 apply/remove/event 等生命周期方法中传递的上下文对象。
## 包含 Ability 运行所需的所有依赖引用。

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


func _init(
	p_owner_actor_id: String,
	p_attribute_set: BaseGeneratedAttributeSet,
	p_ability: Ability,
	p_ability_set: AbilitySet,
	p_event_processor: EventProcessor
) -> void:
	owner_actor_id = p_owner_actor_id
	attribute_set = p_attribute_set
	ability = p_ability
	ability_set = p_ability_set
	event_processor = p_event_processor
