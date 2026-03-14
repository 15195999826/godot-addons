## 技能配置
##
## 技能类型枚举和职业-技能映射。
## 技能的具体数值（伤害、射程、冷却等）定义在 skill_abilities.gd 中，
## 作为 AbilityConfig 的唯一数据源。
class_name HexBattleSkillConfig


# ========== 技能类型 ==========

enum SkillType {
	HOLY_HEAL,
	SLASH,
	PRECISE_SHOT,
	FIREBALL,
	CRUSHING_BLOW,
	SWIFT_STRIKE
}


# ========== 职业对应技能映射 ==========

static func get_class_skill(char_class: HexBattleClassConfig.CharacterClass) -> SkillType:
	match char_class:
		HexBattleClassConfig.CharacterClass.PRIEST:
			return SkillType.HOLY_HEAL
		HexBattleClassConfig.CharacterClass.WARRIOR:
			return SkillType.SLASH
		HexBattleClassConfig.CharacterClass.ARCHER:
			return SkillType.PRECISE_SHOT
		HexBattleClassConfig.CharacterClass.MAGE:
			return SkillType.FIREBALL
		HexBattleClassConfig.CharacterClass.BERSERKER:
			return SkillType.CRUSHING_BLOW
		HexBattleClassConfig.CharacterClass.ASSASSIN:
			return SkillType.SWIFT_STRIKE
		_:
			return SkillType.SLASH
