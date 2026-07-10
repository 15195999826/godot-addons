## Poison - 施毒近战技能【buff_applier 家族的显式教学范本】
##
## 近战范围（RANGE=1），对 current_target 施加 HexBattlePoisonBuff（默认 3 层）。
## 本技能不自己造成直接伤害 —— 全部伤害由 DOT buff 每 2s tick 产生。
##
## 契约示范（对比 Strike）：
##   - Strike 类 Action：on_tag(HIT, [HexBattleDamageAction])，直接结算伤害
##   - Poison 类 Action：on_tag(HIT, [HexBattleApplyBuffAction])，只 grant buff，后续由 buff 自治
##   - Buff 自身层数语义来自 Ability 一级属性 stacks，其驱动来自 ActivateInstanceConfig + GRANTED_SELF
##
## 【家族范本地位】stun/silence/break/expose/ward/双盾/surge 8 个同骨架技能已收进
## HexBattleSkillPresets.buff_applier —— 本文件保持全显式 builder 链，就是那个 preset
## 展开后的样子。想理解 preset 内部结构 / 做带独有机制的变体时，从这里抄起。
class_name HexBattlePoison


const CONFIG_ID := "skill_poison"
const COOLDOWN_MS := 3000.0


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("施毒")
	.description("对目标施加中毒 debuff（3 层，每 2 秒造成 = 当前层数的 PURE 伤害，层数递减）")
	.ability_tags(["skill", "active", "melee", "enemy", "debuff"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_ACTOR)
	.active_use(
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(HexBattleStdTimelines.MELEE_500)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val(HexBattleCues.MELEE_SLASH)
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleApplyBuffAction.new(
				HexBattleTargetSelectors.current_target(),
				HexBattlePoisonBuff.POISON_BUFF
			),
		])
		.build()
	)
	.build()
)
