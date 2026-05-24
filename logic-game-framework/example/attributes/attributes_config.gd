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
	# Hex 战斗 actor 公共属性集（hp / max_hp + cross-clamp）
	# 任何 HexBattleActor 子类（CharacterActor / EnvironmentActor）都通过 _extends 继承此 set
	"HexBattleActor": {
		"hp": { "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 100.0, "minValue": 1.0 },
	},
	# Hex 角色专属属性集（demo / preview / scenario 共用）
	# attack_lifesteal_pct: HexBattleGeneralPassive 读取以决定普攻吸血量；默认 0 = 无吸血。
	"HexBattleCharacter": {
		"_extends": "HexBattleActor",
		"atk": { "baseValue": 50.0 },
		"def": { "baseValue": 30.0 },
		"speed": { "baseValue": 100.0 },
		"attack_lifesteal_pct": { "baseValue": 0.0, "minValue": 0.0 },
	},
	# Hex 环境 actor 属性集（M1 起步只继承公共 hp/max_hp，未来按需 + mass / hardness 等）
	"HexBattleEnvironment": {
		"_extends": "HexBattleActor",
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
	# ── dota2-auto-battle 临时技术债（DOTA2 前缀；不改 hex/rts 语义）──────────────
	# example-local config/output 落地前，dota2-auto-battle M1 借用此共享 generator。
	# 命名空间用 Dota2 前缀避免与 hex/Example 撞名；长期目标是迁出到
	# example/dota2-auto-battle/logic/attributes/ 自管。详见该 example 的
	# logic/attributes/README.md 与 CHANGELOG「待迁出技术债」。
	#
	# AttributeSet 家族（actor-attributes.md）：
	#   Dota2BattleActor (hp/max_hp, hp<=max_hp cross-clamp)
	#     └─ Dota2Unit (move_speed / attack_damage / attack_range /
	#                    attack_interval_ms / aggro_range)
	# armor 按设计文档「无伤害公式前保持 planned-but-unused」暂不入 set，
	# 不造假公式；Tower/Building set 不在 M1，但家族形状已不阻塞后续扩展。
	"Dota2BattleActor": {
		"hp": { "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 100.0, "minValue": 1.0 },
	},
	"Dota2Unit": {
		"_extends": "Dota2BattleActor",
		"move_speed": { "baseValue": 90.0, "minValue": 0.0 },
		"attack_damage": { "baseValue": 12.0, "minValue": 0.0 },
		"attack_range": { "baseValue": 60.0, "minValue": 0.0 },
		"attack_interval_ms": { "baseValue": 1000.0, "minValue": 1.0 },
		"aggro_range": { "baseValue": 350.0, "minValue": 0.0 },
	},
}
