## dota2-auto-battle 属性配置（example-local）。
## AttributeSetGeneratorScript 按 example/<name>/logic/attributes/attributes_config.gd
## 约定自动发现，产物生成到同目录 generated/。
##
## AttributeSet 家族（README「AttributeSet family」）：
##   Dota2BattleActor (hp/max_hp, hp<=max_hp cross-clamp)
##     └─ Dota2Unit (move_speed / attack_damage / attack_range /
##                    attack_interval_ms / aggro_range)
## armor 按设计文档「无伤害公式前保持 planned-but-unused」暂不入 set，
## 不造假公式；Tower/Building set 不在 M1，但家族形状已不阻塞后续扩展。

const SETS := {
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
