## 精准射击 - 远程物理攻击（使用投射物）
##
## 执行流程：
##   1. ABILITY_ACTIVATE_EVENT 触发 → 进入 Timeline
##   2. START tag: 发送动画提示
##   3. LAUNCH tag: 发射箭矢投射物（MOBA 追踪型）
##   4. 投射物飞行中...
##   5. projectileHit 事件触发 → PRECISE_SHOT_HIT_TIMELINE → 造成伤害
class_name HexBattlePreciseShot


const CONFIG_ID := "skill_precise_shot"
const TIMELINE_ID_CAST := "skill_precise_shot"
const TIMELINE_ID_HIT := "skill_precise_shot_hit"
const COOLDOWN_MS := 2500.0


## 发射阶段 Timeline：发射后结束，投射物继续飞行
static var PRECISE_SHOT_TIMELINE := TimelineData.new(
	TIMELINE_ID_CAST,
	500.0,
	{
		TimelineTags.LAUNCH: 300.0,
		TimelineTags.END: 500.0,
	}
)


## 命中响应 Timeline（投射物命中触发）
static var PRECISE_SHOT_HIT_TIMELINE := TimelineData.new(
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
	.display_name("精准射击")
	.description("远程攻击，发射箭矢精准命中敌人")
	.ability_tags(["skill", "active", "ranged", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 4)
	# 主动使用组件：发射投射物
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID_CAST)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("ranged_arrow")
		)])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "arrow",
				ProjectileActor.CFG_SPEED: 250.0,
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,
				ProjectileActor.CFG_DAMAGE: 45.0,
				ProjectileActor.CFG_DAMAGE_TYPE: "physical",
			}),
			HexBattleSkillHelpers.owner_position_resolver(),
			HexBattleSkillHelpers.target_position_resolver(),
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	# 投射物命中响应组件：造成伤害
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			ProjectileEvents.PROJECTILE_HIT_EVENT,
			HexBattleSkillHelpers.projectile_hit_filter
		))
		.timeline_id(TIMELINE_ID_HIT)
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(45.0),
			BattleEvents.DamageType.PHYSICAL
		)])
		.build()
	)
	.build()
)
