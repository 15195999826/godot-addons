## Break #B2 - 破坏主动技能 (passive control)
##
## 命中目标后 grant HexBattleBreakBuff (duration 默认 2000ms)。
## Break buff 禁用目标当前所有 passive ability (Thorn / Vigor / Vitality / DemonForm 等)。
## 多个 Break 重叠时 引用计数, 只有最后一个 Break 移除后 passive 才恢复。
class_name HexBattleBreak


const CONFIG_ID := "skill_break"
const TIMELINE_ID := "skill_break"
const BREAK_DURATION_MS := 2000.0
const COOLDOWN_MS := 6000.0


static var BREAK_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


static var ABILITY := create_config(BREAK_DURATION_MS)


static func create_config(duration_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("破坏")
		.description("命中目标后使其 %.1f 秒内被动技能失效" % (duration_ms / 1000.0))
		.ability_tags(["skill", "active", "melee", "enemy", "control", "passive_break"])
		.meta(HexBattleSkillMetaKeys.RANGE, 1)
		.meta("break_duration_ms", duration_ms)
		.active_use(
			ActiveUseConfig.builder()
			.timeline_id(TIMELINE_ID)
			.on_timeline_start([StageCueAction.new(
				HexBattleTargetSelectors.current_target(),
				Resolvers.str_val("melee_slash"),
			)])
			.on_tag(TimelineTags.HIT, [
				HexBattleApplyBuffAction.new(
					HexBattleTargetSelectors.current_target(),
					HexBattleBreakBuff.create_config(duration_ms),
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
