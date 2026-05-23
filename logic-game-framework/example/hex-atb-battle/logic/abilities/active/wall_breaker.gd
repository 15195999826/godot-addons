## WallBreaker - 破墙近战 (验证 EnvironmentActor opt-in 通路)
##
## 用 metadata `allowedTargetKinds = ["Character", "Environment"]` 显式声明
## 该技能可对 character 和 environment 同时打。其余结构复刻 Strike (近战 +
## caster.atk 缩放), 仅是 EnvironmentActor 交互的最小验证技能。
class_name HexBattleWallBreaker


const CONFIG_ID := "skill_wall_breaker"
const TIMELINE_ID := "skill_wall_breaker"
const COOLDOWN_MS := 3000.0


static var WALL_BREAKER_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


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
	.display_name("破墙")
	.description("近战攻击, 可对敌方角色或环境物造成物理伤害")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.meta(HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS, ["Character", "Environment"])
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL
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
