## 技能-职业绑定配置
##
## 每个职业的默认技能直接返回 AbilityConfig；不再走 SkillType 枚举中转。
## 加一个职业绑定的新技能：
##   1. 在 skills/ 下新建技能文件并导出 ABILITY static var
##   2. 在 skills/all_skills.gd::register_all_timelines() 加一行（若有 timeline）
##   3. 在这里 get_class_skill 的 match 加一条职业 → Class.ABILITY
class_name HexBattleSkillConfig


static func get_class_skill(char_class: HexBattleClassConfig.CharacterClass) -> AbilityConfig:
	match char_class:
		HexBattleClassConfig.CharacterClass.PRIEST:
			return HexBattleHolyHeal.ABILITY
		HexBattleClassConfig.CharacterClass.WARRIOR:
			return HexBattleStrike.ABILITY
		HexBattleClassConfig.CharacterClass.ARCHER:
			return HexBattlePreciseShot.ABILITY
		HexBattleClassConfig.CharacterClass.MAGE:
			return HexBattleFireball.ABILITY
		HexBattleClassConfig.CharacterClass.BERSERKER:
			return HexBattleCrushingBlow.ABILITY
		HexBattleClassConfig.CharacterClass.ASSASSIN:
			return HexBattleSwiftStrike.ABILITY
		_:
			return HexBattleStrike.ABILITY
