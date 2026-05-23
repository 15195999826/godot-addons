## Lifesteal #F - 血怒打击 (主动近战 + 实际生命伤害百分比吸血)
##
## V1 行为 (per advanced-skills-next-batch.md):
## - 主动近战技能 (melee, range=1)
## - 命中后按 DamageEvent.actual_life_damage * ratio 治疗 caster
## - shield 全吸收 (actual=0) → 不吸血
## - target 低 HP overkill → 仅按实际扣掉的生命值吸血
## - reflected damage / self damage 不触发 lifesteal (DamageAction.on_hit callback 默认不
##   被 reflected damage 复触发 — 因为 reflect 走 ReflectDamageAction 不带 on_hit chain)
##
## 实现: 复用 HexBattleDamageAction.on_hit callback, 内嵌 _LifestealHealAction (SkillLocalAction)
## 读 callback_ctx.get_current_event() → DamageEvent dict → actual_life_damage * ratio → HealAction caster。
class_name HexBattleLifesteal


const CONFIG_ID := "skill_lifesteal"
const TIMELINE_ID := "skill_lifesteal"
const COOLDOWN_MS := 6000.0
const LIFESTEAL_RATIO := 0.5


static var LIFESTEAL_TIMELINE := TimelineData.new(
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


class _LifestealHealAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleLifesteal.CONFIG_ID)
		type = "lifesteal_heal"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		# callback_ctx event chain 末尾是 DamageEvent dict
		var damage_event := ctx.get_current_event()
		if damage_event.is_empty():
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_damage_event" })
		var actual := damage_event.get("actual_life_damage", 0.0) as float
		if actual <= 0.0:
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_actual_damage" })

		var heal_amount := actual * HexBattleLifesteal.LIFESTEAL_RATIO
		# 用 HealAction 走标准 heal pipeline (clamp / events / overheal callback)
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_game_state" })
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if caster_id.is_empty():
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_caster" })

		# Embedded HealAction (Fixed target = caster, FloatResolver = heal_amount)
		var heal_action := HexBattleHealAction.new(
			HexBattleTargetSelectors.fixed([caster_id]),
			Resolvers.float_val(heal_amount),
		)
		var result := heal_action.execute(ctx)
		return ActionResult.create_success_result(
			result.event_dicts if result != null else [],
			{ "lifesteal_heal": heal_amount, "actual_life_damage": actual }
		)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("血怒打击")
	.description("近战物理攻击, 按实际生命伤害的 %d%% 治疗自己" % int(LIFESTEAL_RATIO * 100))
	.ability_tags(["skill", "active", "melee", "enemy", "lifesteal"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash"),
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL,
			).on_hit(_LifestealHealAction.new())
		])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
