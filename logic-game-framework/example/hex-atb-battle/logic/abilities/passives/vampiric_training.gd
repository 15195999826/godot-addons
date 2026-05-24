## VampiricTraining · attack_lifesteal_pct 属性来源示例
##
## 普通被动. 通过 StatModifier 给 owner 增加 attack_lifesteal_pct;
## 不自己监听 attack_landed —— 监听由 HexBattleGeneralPassive 统一处理.
##
## Break 可以禁用本 passive (打 `passive` tag); 属性归零后 HexBattleGeneralPassive
## 自然 no-op. 这是 phase B 验证 "Break 禁源不禁规则桥" 的契约样本.
class_name HexBattleVampiricTraining


const CONFIG_ID := "passive_vampiric_training"
## 默认 50% 普攻吸血; scenario 直接复用此常量做断言.
const LIFESTEAL_PCT := 0.5


static var ABILITY: AbilityConfig = (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("血怒训练")
	.description("增加 %d%% 普攻吸血（通过 attack_lifesteal_pct 属性, 由 HexBattleGeneralPassive 触发）" % int(LIFESTEAL_PCT * 100))
	.ability_tags(["passive", "lifesteal"])
	.component_config(
		StatModifierConfig.builder()
		.modifier(HexBattleCharacterAttributeSet.attack_lifesteal_pct_attribute, AttributeModifier.Type.ADD_BASE, LIFESTEAL_PCT)
		.build()
	)
	.build()
)
