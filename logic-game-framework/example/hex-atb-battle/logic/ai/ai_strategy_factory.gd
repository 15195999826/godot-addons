## AIStrategyFactory - AI 策略工厂
##
## 根据职业返回对应的 AI 策略实例。
## 策略是无状态共享实例，所有同策略角色共用一个。
class_name AIStrategyFactory


# ========== 共享实例（无状态，可安全共享） ==========

static var _melee_attack: AIStrategy = MeleeAttackStrategy.new()
static var _ranged_attack: AIStrategy = RangedAttackStrategy.new()
static var _ranged_support: AIStrategy = RangedSupportStrategy.new()


## 根据职业获取 AI 策略
static func get_strategy(char_class: HexBattleClassConfig.CharacterClass) -> AIStrategy:
	match char_class:
		HexBattleClassConfig.CharacterClass.WARRIOR:
			return _melee_attack
		HexBattleClassConfig.CharacterClass.BERSERKER:
			return _melee_attack
		HexBattleClassConfig.CharacterClass.ASSASSIN:
			return _melee_attack
		HexBattleClassConfig.CharacterClass.ARCHER:
			return _ranged_attack
		HexBattleClassConfig.CharacterClass.MAGE:
			return _ranged_attack
		HexBattleClassConfig.CharacterClass.PRIEST:
			return _ranged_support
		_:
			return _melee_attack
