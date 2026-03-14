## Ability 定义
##
## 使用框架 Ability 系统实现的技能和行动配置。
## 包括移动、攻击技能、治疗技能等。
class_name HexBattleSkillAbilities


# ========== 技能冷却配置（毫秒） ==========

const SKILL_COOLDOWNS := {
	"slash": 2000.0,
	"precise_shot": 2500.0,
	"fireball": 4000.0,
	"crushing_blow": 5000.0,
	"swift_strike": 3000.0,
	"holy_heal": 4000.0,
}


# ========== 辅助函数 ==========

## 从事件中获取目标坐标的解析器
static func _get_target_coord_from_event() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var evt := ctx.get_current_event()
		return evt.get("target_coord", {}) as Dictionary
	)


## 触发器过滤函数：匹配当前 Ability 的激活事件
static func _ability_activate_filter(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var ability: Ability = ctx.ability
	if ability == null:
		return false
	# 使用强类型事件
	var event := GameEvent.AbilityActivate.from_dict(event_dict)
	return event.ability_instance_id == ability.id


## 触发器过滤函数：匹配投射物命中事件
## 同时匹配 source_actor_id（发射者）和 ability_config_id（技能来源），
## 确保只有本技能发出的投射物才触发命中响应。
static func _projectile_hit_filter(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var ability: Ability = ctx.ability
	if ability == null:
		Log.warning("ProjectileHitFilter", "ctx.ability is null, skipping filter")
		return false
	var event := GameEvent.ProjectileHit.from_dict(event_dict)
	return event.source_actor_id == ctx.owner_actor_id \
		and event.ability_config_id == ability.config_id


# ========== 投射物位置解析器 ==========

## 从 Ability Owner 获取位置（hex 坐标转 Vector3）
static func _get_owner_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if owner_id == "":
			return Vector3.ZERO
		var actor := GameWorld.get_actor(owner_id)
		if actor == null or not (actor is CharacterActor):
			return Vector3.ZERO
		var char_actor := actor as CharacterActor
		if not char_actor.hex_position.is_valid():
			return Vector3.ZERO
		# hex 坐标转 Vector3（使用 q, r 作为 x, y）
		return Vector3(char_actor.hex_position.q, char_actor.hex_position.r, 0)
	)


## 从当前事件目标获取位置（hex 坐标转 Vector3）
static func _get_target_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var event := ctx.get_current_event()
		var target_actor_id: String = event.get("target_actor_id", "")
		if target_actor_id == "":
			return Vector3.ZERO
		var actor := GameWorld.get_actor(target_actor_id)
		if actor == null or not (actor is CharacterActor):
			return Vector3.ZERO
		var char_actor := actor as CharacterActor
		if not char_actor.hex_position.is_valid():
			return Vector3.ZERO
		return Vector3(char_actor.hex_position.q, char_actor.hex_position.r, 0)
	)


# ========== 移动 Ability ==========

## 移动 - 移动到相邻格子（两阶段）
static var MOVE_ABILITY := (
	AbilityConfig.builder()
	.config_id("action_move")
	.display_name("移动")
	.description("移动到相邻格子")
	.ability_tags(["action", "move"])
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(GameEvent.ABILITY_ACTIVATE_EVENT, _ability_activate_filter))
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.MOVE)
		.on_tag(TimelineTags.START, [HexBattleStartMoveAction.new(
			HexBattleTargetSelectors.ability_owner(),
			_get_target_coord_from_event()
		)])
		.on_tag(TimelineTags.EXECUTE, [HexBattleApplyMoveAction.new(
			HexBattleTargetSelectors.ability_owner(),
			_get_target_coord_from_event()
		)])
		.build()
	)
	.build()
)


# ========== 技能 Ability ==========

## 横扫斩 - 近战物理攻击
## 示例：使用 on_critical 回调，暴击时额外造成 10 点伤害
static var SLASH_ABILITY := (
	AbilityConfig.builder()
	.config_id("skill_slash")
	.display_name("横扫斩")
	.description("近战攻击，对敌人造成物理伤害（暴击时额外伤害）")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.SLASH)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash")
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				50.0,
				BattleEvents.DamageType.PHYSICAL
			).on_critical(
				HexBattleDamageAction.new(
					HexBattleTargetSelectors.current_target(),
					10.0,
					BattleEvents.DamageType.PHYSICAL
				)
			),
		])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(SKILL_COOLDOWNS["slash"]))
		.build()
	)
	.build()
)


## 精准射击 - 远程物理攻击（使用投射物）
##
## 执行流程：
## 1. ABILITY_ACTIVATE_EVENT 触发 → 进入 Timeline
## 2. START tag: 发送动画提示
## 3. LAUNCH tag: 发射箭矢投射物（MOBA 追踪型）
## 4. 投射物飞行中...
## 5. projectileHit 事件触发 → 造成伤害
static var PRECISE_SHOT_ABILITY := (
	AbilityConfig.builder()
	.config_id("skill_precise_shot")
	.display_name("精准射击")
	.description("远程攻击，发射箭矢精准命中敌人")
	.ability_tags(["skill", "active", "ranged", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 4)
	# 主动使用组件：发射投射物
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.PRECISE_SHOT)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("ranged_arrow")
		)])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			# 投射物配置
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "arrow",  # 视觉类型：箭矢
				ProjectileActor.CFG_SPEED: 250.0,  # 箭矢比火球快
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,
				ProjectileActor.CFG_DAMAGE: 45.0,
				ProjectileActor.CFG_DAMAGE_TYPE: "physical",
			}),
			_get_owner_position_resolver(),
			_get_target_position_resolver(),
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(SKILL_COOLDOWNS["precise_shot"]))
		.build()
	)
	# 投射物命中响应组件：造成伤害
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(ProjectileEvents.PROJECTILE_HIT_EVENT, _projectile_hit_filter))
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.PRECISE_SHOT_HIT)
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			45.0,
			BattleEvents.DamageType.PHYSICAL
		)])
		.build()
	)
	.build()
)


## 火球术 - 远程魔法攻击（使用投射物）
## 
## 执行流程：
## 1. ABILITY_ACTIVATE_EVENT 触发 → 进入 Timeline
## 2. START tag: 发送动画提示
## 3. LAUNCH tag: 发射火球投射物（MOBA 追踪型）
## 4. 投射物飞行中...
## 5. projectileHit 事件触发 → 造成伤害
static var FIREBALL_ABILITY := (
	AbilityConfig.builder()
	.config_id("skill_fireball")
	.display_name("火球术")
	.description("远程魔法攻击，发射追踪火球")
	.ability_tags(["skill", "active", "ranged", "magic", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 5)
	# 主动使用组件：发射投射物
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.FIREBALL)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_fireball")
		)])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			# 投射物配置
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "fireball",  # 视觉类型：火球
				ProjectileActor.CFG_SPEED: 200.0,  # 单位/秒
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,  # 最大飞行时间 5 秒
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,  # MOBA 类型的命中距离
				ProjectileActor.CFG_DAMAGE: 80.0,
				ProjectileActor.CFG_DAMAGE_TYPE: "magical",
			}),
			_get_owner_position_resolver(),  # 起始位置
			_get_target_position_resolver(),  # 目标位置
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(SKILL_COOLDOWNS["fireball"]))
		.build()
	)
	# 投射物命中响应组件：造成伤害
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(ProjectileEvents.PROJECTILE_HIT_EVENT, _projectile_hit_filter))
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.FIREBALL_HIT)
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			80.0,
			BattleEvents.DamageType.MAGICAL
		)])
		.build()
	)
	.build()
)


## 毁灭重击 - 近战重击
static var CRUSHING_BLOW_ABILITY := (
	AbilityConfig.builder()
	.config_id("skill_crushing_blow")
	.display_name("毁灭重击")
	.description("近战重击，造成毁灭性伤害")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.CRUSHING_BLOW)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_heavy")
		)])
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			90.0,
			BattleEvents.DamageType.PHYSICAL
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(SKILL_COOLDOWNS["crushing_blow"]))
		.build()
	)
	.build()
)


## 疾风连刺 - 快速多段攻击
static var SWIFT_STRIKE_ABILITY := (
	AbilityConfig.builder()
	.config_id("skill_swift_strike")
	.display_name("疾风连刺")
	.description("快速近战攻击，三连击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.SWIFT_STRIKE)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_combo"),
			Resolvers.dict_val({ "hits": 3 })
		)])
		.on_tag(TimelineTags.HIT1, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			10.0,
			BattleEvents.DamageType.PHYSICAL
		)])
		.on_tag(TimelineTags.HIT2, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			10.0,
			BattleEvents.DamageType.PHYSICAL
		)])
		.on_tag(TimelineTags.HIT3, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			10.0,
			BattleEvents.DamageType.PHYSICAL
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(SKILL_COOLDOWNS["swift_strike"]))
		.build()
	)
	.build()
)


## 圣光治愈 - 治疗技能
static var HOLY_HEAL_ABILITY := (
	AbilityConfig.builder()
	.config_id("skill_holy_heal")
	.display_name("圣光治愈")
	.description("治疗友方单位，恢复生命值")
	.ability_tags(["skill", "active", "heal", "ally"])
	.meta(HexBattleSkillMetaKeys.RANGE, 3)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(HexBattleSkillTimelines.TIMELINE_ID.HOLY_HEAL)
		.on_tag(TimelineTags.START, [StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_heal")
		)])
		.on_tag(TimelineTags.HEAL, [HexBattleHealAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(40.0)
		)])
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(SKILL_COOLDOWNS["holy_heal"]))
		.build()
	)
	.build()
)


# ========== 技能映射 ==========

## 根据技能类型获取 Ability 配置
static func get_skill_ability(skill_type: HexBattleSkillConfig.SkillType) -> AbilityConfig:
	match skill_type:
		HexBattleSkillConfig.SkillType.SLASH:
			return SLASH_ABILITY
		HexBattleSkillConfig.SkillType.PRECISE_SHOT:
			return PRECISE_SHOT_ABILITY
		HexBattleSkillConfig.SkillType.FIREBALL:
			return FIREBALL_ABILITY
		HexBattleSkillConfig.SkillType.CRUSHING_BLOW:
			return CRUSHING_BLOW_ABILITY
		HexBattleSkillConfig.SkillType.SWIFT_STRIKE:
			return SWIFT_STRIKE_ABILITY
		HexBattleSkillConfig.SkillType.HOLY_HEAL:
			return HOLY_HEAL_ABILITY
		_:
			return SLASH_ABILITY
