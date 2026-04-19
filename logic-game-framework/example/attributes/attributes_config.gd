class_name LGFExampleAttributesConfig
extends Resource

const SETS := {
	"ExampleHero": {
		"max_hp": { "baseValue": 120.0 },
		"attack": { "baseValue": 12.0 },
	},
	"ExampleTower": {
		"max_hp": { "baseValue": 350.0 },
		"range": { "baseValue": 6.0 },
	},
	# HexBattle 角色属性集
	"HexBattleCharacter": {
		"hp": { "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 100.0, "minValue": 1.0 },
		"atk": { "baseValue": 50.0 },
		"def": { "baseValue": 30.0 },
		"speed": { "baseValue": 100.0 },
	},
	# 派生属性示例：使用 damage + max_hp 模式
	"ExampleDerivedDemo": {
		# 基础属性
		"damage": { "baseValue": 0.0, "minValue": 0.0 },
		"max_hp": { "baseValue": 100.0, "minValue": 1.0 },
		"strength": { "baseValue": 10.0 },
		# 派生属性（只读，实时计算）
		"current_hp": { "derived": { "op": "sub", "left": "max_hp", "right": "damage" } },
		"attack": { "derived": { "op": "mul", "left": "strength", "right": 2.5 } },
	},
}
