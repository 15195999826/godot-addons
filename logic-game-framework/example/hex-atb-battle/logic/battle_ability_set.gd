## BattleAbilitySet - 战斗技能集
##
## 扩展 AbilitySet，添加冷却系统支持
class_name BattleAbilitySet
extends AbilitySet


# ========== 行动阻塞 ==========

## ATB 冻结只认「行动」: 角色花行动条换来的那个行动 (主动技能 active / 移动 action) 在飞才停充能。
## buff / 被动 / 内建能力的周期 timeline (中毒 DOT、涌动、恶魔形态、回血) 在身期间全程「执行中」,
## 当成阻塞 = 持有者整段不充能不行动 (中毒即定身、恶魔形态持有者整场零行动)。
## 白名单而非逐个豁免: 新写的周期能力默认不冻结; 主动技能必带 active tag 由 manifest lint 守。
func _is_blocking_execution(ability: Ability) -> bool:
	return ability.has_ability_tag(HexBattleSkillTags.TAG_ACTIVE) or ability.has_ability_tag(HexBattleSkillTags.TAG_ACTION)


## 除内建能力外是否还有 execution 在飞 —— 预览收尾判 idle 要等的那张清单 (DOT 这类周期 buff 也等它跳完),
## 与「ATB 冻结只认行动」是两个问题。内建能力的周期 timeline 永不停, 算进来预览永远收不了尾。
func has_pending_execution() -> bool:
	for ability in get_abilities():
		if ability.has_executing_instance() and not ability.has_ability_tag(HexBattleSkillTags.TAG_INTRINSIC):
			return true
	return false


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
