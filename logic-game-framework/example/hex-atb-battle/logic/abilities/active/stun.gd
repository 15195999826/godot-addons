## Stun #A1 - 眩晕主动技能 (hard control)
##
## 命中目标后 grant HexBattleStunBuff (duration 默认 2000ms), 短 cast (500ms timeline, HIT@300ms)。
##
## 不为不同 duration 的 stun 复制多个 buff class — duration 由 HexBattleStunBuff.create_config(ms)
## 在每个技能配置里传入, ApplyBuffAction 在 execute 时 grant 出独立 buff Ability 实例。
##
## 同一 actor 多次被 Stun → 多个独立 buff 实例并存, 各自 lifetime, 各自贡献 component-owned
## cant_act tag (V1 设计: 不 refresh / 不 merge duration, 见 HexBattleStunBuff §)。
class_name HexBattleStun


const CONFIG_ID := "skill_stun"
const TIMELINE_ID := "skill_stun"
const STUN_DURATION_MS := 2000.0
const COOLDOWN_MS := 6000.0


static var STUN_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


## 默认 STUN_DURATION_MS=2000ms。需要其它 duration 用 create_config(ms)。
static var ABILITY := create_config(STUN_DURATION_MS)


static func create_config(duration_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("眩晕")
		.description("命中目标后使其 %.1f 秒内无法行动" % (duration_ms / 1000.0))
		.ability_tags(["skill", "active", "melee", "enemy", "control", "stun"])
		.meta(HexBattleSkillMetaKeys.RANGE, 1)
		.meta("stun_duration_ms", duration_ms)
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
					HexBattleStunBuff.create_config(duration_ms),
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
