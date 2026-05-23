## Swap #E - 位置交换主动技能
##
## V1 行为 (per Goal):
## - target: CharacterActor (自/友/敌可); 不能 self target, 不能 EnvironmentActor
## - range=3
## - effect: caster 与 target 原子交换 hex_position + grid occupant
## - event: 双 ActorDisplacedEvent 同 swap_id, caster event 先, target event 后
## - failure: validate-all 失败 (双 alive + valid coord + grid occupant 一致) → 不改 grid/actor
## - 不造伤 / 不触发碰撞 / 不加 cant_act
class_name HexBattleSwap


const CONFIG_ID := "skill_swap"
const TIMELINE_ID := "skill_swap"
const COOLDOWN_MS := 8000.0
const DISPLACEMENT_KIND := "swap"


static var SWAP_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


class _SwapPositionsAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.current_target(), HexBattleSwap.CONFIG_ID)
		type = "swap_positions"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], { "swap_failed": "no_game_state" })
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		var targets := get_targets(ctx)
		if targets.is_empty():
			return ActionResult.create_success_result([], { "swap_failed": "no_target" })
		var target_id := targets[0]

		# Validate all
		if caster_id == target_id:
			return ActionResult.create_success_result([], { "swap_failed": "self_target" })
		var caster := battle.get_actor(caster_id) as CharacterActor
		var target := battle.get_actor(target_id) as CharacterActor
		if caster == null:
			return ActionResult.create_success_result([], { "swap_failed": "caster_invalid" })
		if target == null:
			return ActionResult.create_success_result([], { "swap_failed": "target_not_character" })
		if caster.is_dead() or target.is_dead():
			return ActionResult.create_success_result([], { "swap_failed": "dead_actor" })
		var caster_pos: HexCoord = caster.hex_position
		var target_pos: HexCoord = target.hex_position
		if caster_pos == null or target_pos == null:
			return ActionResult.create_success_result([], { "swap_failed": "invalid_coord" })
		var grid = battle.grid
		if grid == null:
			return ActionResult.create_success_result([], { "swap_failed": "no_grid" })
		if grid.get_occupant(caster_pos) != caster:
			return ActionResult.create_success_result([], { "swap_failed": "caster_occupant_mismatch" })
		if grid.get_occupant(target_pos) != target:
			return ActionResult.create_success_result([], { "swap_failed": "target_occupant_mismatch" })

		# Commit (atomic): 临时清两个 occupant → 重放
		grid.remove_occupant(caster_pos)
		grid.remove_occupant(target_pos)
		grid.place_occupant(target_pos, caster)
		grid.place_occupant(caster_pos, target)
		caster.hex_position = target_pos.duplicate()
		target.hex_position = caster_pos.duplicate()

		# 双 ActorDisplacedEvent 同 swap_id (caster 先, target 后)
		var swap_id := IdGenerator.generate("swap")
		var caster_event := BattleEvents.ActorDisplacedEvent.create(
			caster_id,
			{ "q": caster_pos.q, "r": caster_pos.r },
			{ "q": target_pos.q, "r": target_pos.r },
			DISPLACEMENT_KIND,
			caster_id,  # source = caster
			1,  # actual_distance (treated as 1 hex for swap)
			0.0,  # no action_lock
			0.0,
		)
		var caster_dict := caster_event.to_dict()
		caster_dict["swap_id"] = swap_id
		ctx.event_collector.push(caster_dict)

		var target_event := BattleEvents.ActorDisplacedEvent.create(
			target_id,
			{ "q": target_pos.q, "r": target_pos.r },
			{ "q": caster_pos.q, "r": caster_pos.r },
			DISPLACEMENT_KIND,
			caster_id,
			1,
			0.0,
			0.0,
		)
		var target_dict := target_event.to_dict()
		target_dict["swap_id"] = swap_id
		ctx.event_collector.push(target_dict)

		return ActionResult.create_success_result([caster_dict, target_dict], {
			"swap_id": swap_id,
			"caster_id": caster_id,
			"target_id": target_id,
		})


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("交换")
	.description("与 3 格内的角色原子交换位置 (自己 / 友方 / 敌方都可)")
	.ability_tags(["skill", "active", "ranged", "swap"])
	.meta(HexBattleSkillMetaKeys.RANGE, 3)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("swap_blink"),
		)])
		.on_tag(TimelineTags.HIT, [_SwapPositionsAction.new()])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
