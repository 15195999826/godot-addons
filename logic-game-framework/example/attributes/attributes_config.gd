class_name LGFExampleAttributesConfig
extends Resource
## Generator demo 专用属性配置：仅承载演示/自测用的 Example* set。
## example 游戏的属性一律走 example-local config
## （example/<name>/logic/attributes/attributes_config.gd，generator 自动发现），
## 不再往本文件加 set。

const SETS := {
	"ExampleHero": {
		"max_hp": { "baseValue": 120.0 },
		"attack": { "baseValue": 12.0 },
	},
	"ExampleTower": {
		"max_hp": { "baseValue": 350.0 },
		"range": { "baseValue": 6.0 },
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
