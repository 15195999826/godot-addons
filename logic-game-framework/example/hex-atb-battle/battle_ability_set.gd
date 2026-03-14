## BattleAbilitySet - 战斗技能集
##
## 扩展 AbilitySet，添加冷却系统支持
class_name BattleAbilitySet
extends AbilitySet


# ========== 冷却系统 ==========

## 检查技能是否在冷却中
func is_on_cooldown(ability_config_id: String) -> bool:
	var cooldown_tag := _get_cooldown_tag(ability_config_id)
	return has_tag(cooldown_tag)


## 获取技能剩余冷却时间
func get_cooldown_remaining(ability_config_id: String) -> float:
	var cooldown_tag := _get_cooldown_tag(ability_config_id)
	return tag_container.get_auto_duration_remaining(cooldown_tag)


## 开始技能冷却
func start_cooldown(ability_config_id: String, duration: float) -> void:
	var cooldown_tag := _get_cooldown_tag(ability_config_id)
	add_auto_duration_tag(cooldown_tag, duration)


## 重置技能冷却
func reset_cooldown(ability_config_id: String) -> void:
	var cooldown_tag := _get_cooldown_tag(ability_config_id)
	tag_container.remove_auto_duration_tag(cooldown_tag)


## 获取冷却标签名
func _get_cooldown_tag(ability_config_id: String) -> String:
	return "cooldown:%s" % ability_config_id


# ========== 工厂方法 ==========

static func create_battle_ability_set(p_owner_actor_id: String, p_attribute_set: BaseGeneratedAttributeSet = null) -> BattleAbilitySet:
	return BattleAbilitySet.new(p_owner_actor_id, p_attribute_set)
