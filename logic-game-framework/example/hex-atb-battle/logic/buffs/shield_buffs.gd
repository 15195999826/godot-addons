## Typed shield buff configs.
##
## These are data-only shield abilities used by tests and future shield-granting
## skills. Existing Ward remains the universal/all-damage shield instance.
class_name HexBattleShieldBuffs


const PHYSICAL_CONFIG_ID := "buff_physical_shield"
const MAGICAL_CONFIG_ID := "buff_magical_shield"
const SHIELD_CAPACITY := 30.0
const DURATION_MS := 6000.0
const TYPED_PRIORITY := 10


static var PHYSICAL_SHIELD_BUFF := (
	AbilityConfig.builder()
	.config_id(PHYSICAL_CONFIG_ID)
	.display_name("物理护盾")
	.description("吸收 30 点物理伤害，持续 6 秒")
	.ability_tags(["buff", "positive"])
	.component_config(HexBattleShieldComponentConfig.new(
		SHIELD_CAPACITY,
		["physical"],
		TYPED_PRIORITY,
		"independent"
	))
	.component_config(TimeDurationConfig.new(DURATION_MS))
	.build()
)


static var MAGICAL_SHIELD_BUFF := (
	AbilityConfig.builder()
	.config_id(MAGICAL_CONFIG_ID)
	.display_name("魔法护盾")
	.description("吸收 30 点魔法伤害，持续 6 秒")
	.ability_tags(["buff", "positive"])
	.component_config(HexBattleShieldComponentConfig.new(
		SHIELD_CAPACITY,
		["magical"],
		TYPED_PRIORITY,
		"independent"
	))
	.component_config(TimeDurationConfig.new(DURATION_MS))
	.build()
)
