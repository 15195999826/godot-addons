## Silence #B1 - 沉默主动技能 (soft control)
##
## 命中目标后 grant HexBattleSilenceBuff (duration 默认 2000ms)。
## 阻挡目标"真正的 active skill" (Fireball / Poison / Stun / etc), 不挡 Strike / Move。
##
## 与 Stun 相同的契约: HexBattleSilenceBuff.create_config(duration_ms) 让 ApplyBuffAction
## 在 execute 时 grant 独立 buff Ability 实例; 多次 silence 不 refresh 不合并 duration。
class_name HexBattleSilence


const CONFIG_ID := "skill_silence"
const TIMELINE_ID := "skill_silence"
const SILENCE_DURATION_MS := 2000.0
const COOLDOWN_MS := 6000.0


static var SILENCE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


static var ABILITY := create_config(SILENCE_DURATION_MS)


static func create_config(duration_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("沉默")
		.description("命中目标后使其 %.1f 秒内无法施放主动技能" % (duration_ms / 1000.0))
		.ability_tags(["skill", "active", "melee", "enemy", "control", "silence"])
		.meta(HexBattleSkillMetaKeys.RANGE, 1)
		.meta("silence_duration_ms", duration_ms)
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
					HexBattleSilenceBuff.create_config(duration_ms),
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
