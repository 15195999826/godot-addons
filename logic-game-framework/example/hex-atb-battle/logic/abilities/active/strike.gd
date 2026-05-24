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


## Phase A · 普攻命中后 emit AttackLandedEvent.
## 挂在主 damage action 的 on_hit chain, 不挂在 on_critical (crit bonus 不算独立"普攻命中").
## callback ctx 已携带主 damage event dict; cancelled / dead-target 由 DamageAction 上游 skip,
## 这里不会被复触发。事件 push 到 event_collector + broadcast 给存活 actor 以触发被动.
class _EmitAttackLandedAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleStrike.CONFIG_ID)
		type = "emit_attack_landed"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var damage_event_dict := ctx.get_current_event()
		if damage_event_dict.is_empty():
			return ActionResult.create_success_result([], { "attack_landed_skipped": "no_damage_event" })
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], { "attack_landed_skipped": "no_game_state" })
		var attacker_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if attacker_id.is_empty():
			return ActionResult.create_success_result([], { "attack_landed_skipped": "no_attacker" })

		var target_id := str(damage_event_dict.get("target_actor_id", ""))
		var actual_life_damage := damage_event_dict.get("actual_life_damage", 0.0) as float
		var source_ability_id := ctx.ability_ref.id if ctx.ability_ref != null else ""
		var source_ability_config_id := ctx.ability_ref.config_id if ctx.ability_ref != null else ""

		var event := BattleEvents.AttackLandedEvent.create(
			attacker_id,
			target_id,
			source_ability_id,
			source_ability_config_id,
			actual_life_damage,
			damage_event_dict,
		)
		var event_dict: Dictionary = ctx.event_collector.push(event.to_dict())

		var alive_actor_ids := battle.get_alive_actor_ids()
		if alive_actor_ids.size() > 0:
			GameWorld.event_processor.process_post_event(event_dict, alive_actor_ids, battle)

		return ActionResult.create_success_result(
			[event_dict],
			{ "attack_landed_actual_life_damage": actual_life_damage }
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
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash")
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL
			).on_hit(_EmitAttackLandedAction.new()).on_critical(
				HexBattleDamageAction.new(
					HexBattleTargetSelectors.current_target(),
					Resolvers.float_val(CRITICAL_BONUS),
					BattleEvents.DamageType.PHYSICAL
				)
			),
		])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
