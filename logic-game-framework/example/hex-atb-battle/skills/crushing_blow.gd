## 毁灭重击 - 近战重击
##
## 阶段：START → WINDUP（蓄力） → HIT → END
class_name HexBattleCrushingBlow


const CONFIG_ID := "skill_crushing_blow"
const TIMELINE_ID := "skill_crushing_blow"
const COOLDOWN_MS := 5000.0


static var CRUSHING_BLOW_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	1000.0,
	{
		TimelineTags.START: 0.0,
		TimelineTags.WINDUP: 300.0,
		TimelineTags.HIT: 600.0,
		TimelineTags.END: 1000.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("毁灭重击")
	.description("近战重击，造成毁灭性伤害")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_heavy")
		)])
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			90.0,
			BattleEvents.DamageType.PHYSICAL
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
