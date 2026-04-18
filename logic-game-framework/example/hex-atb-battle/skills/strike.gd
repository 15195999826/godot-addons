## Strike - 近战基础攻击
##
## （原名 SLASH）：相邻格物理伤害，暴击时额外 10 点固定伤害
##
## 契约示范：damage 用 Resolver 读 caster.atk，随属性缩放。
##   - 这让 Buff/Debuff/装备对 atk 的修改自动影响 Strike 伤害
##   - Hook 类技能（Ward 拦伤、Expose 增伤）在 PreDamage 阶段作用于已解析的数值
##   - 未来其他物理技能（CrushingBlow 等）可复制此 resolver 模板
class_name HexBattleStrike


const CONFIG_ID := "skill_strike"
const TIMELINE_ID := "skill_strike"
const COOLDOWN_MS := 2000.0
const CRITICAL_BONUS := 10.0


static var STRIKE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.START: 0.0,
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


## caster.atk 作为基础伤害；resolve 在 DamageAction.execute() 时按 ctx 读取
static var _CASTER_ATK_DAMAGE: FloatResolver = Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
	var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if owner_id == "":
		return 0.0
	var actor := GameWorld.get_actor(owner_id)
	if actor == null or not (actor is CharacterActor):
		return 0.0
	return (actor as CharacterActor).attribute_set.atk
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
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL
			).on_critical(
				HexBattleDamageAction.new(
					HexBattleTargetSelectors.current_target(),
					Resolvers.float_val(CRITICAL_BONUS),
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
