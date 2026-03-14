## 振奋 Buff - 防御力 +10，持续 2 秒
class_name HexBattleInspireBuff


## 振奋 Buff 持续时间（毫秒）
const INSPIRE_DURATION_MS := 2000.0

## 振奋 Buff 防御力加成
const INSPIRE_DEF_BONUS := 10.0


## 振奋 Buff 配置
##
## - 效果：防御力 +10（AddBase）
## - 持续：2 秒
## - 标签：buff, inspire
static var INSPIRE_BUFF := (
	AbilityConfig.builder()
	.config_id("buff_inspire")
	.display_name("振奋")
	.description("防御力 +10，持续 2 秒")
	.ability_tags(["buff", "inspire"])
	# 属性修改：防御力 +10
	.component_config(
		StatModifierConfig.builder()
		.modifier("def", AttributeModifier.Type.ADD_BASE, INSPIRE_DEF_BONUS)
		.build()
	)
	# 持续时间：2 秒
	.component_config(TimeDurationConfig.new(INSPIRE_DURATION_MS))
	.build()
)


## 获取振奋 Buff 配置
static func get_config() -> AbilityConfig:
	return INSPIRE_BUFF
