## Surge - 自施"涌动"主动技能
##
## RANGE 0:caster 给自己挂 HexBattleSurgeBuff(独立实例)。Buff 立即生效,
## 之后每 2s tick 一次,共 3 次。
##
## 设计目的:复现并验证 frontend BuffVisualizer 在 GRANTED_SELF + on_timeline_start
## 场景下的 stacks 显示序列(grant 与首 tick 同帧)。
class_name HexBattleSurge


const CONFIG_ID := "skill_surge"
const TIMELINE_ID := "skill_surge"
const COOLDOWN_MS := 5000.0


static var SURGE_TIMELINE := TimelineData.new(
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
	.display_name("涌动")
	.description("自施涌动 buff(3 stacks,每 2s 减 1,立即生效)")
	.ability_tags(["skill", "active", "self", "surge"])
	.meta(HexBattleSkillMetaKeys.RANGE, 0)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.HIT, [
			HexBattleApplyBuffAction.new(
				HexBattleTargetSelectors.ability_owner(),
				HexBattleSurgeBuff.SURGE_BUFF
			),
		])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
