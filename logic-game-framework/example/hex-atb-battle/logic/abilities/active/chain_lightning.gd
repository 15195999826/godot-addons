## Chain Lightning - 链锁闪电
##
## 设计卡 #9: 首目标魔法伤害 → 跳最近未命中敌人, 每跳 -20%, 最多 3 跳。
##
## 实现模式 (per phase-01-chain-lightning.md):
##   1. ABILITY_ACTIVATE_EVENT → cast timeline 发射首段 lightning projectile
##   2. projectileHit → hit timeline 跑 DamageAction
##   3. DamageAction.on_hit hook 跑 FlowAction.if_(has_next, [LaunchProjectileAction]) 链发下一段
##   4. 下一段 projectile customData 带 ability_instance_id / chain_id / hit_index+1 /
##      damage*0.8 / visited_actor_ids; 触发新一轮 projectileHit
##
## 数值:
##   BASE_DAMAGE 60 MAGICAL; FALLOFF 0.2 (×0.8/跳); MAX_HITS 3
##   伤害序列: 60 / 48 / 38.4
##
## 安全合同:
##   - hit filter 匹配 source + config_id + ability_instance_id, 不会被同 caster
##     的其它 chain 释放污染。
##   - caster 死亡 / ability 过期 / 不在 alive → 不再链发下一段。
##   - visited_actor_ids 防同一敌方重复命中。
class_name HexBattleChainLightning


const CONFIG_ID := "skill_chain_lightning"
const CAST_TIMELINE_ID := "skill_chain_lightning"
const HIT_TIMELINE_ID := "skill_chain_lightning_hit"
const BASE_DAMAGE := 60.0
const MAX_HITS := 3
const FALLOFF := 0.2
const COOLDOWN_MS := 5000.0


static var CHAIN_LIGHTNING_CAST_TIMELINE := TimelineData.new(CAST_TIMELINE_ID, 600.0, {
	TimelineTags.CAST: 200.0,
	TimelineTags.LAUNCH: 400.0,
	TimelineTags.END: 600.0,
})

static var CHAIN_LIGHTNING_HIT_TIMELINE := TimelineData.new(HIT_TIMELINE_ID, 100.0, {
	TimelineTags.END: 100.0,
})


# ============================================================
# Hit filter: source + config_id + ability_instance_id 三重过滤
# ============================================================
static func _projectile_hit_filter(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var ability: Ability = ctx.ability
	if ability == null:
		return false
	if not ProjectileEvents.is_projectile_hit_event(event_dict):
		return false
	if str(event_dict.get("ability_config_id", "")) != CONFIG_ID:
		return false
	if str(event_dict.get("source_actor_id", "")) != ctx.owner_actor_id:
		return false
	var custom: Dictionary = event_dict.get("customData", {}) as Dictionary
	if str(custom.get("ability_instance_id", "")) != ability.id:
		return false
	# caster 死亡 / ability 过期 → 不响应 (避免反死后仍结算)
	if ability.is_expired():
		return false
	var caster := GameWorld.get_actor(ctx.owner_actor_id)
	if not (caster is CharacterActor) or (caster as CharacterActor).is_dead():
		return false
	return true


# ============================================================
# Resolvers
# ============================================================

## 初始 projectile customData (CAST 阶段 hit_index=0 / damage=60)
static func _initial_chain_custom_data_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var chain_id: String = ""
		if ctx.execution_info != null:
			chain_id = ctx.execution_info.id
		if chain_id.is_empty():
			chain_id = IdGenerator.generate("chain_lightning")
		return {
			"ability_instance_id": ctx.ability_ref.id if ctx.ability_ref != null else "",
			"chain_id": chain_id,
			"hit_index": 0,
			"damage": BASE_DAMAGE,
			"visited_actor_ids": [] as Array[String],
		}
	)


## hit timeline 内的 damage resolver: 读取 projectileHit event 的 customData.damage
static func _chain_damage_resolver() -> FloatResolver:
	return Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
		var hit_event := ctx.get_original_event()
		var custom: Dictionary = hit_event.get("customData", {}) as Dictionary
		return float(custom.get("damage", BASE_DAMAGE))
	)


# ============================================================
# Next chain target 计算 (hit on_hit hook 内调用)
# ============================================================

## 计算下一跳数据; 找不到合法目标返回空 dict。
##
## 输入: hit-timeline 内 on_hit callback ctx (event_dict_chain 末 = damage event,
## 原始 = projectileHit event)。
##
## 返回:
##   {} -> 链终止 (达到 MAX_HITS / 无更近未命中敌人 / caster dead / target dead)
##   { start_actor_id, target_actor_id, chain_id, hit_index, damage, visited_actor_ids }
static func _next_chain_data(ctx: ExecutionContext) -> Dictionary:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	if battle == null or ctx.ability_ref == null:
		return {}
	var hit_event := ctx.get_original_event()
	if not ProjectileEvents.is_projectile_hit_event(hit_event):
		return {}
	var chain: Dictionary = hit_event.get("customData", {}) as Dictionary
	if str(chain.get("ability_instance_id", "")) != ctx.ability_ref.id:
		return {}
	var damage_event_dict := ctx.get_current_event()
	var current_id := str(damage_event_dict.get("target_actor_id", ""))
	if current_id.is_empty():
		return {}
	var current_actor := battle.get_actor(current_id)
	if current_actor == null:
		return {}
	var caster := battle.get_character_actor(ctx.ability_ref.owner_actor_id)
	if caster == null or caster.is_dead():
		return {}
	var hit_index := int(chain.get("hit_index", 0))
	if hit_index + 1 >= MAX_HITS:
		return {}
	var visited: Array[String] = []
	for v in (chain.get("visited_actor_ids", []) as Array):
		if v is String:
			visited.append(v as String)
	if not (current_id in visited):
		visited.append(current_id)
	var next_id := _nearest_unvisited_enemy(caster.get_team_id(), current_actor.hex_position, visited, battle)
	if next_id == "":
		return {}
	return {
		"start_actor_id": current_id,
		"target_actor_id": next_id,
		"chain_id": str(chain.get("chain_id", "")),
		"hit_index": hit_index + 1,
		"damage": float(chain.get("damage", BASE_DAMAGE)) * (1.0 - FALLOFF),
		"visited_actor_ids": visited,
	}


static func _nearest_unvisited_enemy(team: int, from_pos: HexCoord,
		visited: Array[String], battle: HexWorldGameplayInstance) -> String:
	var best := ""
	var best_d := 1 << 30
	for actor in battle.get_alive_actors():
		if actor.get_team_id() == team or actor.get_id() in visited:
			continue
		var d := from_pos.distance_to(actor.hex_position)
		if d < best_d:
			best_d = d
			best = actor.get_id()
	return best


## predicate for FlowAction.if_
static func _has_next_chain_target(ctx: ExecutionContext) -> bool:
	return not _next_chain_data(ctx).is_empty()


# ============================================================
# Next chain projectile params (FlowAction.if_ then branch)
# ============================================================

class _NextChainTargetSelector extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		var data := HexBattleChainLightning._next_chain_data(ctx)
		var tid := str(data.get("target_actor_id", ""))
		var result: Array[String] = []
		if tid != "":
			result.append(tid)
		return result


static func _next_chain_projectile_config_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var data := _next_chain_data(ctx)
		var damage_value := float(data.get("damage", BASE_DAMAGE * (1.0 - FALLOFF)))
		return {
			ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
			ProjectileActor.CFG_VISUAL_TYPE: "lightning",
			ProjectileActor.CFG_SPEED: 200.0,
			ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
			ProjectileActor.CFG_HIT_DISTANCE: 30.0,
			ProjectileActor.CFG_DAMAGE: damage_value,
			ProjectileActor.CFG_DAMAGE_TYPE: "magical",
		}
	)


static func _actor_world_pos(actor_id: String, battle: HexWorldGameplayInstance) -> Vector3:
	if battle == null:
		return Vector3.ZERO
	var actor := battle.get_actor(actor_id)
	if actor == null or not actor.hex_position.is_valid():
		return Vector3.ZERO
	return Vector3(actor.hex_position.q, actor.hex_position.r, 0)


static func _next_chain_start_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var data := _next_chain_data(ctx)
		return _actor_world_pos(str(data.get("start_actor_id", "")), ctx.game_state_provider)
	)


static func _next_chain_target_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var data := _next_chain_data(ctx)
		return _actor_world_pos(str(data.get("target_actor_id", "")), ctx.game_state_provider)
	)


static func _next_chain_custom_data_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var data := _next_chain_data(ctx)
		var visited_arr: Array = (data.get("visited_actor_ids", []) as Array).duplicate()
		return {
			"ability_instance_id": ctx.ability_ref.id if ctx.ability_ref != null else "",
			"chain_id": str(data.get("chain_id", "")),
			"hit_index": int(data.get("hit_index", 0)),
			"damage": float(data.get("damage", BASE_DAMAGE)),
			"visited_actor_ids": visited_arr,
		}
	)


# ============================================================
# Ability definition
# ============================================================

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("连锁闪电")
	.description("对目标造成魔法伤害,弹跳至最近的其他敌人,每跳衰减 20%,最多 3 跳")
	.ability_tags(["skill", "active", "ranged", "magic", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 5)
	.active_use(ActiveUseConfig.builder()
		.timeline_id(CAST_TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_fireball")
		)])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "lightning",
				ProjectileActor.CFG_SPEED: 200.0,
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,
				ProjectileActor.CFG_DAMAGE: BASE_DAMAGE,
				ProjectileActor.CFG_DAMAGE_TYPE: "magical",
			}),
			HexBattleSkillHelpers.owner_position_resolver(),
			HexBattleSkillHelpers.target_position_resolver(),
			null,
			_initial_chain_custom_data_resolver()
		)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			ProjectileEvents.PROJECTILE_HIT_EVENT,
			_projectile_hit_filter
		))
		.timeline_id(HIT_TIMELINE_ID)
		.on_timeline_start([_build_hit_damage_action()])
		.build())
	.build())


# DamageAction.on_hit(FlowAction.if_(_has_next_chain_target, [next-chain LaunchProjectileAction]))
static func _build_hit_damage_action() -> HexBattleDamageAction:
	var damage_action := HexBattleDamageAction.new(
		HexBattleTargetSelectors.current_target(),
		_chain_damage_resolver(),
		BattleEvents.DamageType.MAGICAL
	)
	var then_actions: Array[Action.BaseAction] = [
		LaunchProjectileAction.new(
			_NextChainTargetSelector.new(),
			_next_chain_projectile_config_resolver(),
			_next_chain_start_position_resolver(),
			_next_chain_target_position_resolver(),
			null,
			_next_chain_custom_data_resolver()
		)
	]
	damage_action.on_hit(FlowAction.if_(_has_next_chain_target, then_actions))
	return damage_action
