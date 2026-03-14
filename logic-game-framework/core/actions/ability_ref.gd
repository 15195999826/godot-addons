class_name AbilityRef
extends RefCounted

## Ability 轻量引用
##
## 用于 ExecutionContext 中传递 Ability 信息，避免传递完整 Ability 实例。
## 提供 resolve() 方法按需获取完整 Ability 实例。
##
## 解析路径：
## GameWorld.get_actor(owner_actor_id) → Actor
## IAbilitySetOwner.get_ability_set(actor) → AbilitySet
## ability_set.find_ability_by_id(id) → Ability

## Ability 实例 ID
var id: String

## Ability 配置 ID
var config_id: String

## 拥有者 Actor ID
var owner_actor_id: String

## 来源 Actor ID（通常与 owner 相同，但 buff 可能由其他 Actor 施加）
var source_actor_id: String


func _init(
	p_id: String = "",
	p_config_id: String = "",
	p_owner_actor_id: String = "",
	p_source_actor_id: String = ""
) -> void:
	id = p_id
	config_id = p_config_id
	owner_actor_id = p_owner_actor_id
	source_actor_id = p_source_actor_id


## 从 Ability 实例创建 AbilityRef
static func from_ability(in_ability: Ability) -> AbilityRef:
	if in_ability == null:
		return null
	return AbilityRef.new(
		in_ability.id,
		in_ability.config_id,
		in_ability.owner_actor_id,
		in_ability.source_actor_id
	)


## 创建 AbilityRef
static func create(
	p_id: String,
	p_config_id: String,
	p_owner_actor_id: String,
	p_source_actor_id: String = ""
) -> AbilityRef:
	var ref := AbilityRef.new(p_id, p_config_id, p_owner_actor_id, p_source_actor_id)
	if ref.source_actor_id.is_empty():
		ref.source_actor_id = p_owner_actor_id
	return ref


## 解析获取完整 Ability 实例
##
## 解析路径：
## 1. GameWorld.get_actor(owner_actor_id) → Actor
## 2. IAbilitySetOwner.get_ability_set(actor) → AbilitySet
## 3. ability_set.find_ability_by_id(id) → Ability
##
## 返回 null 的情况：
## - owner_actor_id 为空
## - Actor 不存在
## - Actor 未实现 IAbilitySetOwner 协议
## - AbilitySet 中找不到对应 Ability
func resolve() -> Ability:
	if owner_actor_id.is_empty():
		return null
	
	var actor := GameWorld.get_actor(owner_actor_id)
	if actor == null:
		return null
	
	var ability_set := IAbilitySetOwner.get_ability_set(actor)
	if ability_set == null:
		return null
	
	return ability_set.find_ability_by_id(id)


## 检查引用是否有效（非空 ID）
func is_valid() -> bool:
	return not id.is_empty() and not owner_actor_id.is_empty()


## 序列化为 Dictionary
func to_dict() -> Dictionary:
	return {
		"id": id,
		"configId": config_id,
		"ownerActorId": owner_actor_id,
		"sourceActorId": source_actor_id,
	}


## 从 Dictionary 反序列化
static func from_dict(d: Dictionary) -> AbilityRef:
	return AbilityRef.new(
		d.get("id", ""),
		d.get("configId", ""),
		d.get("ownerActorId", ""),
		d.get("sourceActorId", "")
	)
