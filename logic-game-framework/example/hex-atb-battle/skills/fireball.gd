## 火球术 - 远程魔法攻击（使用投射物）
##
## 执行流程：
##   1. ABILITY_ACTIVATE_EVENT 触发 → 进入 Timeline
##   2. START tag: 发送动画提示
##   3. CAST tag: 施法动作（仅动画占位，无 Action 注册）
##   4. LAUNCH tag: 发射火球投射物（MOBA 追踪型）
##   5. 投射物飞行中...
##   6. projectileHit 事件触发 → FIREBALL_HIT_TIMELINE → 造成伤害
class_name HexBattleFireball


const CONFIG_ID := "skill_fireball"
const TIMELINE_ID_CAST := "skill_fireball"
const TIMELINE_ID_HIT := "skill_fireball_hit"
const COOLDOWN_MS := 4000.0


## 发射阶段 Timeline
static var FIREBALL_TIMELINE := TimelineData.new(
	TIMELINE_ID_CAST,
	600.0,
	{
		TimelineTags.START: 0.0,
		TimelineTags.CAST: 200.0,    # 施法动作（占位）
		TimelineTags.LAUNCH: 400.0,
		TimelineTags.END: 600.0,
	}
)


## 命中响应 Timeline
static var FIREBALL_HIT_TIMELINE := TimelineData.new(
	TIMELINE_ID_HIT,
	100.0,
	{
		TimelineTags.HIT: 0.0,
		TimelineTags.END: 100.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("火球术")
	.description("远程魔法攻击，发射追踪火球")
	.ability_tags(["skill", "active", "ranged", "magic", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 5)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID_CAST)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_fireball")
		)])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "fireball",
				ProjectileActor.CFG_SPEED: 200.0,
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,
				ProjectileActor.CFG_DAMAGE: 80.0,
				ProjectileActor.CFG_DAMAGE_TYPE: "magical",
			}),
			HexBattleSkillHelpers.owner_position_resolver(),
			HexBattleSkillHelpers.target_position_resolver(),
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			ProjectileEvents.PROJECTILE_HIT_EVENT,
			HexBattleSkillHelpers.projectile_hit_filter
		))
		.timeline_id(TIMELINE_ID_HIT)
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(80.0),
			BattleEvents.DamageType.MAGICAL
		)])
		.build()
	)
	.build()
)
