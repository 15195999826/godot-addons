## FireTilePulse - 火焰地形周期伤害 passive
##
## V1 用例: Phase C Fire Tile 火焰地形自带 passive。GRANTED_SELF periodic timeline,
## 每 1s 对站在自己 hex_position 上的 alive CharacterActor 造 pure damage。
##
## 伤害归因 (per Goal):
## - DamageEvent.source_actor_id = fire_tile_actor.id (fire tile 自己是攻击者)
## - 走完整 damage pipeline (pre/shield/damage/post-damage), Thorn 等反应可生效
##   反伤到 fire tile 自己, 打死按普通 actor 死亡处理 (HexBattleDamageUtils.apply_damage 走完整流程)
class_name HexBattleFireTilePulse


const CONFIG_ID := "passive_fire_tile_pulse"
const TICK_TIMELINE_ID := "passive_fire_tile_pulse_tick"
const DEFAULT_PULSE_INTERVAL_MS := 1000.0
const DEFAULT_PULSE_DAMAGE := 20.0


static var PULSE_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, DEFAULT_PULSE_INTERVAL_MS)


class _FireTilePulseAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleFireTilePulse.CONFIG_ID)
		type = "fire_tile_pulse"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], {})
		var self_ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if self_ability == null or self_ability.is_expired():
			return ActionResult.create_success_result([], {})
		var owner_id := self_ability.owner_actor_id
		var fire_tile := battle.get_actor(owner_id)
		if fire_tile == null:
			return ActionResult.create_success_result([], {})
		var tile_coord: HexCoord = (fire_tile as HexBattleActor).hex_position
		if tile_coord == null:
			return ActionResult.create_success_result([], {})

		# 找所有站在 tile_coord 上的 alive CharacterActor (per Goal: tick 当下站在该 coord 的)
		var victims: Array[CharacterActor] = []
		for actor in battle.get_alive_actors():
			if not (actor is CharacterActor):
				continue
			var c := actor as CharacterActor
			if c.hex_position == null:
				continue
			if c.hex_position.q == tile_coord.q and c.hex_position.r == tile_coord.r:
				victims.append(c)

		if victims.is_empty():
			return ActionResult.create_success_result([], { "pulse_skipped": "no_victim" })

		var alive_ids := battle.get_alive_actor_ids()
		var collected: Array[Dictionary] = []
		for victim in victims:
			var event := BattleEvents.DamageEvent.create(
				victim.get_id(),
				HexBattleFireTilePulse.DEFAULT_PULSE_DAMAGE,
				BattleEvents.DamageType.PURE,
				owner_id,  # source = fire tile actor itself
				false,  # is_critical
				false,  # is_reflected
			)
			var damage_result := HexBattleDamageUtils.apply_damage(
				event, alive_ids, ctx, battle,
			)
			collected.append_array(damage_result.all_events)
			HexBattleDamageUtils.broadcast_post_damage(
				damage_result.damage_event_dict, alive_ids, battle,
			)
		return ActionResult.create_success_result(collected, {
			"fire_tile_pulse_victim_count": victims.size(),
		})


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("火焰地形脉冲")
	.description("每 1 秒对同格站位的角色造 %d 纯伤" % int(DEFAULT_PULSE_DAMAGE))
	.ability_tags(["passive", "fire_tile", "periodic"])
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_end([_FireTilePulseAction.new()])
		.build()
	)
	.build()
)
