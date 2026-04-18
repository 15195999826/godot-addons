## Strike - 近战基础攻击
##
## （原名 SLASH）：相邻格物理伤害，暴击时额外 10 点
##
## NOTE: 当前 damage=50 写死；后续"契约改造"会改为 Resolver 读 caster.atk，
## 让 hook 类技能（Expose/Ward/Thorns）能正确作用于 attribute scaling。
class_name HexBattleStrike


const CONFIG_ID := "skill_strike"
const TIMELINE_ID := "skill_strike"
const COOLDOWN_MS := 2000.0


static var STRIKE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.START: 0.0,
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("普通攻击")
	.description("近战攻击，对敌人造成物理伤害（暴击时额外伤害）")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash")
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				50.0,
				BattleEvents.DamageType.PHYSICAL
			).on_critical(
				HexBattleDamageAction.new(
					HexBattleTargetSelectors.current_target(),
					10.0,
					BattleEvents.DamageType.PHYSICAL
				)
			),
		])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
