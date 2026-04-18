## 生命力被动 - max_hp 越高，atk 越高
##
## 效果：atk += max_hp * 0.01
## 与 Vigor 形成循环依赖，用于验证 AttributeSet 收敛机制
class_name HexBattleVitality


const CONFIG_ID := "passive_vitality"
const SCALING_RATIO := 0.01


static var ABILITY: AbilityConfig = (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("生命力")
	.description("max_hp 越高，atk 越高（atk += max_hp * 0.01）")
	.ability_tags(["passive", "buff", "dynamic"])
	.component_config(DynamicStatModifierComponentConfig.new(
		DynamicStatModifierConfig.new(
			HexBattleCharacterAttributeSet.max_hp_attribute,  # 源
			HexBattleCharacterAttributeSet.atk_attribute,     # 目标
			AttributeModifier.Type.ADD_BASE,
			SCALING_RATIO
		)
	))
	.build()
)
