## Ward - 自施护盾主动技能
##
## RANGE 0：caster 给自己挂一个 HexBattleWardBuff（独立实例）。
## V1 不支持友军施放（target_selectors 暂无 self / target ally 区分需要时再加）。
##
## Timeline：500ms 短 cast，HIT @ 300ms（节奏对齐 Strike / Poison）。
class_name HexBattleWard


const CONFIG_ID := "skill_ward"
const TIMELINE_ID := "skill_ward"
const COOLDOWN_MS := 4000.0


static var WARD_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("护盾术")
	.description("为自己生成一个吸收 30 点伤害的护盾，持续 6 秒")
	.ability_tags(["skill", "active", "self", "shield"])
	.meta(HexBattleSkillMetaKeys.RANGE, 0)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.HIT, [
			HexBattleApplyShieldAction.new(
				HexBattleTargetSelectors.ability_owner(),
				HexBattleWardBuff.WARD_BUFF
			),
		])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
