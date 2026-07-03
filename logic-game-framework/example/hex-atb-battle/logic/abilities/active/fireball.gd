## 火球术 - 远程魔法攻击（使用投射物）
##
## 执行流程：
##   1. ABILITY_ACTIVATE_EVENT 触发 → 进入 Timeline
##   2. START tag: 发送动画提示
##   3. CAST tag: 施法动作（仅动画占位，无 Action 注册）
##   4. LAUNCH tag: 发射火球投射物（MOBA 追踪型）
##   5. 投射物飞行中...
##   6. projectileHit 事件触发 → FIREBALL_HIT_TIMELINE → 造成伤害
##
## 【投射物伤害技能 = 四件套手装, 投射物模板】(precise_shot / chain_lightning 同构):
##   ① active_use on_tag(LAUNCH, [LaunchProjectileAction]) 发射弹体
##   ② 独立 *_HIT timeline
##   ③ component_config(ActivateInstanceConfig).trigger(PROJECTILE_HIT_EVENT, filter)
##   ④ 该 component 的 on_timeline_start([HexBattleDamageAction]) —— 真正结算伤害
##   关键: 弹体本身【0 HP 伤害】—— ProjectileSystem 只把 CFG_DAMAGE 拷进 projectileHit
##   事件 payload (表演/replay metadata), 不 apply_damage。漏掉第④步 = 飞出去不掉血,
##   无编译/结构报错。曾评估抽 make_projectile_damage_skill() factory 绑死四件套,
##   但仅 3 技能 / ~12 参数, 显式 builder 对 AI 模仿沙盒更友好, 故【不抽 factory】,
##   靠本注释 + SkillValidator 的 trigger 层伤害可见性 (新-2) 兜底。
class_name HexBattleFireball


const CONFIG_ID := "skill_fireball"
const TIMELINE_ID_CAST := "skill_fireball"
const TIMELINE_ID_HIT := "skill_fireball_hit"
const COOLDOWN_MS := 4000.0
## 火球伤害 (固定值, 不随 atk 缩放; 与法师 atk 80 相等纯属巧合)。
## 单一来源: 同时喂 projectile CFG_DAMAGE (仅 projectileHit 事件 payload, 表演/replay
## metadata, 不实际扣 HP) 与 hit-timeline DamageAction (真正结算伤害的那行)。
const DAMAGE := 80.0


## 发射阶段 Timeline
static var FIREBALL_TIMELINE := TimelineData.new(
	TIMELINE_ID_CAST,
	600.0,
	{
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
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline_id(TIMELINE_ID_CAST)
		.on_timeline_start([StageCueAction.new(
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
				ProjectileActor.CFG_DAMAGE: DAMAGE,
				ProjectileActor.CFG_DAMAGE_TYPE: "magical",
			}),
			HexBattleSkillHelpers.owner_position_resolver(),
			HexBattleSkillHelpers.target_position_resolver(),
		)])
		.build()
	)
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			ProjectileEvents.PROJECTILE_HIT_EVENT,
			HexBattleSkillHelpers.projectile_hit_filter
		))
		.timeline_id(TIMELINE_ID_HIT)
		.on_timeline_start([HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(DAMAGE),
			BattleEvents.DamageType.MAGICAL
		)])
		.build()
	)
	.build()
)
