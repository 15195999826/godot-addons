## TotemAttack - 图腾自动攻击 passive
##
## V1 用例: Phase C0 Summon Totem 召唤后图腾自带的 passive。
## GRANTED_SELF trigger 启动 periodic timeline, 每 3s 选最近敌方 CharacterActor 造伤。
##
## 行为:
## - 每 tick 选当前 battle 中 (alive CharacterActor && team_id != owner.team_id) 中最近的目标
## - 不区分 ranged / melee, 不考虑 LOS, 不需要相邻
## - damage = owner.atk (PHYSICAL)
## - 若无敌人 → tick 跳过, periodic timeline 继续 (next tick 再试)
class_name HexBattleTotemAttack


const CONFIG_ID := "passive_totem_attack"
const TICK_TIMELINE_ID := "passive_totem_attack_tick"
const TICK_INTERVAL_MS := 3000.0
const STAGE_CUE_ID := "totem_attack"


static var TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)


class _TotemAttackAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleTotemAttack.CONFIG_ID)
		type = "totem_attack_tick"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], {})
		var self_ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if self_ability == null or self_ability.is_expired():
			return ActionResult.create_success_result([], {})
		var owner_id := self_ability.owner_actor_id
		var owner := battle.get_actor(owner_id) as CharacterActor
		if owner == null or owner.is_dead():
			return ActionResult.create_success_result([], {})
		var owner_team := owner.get_team_id()

		# 选最近敌方 CharacterActor
		var best_target: CharacterActor = null
		var best_dist := 9999
		for actor in battle.get_alive_actors():
			if not (actor is CharacterActor):
				continue
			var c := actor as CharacterActor
			if c.get_team_id() == owner_team:
				continue
			if c.get_id() == owner_id:
				continue
			var dist := owner.hex_position.distance_to(c.hex_position)
			if dist < best_dist:
				best_dist = dist
				best_target = c

		if best_target == null:
			return ActionResult.create_success_result([], { "totem_attack_skipped": "no_enemy" })

		var collected: Array[Dictionary] = []
		var target_ids: Array[String] = [best_target.get_id()]
		var stage_cue := GameEvent.StageCue.create(
			owner_id,
			target_ids,
			HexBattleTotemAttack.STAGE_CUE_ID,
		)
		if ctx.event_collector != null:
			collected.append(ctx.event_collector.push(stage_cue.to_dict()))
		else:
			collected.append(stage_cue.to_dict())

		# 造伤 (PHYSICAL atk damage), source = totem owner (= totem 本身)
		var damage_value := owner.attribute_set.atk
		var event := BattleEvents.DamageEvent.create(
			best_target.get_id(),
			damage_value,
			BattleEvents.DamageType.PHYSICAL,
			owner_id,
			false,
			false,  # is_reflected
		)
		var damage_result := HexBattleDamageUtils.apply_damage(
			event, battle.get_alive_actor_ids(), ctx, battle,
		)
		HexBattleDamageUtils.broadcast_post_damage(
			damage_result.damage_event_dict, battle.get_alive_actor_ids(), battle,
		)
		collected.append_array(damage_result.all_events)
		return ActionResult.create_success_result(collected, {
			"totem_attack_target": best_target.get_id(),
			"totem_attack_damage": damage_value,
		})


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("图腾自动攻击")
	.description("每 3 秒选最近敌方 CharacterActor 造成 atk 伤害")
	.ability_tags(["passive", "totem", "auto_attack"])
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_end([_TotemAttackAction.new()])
		.build()
	)
	.build()
)
