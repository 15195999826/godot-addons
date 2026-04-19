## Poison - 施毒近战技能
##
## 近战范围（RANGE=1），对 current_target 施加 HexBattlePoisonBuff（默认 3 层）。
## 本技能不自己造成直接伤害 —— 全部伤害由 DOT buff 每 2s tick 产生。
##
## 契约示范（对比 Strike）：
##   - Strike 类 Action：on_tag(HIT, [HexBattleDamageAction])，直接结算伤害
##   - Poison 类 Action：on_tag(HIT, [HexBattleApplyBuffAction])，只 grant buff，后续由 buff 自治
##   - Buff 自身层数语义来自 Ability 一级属性 stacks，其驱动来自 ActivateInstanceConfig + GRANTED_SELF
##
## Timeline：500ms 短 cast，HIT @ 300ms（对齐 Strike，动画节奏一致）
class_name HexBattlePoison


const CONFIG_ID := "skill_poison"
const TIMELINE_ID := "skill_poison"
const COOLDOWN_MS := 3000.0


static var POISON_TIMELINE := TimelineData.new(
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
	.display_name("施毒")
	.description("对目标施加中毒 debuff（3 层，每 2 秒造成 = 当前层数的 PURE 伤害，层数递减）")
	.ability_tags(["skill", "active", "melee", "enemy", "debuff"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash")
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleApplyBuffAction.new(
				HexBattleTargetSelectors.current_target(),
				HexBattlePoisonBuff.POISON_BUFF
			),
		])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
