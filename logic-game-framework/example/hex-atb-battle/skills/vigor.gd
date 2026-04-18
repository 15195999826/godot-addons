## 活力被动 - atk 越高，max_hp 越高
##
## 效果：max_hp += atk * 0.1
## 与 Vitality 形成循环依赖，用于验证 AttributeSet 收敛机制
class_name HexBattleVigor


const CONFIG_ID := "passive_vigor"
const SCALING_RATIO := 0.1


static var ABILITY: AbilityConfig = (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("活力")
	.description("atk 越高，max_hp 越高（max_hp += atk * 0.1）")
	.ability_tags(["passive", "buff", "dynamic"])
	.component_config(DynamicStatModifierComponentConfig.new(
		DynamicStatModifierConfig.new(
			HexBattleCharacterAttributeSet.atk_attribute,     # 源
			HexBattleCharacterAttributeSet.max_hp_attribute,  # 目标
			AttributeModifier.Type.ADD_BASE,
			SCALING_RATIO
		)
	))
	.build()
)
