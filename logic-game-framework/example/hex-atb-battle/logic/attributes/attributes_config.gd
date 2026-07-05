## hex-atb-battle 属性配置（example-local）。
## AttributeSetGeneratorScript 按 example/<name>/logic/attributes/attributes_config.gd
## 约定自动发现，产物生成到同目录 generated/。

const SETS := {
	# Hex 战斗 actor 公共属性集（hp / max_hp + cross-clamp）
	# 任何 HexBattleActor 子类（CharacterActor / EnvironmentActor）都通过 _extends 继承此 set
	"HexBattleActor": {
		"hp": { "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" },
		"max_hp": { "baseValue": 100.0, "minValue": 1.0 },
	},
	# Hex 角色专属属性集（demo / preview / scenario 共用）
	# attack_lifesteal_pct: HexBattleGeneralPassive 读取以决定普攻吸血量；默认 0 = 无吸血。
	# hp_regen_per_sec:     HexBattleGeneralPassive periodic timeline 每秒恢复 HP；默认 0 = 无回血。
	"HexBattleCharacter": {
		"_extends": "HexBattleActor",
		"atk": { "baseValue": 50.0 },
		"def": { "baseValue": 30.0 },
		"speed": { "baseValue": 100.0 },
		"attack_lifesteal_pct": { "baseValue": 0.0, "minValue": 0.0 },
		"hp_regen_per_sec": { "baseValue": 0.0, "minValue": 0.0 },
	},
	# Hex 环境 actor 属性集（M1 起步只继承公共 hp/max_hp，未来按需 + mass / hardness 等）
	"HexBattleEnvironment": {
		"_extends": "HexBattleActor",
	},
}
