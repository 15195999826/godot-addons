## 疾风连刺 - 快速多段近战攻击（三连击）
##
## 阶段：START → HIT1 → HIT2 → HIT3 → END
class_name HexBattleSwiftStrike


const CONFIG_ID := "skill_swift_strike"
const TIMELINE_ID := "skill_swift_strike"
const COOLDOWN_MS := 3000.0


static var SWIFT_STRIKE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	400.0,
	{
		TimelineTags.HIT1: 100.0,
		TimelineTags.HIT2: 200.0,
		TimelineTags.HIT3: 300.0,
		TimelineTags.END: 400.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("疾风连刺")
	.description("快速近战攻击，三连击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_combo"),
			Resolvers.dict_val({ "hits": 3 })
		)])
		.on_tag(TimelineTags.HIT1, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(10.0),
			BattleEvents.DamageType.PHYSICAL
		)])
		.on_tag(TimelineTags.HIT2, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(10.0),
			BattleEvents.DamageType.PHYSICAL
		)])
		.on_tag(TimelineTags.HIT3, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(10.0),
			BattleEvents.DamageType.PHYSICAL
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
