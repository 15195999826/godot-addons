## Expose - 易伤标记主动技能
##
## 近战范围(RANGE=1), 对 current_target 施加 HexBattleExposeBuff。
## 本技能不造成直接伤害 — 全部效果由 buff 自治(pre_damage modify_intent +50%, 5 秒)。
##
## Timeline: 500ms cast, HIT @ 300ms(对齐 Poison / Strike, 动画节奏一致)。
class_name HexBattleExpose


const CONFIG_ID := "skill_expose"
const TIMELINE_ID := "skill_expose"
const COOLDOWN_MS := 4000.0


static var EXPOSE_TIMELINE := TimelineData.new(
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
	.display_name("易伤标记")
	.description("对目标施加易伤 debuff(受到伤害提高 50%, 持续 5 秒)")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash")  # 复用近战挥手 vfx; 无专属 debuff_glow 资产, 不编造新 cue id
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleApplyBuffAction.new(
				HexBattleTargetSelectors.current_target(),
				HexBattleExposeBuff.EXPOSE_BUFF
			),
		])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
