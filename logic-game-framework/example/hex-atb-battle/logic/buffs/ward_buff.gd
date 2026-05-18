## Ward Buff - 基础护盾（Shield Rune 风格）
##
## V1 设计：30 容量、6 秒、all 伤害类型、stacking_policy = independent。
## 这里的 all = universal shield，可吸收 physical / magical / pure。
## 重复施放会产生独立 Ward 实例并存，由 ShieldResolver 按 LIFO（grant_index desc）顺序消耗。
##
## 没有 on_break / on_expire 回调 —— 破裂或到期就只是 ability 自然 revoke，
## 不产生 AoE / 治疗等二次效果。亚巴顿风格的破裂爆炸留到 V2 的 Aphotic Ward 实现。
class_name HexBattleWardBuff


const CONFIG_ID := "buff_ward"
const SHIELD_CAPACITY := 30.0
const DURATION_MS := 6000.0
const PRIORITY := 0


static var WARD_BUFF := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("全伤害护盾")
	.description("吸收 30 点任意伤害，持续 6 秒")
	.ability_tags(["buff", "positive"])
	.component_config(HexBattleShieldComponentConfig.new(
		SHIELD_CAPACITY,
		["all"],
		PRIORITY,
		"independent"
	))
	.component_config(TimeDurationConfig.new(DURATION_MS))
	.build()
)
