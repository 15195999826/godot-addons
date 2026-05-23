## PhysicalShield - 自施物理护盾主动技能
##
## RANGE 0：caster 给自己挂一个 HexBattleShieldBuffs.PHYSICAL_SHIELD_BUFF（独立实例），
## 只吸 physical 伤害（priority 10，高于 universal Ward 的 0，按 resolver 规则先于 Ward 消耗）。
## V1 不支持友军施放（与 Ward 一致，需要 target ally 区分时再加）。
##
## Timeline：500ms 短 cast，HIT @ 300ms（节奏对齐 Ward / Strike / Poison）。
class_name HexBattlePhysicalShield


const CONFIG_ID := "skill_physical_shield"
const TIMELINE_ID := "skill_physical_shield"
const COOLDOWN_MS := 4000.0


static var PHYSICAL_SHIELD_TIMELINE := TimelineData.new(
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
	.display_name("物理护盾术")
	.description("为自己生成一个吸收 30 点物理伤害的护盾，持续 6 秒")
	.ability_tags(["skill", "active", "self", "shield"])
	.meta(HexBattleSkillMetaKeys.RANGE, 0)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.HIT, [
			HexBattleApplyShieldAction.new(
				HexBattleTargetSelectors.ability_owner(),
				HexBattleShieldBuffs.PHYSICAL_SHIELD_BUFF
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
