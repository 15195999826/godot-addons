## 圣光治愈 - 治疗技能
##
## 单文件自包含：config + timeline + (私有 action 若有)
class_name HexBattleHolyHeal


const CONFIG_ID := "skill_holy_heal"
const TIMELINE_ID := "skill_holy_heal"
const COOLDOWN_MS := 4000.0


# ========== Timeline ==========

## 远程治疗：0ms 发送动画提示，0.4s 时生效
static var HOLY_HEAL_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	600.0,
	{
		TimelineTags.START: 0.0,
		TimelineTags.HEAL: 400.0,
		TimelineTags.END: 600.0,
	}
)


# ========== Ability ==========

static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("圣光治愈")
	.description("治疗友方单位，恢复生命值")
	.ability_tags(["skill", "active", "heal", "ally"])
	.meta(HexBattleSkillMetaKeys.RANGE, 3)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_heal")
		)])
		.on_tag(TimelineTags.HEAL, [HexBattleHealAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(40.0)
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
