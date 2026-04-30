## 职业配置
class_name HexBattleClassConfig


# ========== 职业类型 ==========

enum CharacterClass {
	PRIEST,
	WARRIOR,
	ARCHER,
	MAGE,
	BERSERKER,
	ASSASSIN
}


# ========== 职业配置表 ==========
# 注意：属性定义已迁移到 attributes_config.gd 中的 HexBattleCharacter 属性集
# 使用 HexBattleCharacterAttributeSet 生成式属性集

## 职业配置项
class ClassConfigItem:
	var name: String
	var stats: Dictionary  # { hp, max_hp, atk, def, speed }
	
	func _init(p_name: String, p_stats: Dictionary) -> void:
		name = p_name
		stats = p_stats


## 获取职业配置
static func get_class_config(char_class: CharacterClass) -> ClassConfigItem:
	match char_class:
		CharacterClass.PRIEST:
			return ClassConfigItem.new("牧师", {
				"hp": 100.0, "max_hp": 100.0, "atk": 30.0, "def": 30.0, "speed": 100.0
			})
		CharacterClass.WARRIOR:
			return ClassConfigItem.new("战士", {
				"hp": 100.0, "max_hp": 100.0, "atk": 50.0, "def": 30.0, "speed": 100.0
			})
		CharacterClass.ARCHER:
			return ClassConfigItem.new("弓箭手", {
				"hp": 100.0, "max_hp": 100.0, "atk": 50.0, "def": 30.0, "speed": 100.0
			})
		CharacterClass.MAGE:
			return ClassConfigItem.new("法师", {
				"hp": 70.0, "max_hp": 70.0, "atk": 80.0, "def": 20.0, "speed": 70.0
			})
		CharacterClass.BERSERKER:
			return ClassConfigItem.new("狂战士", {
				"hp": 150.0, "max_hp": 150.0, "atk": 70.0, "def": 40.0, "speed": 70.0
			})
		CharacterClass.ASSASSIN:
			return ClassConfigItem.new("刺客", {
				"hp": 80.0, "max_hp": 80.0, "atk": 40.0, "def": 25.0, "speed": 140.0
			})
		_:
			return ClassConfigItem.new("未知", {
				"hp": 100.0, "max_hp": 100.0, "atk": 50.0, "def": 30.0, "speed": 100.0
			})


## 职业枚举转字符串
static func class_to_string(char_class: CharacterClass) -> String:
	match char_class:
		CharacterClass.PRIEST:
			return "Priest"
		CharacterClass.WARRIOR:
			return "Warrior"
		CharacterClass.ARCHER:
			return "Archer"
		CharacterClass.MAGE:
			return "Mage"
		CharacterClass.BERSERKER:
			return "Berserker"
		CharacterClass.ASSASSIN:
			return "Assassin"
		_:
			return "Unknown"


## 字符串转职业枚举
static func string_to_class(s: String) -> CharacterClass:
	match s:
		"Priest":
			return CharacterClass.PRIEST
		"Warrior":
			return CharacterClass.WARRIOR
		"Archer":
			return CharacterClass.ARCHER
		"Mage":
			return CharacterClass.MAGE
		"Berserker":
			return CharacterClass.BERSERKER
		"Assassin":
			return CharacterClass.ASSASSIN
		_:
			return CharacterClass.WARRIOR
