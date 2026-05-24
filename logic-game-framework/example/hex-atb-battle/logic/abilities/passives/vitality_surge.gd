## VitalitySurge · hp_regen_per_sec 属性来源示例
##
## 普通被动. 通过 StatModifier 给 owner 增加 hp_regen_per_sec;
## 周期回血 tick 由 HexBattleGeneralPassive 的 regen timeline 驱动 (本 passive 不挂 trigger).
##
## Break 可以禁用本 passive (打 `passive` tag); 属性归零后 GeneralPassive 周期 tick 自然 no-op,
## 但 timeline 继续转动, 等 Break 期满 VitalitySurge 自动 re-enable, 回血继续.
class_name HexBattleVitalitySurge


const CONFIG_ID := "passive_vitality_surge"
## 默认 5 hp/s, scenario 直接复用此常量做断言.
const HP_PER_SEC := 5.0


static var ABILITY: AbilityConfig = (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("生命涌动")
	.description("每秒恢复 %d HP（通过 hp_regen_per_sec 属性, 由 HexBattleGeneralPassive 周期触发）" % int(HP_PER_SEC))
	.ability_tags(["passive", "regen"])
	.component_config(
		StatModifierConfig.builder()
		.modifier(HexBattleCharacterAttributeSet.hp_regen_per_sec_attribute, AttributeModifier.Type.ADD_BASE, HP_PER_SEC)
		.build()
	)
	.build()
)
