## FireTileLifetime - 火焰地形寿命 (与 TotemLifetime 同 pattern, 不同 config_id)
##
## TimeDurationConfig + NoInstance.on_remove → 内嵌 SkillLocalAction 调
## instance.remove_actor(owner.id) 自清 fire tile EnvironmentActor。
class_name HexBattleFireTileLifetime


const CONFIG_ID := "passive_fire_tile_lifetime"
const DEFAULT_DURATION_MS := 5000.0


class _RemoveOwnerActorAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleFireTileLifetime.CONFIG_ID)
		type = "fire_tile_lifetime_remove_owner"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if owner_id.is_empty():
			return ActionResult.create_success_result([], { "removed": false, "reason": "no_owner" })
		var actor := GameWorld.get_actor(owner_id)
		if actor == null:
			return ActionResult.create_success_result([], { "removed": false, "reason": "owner_missing" })
		var instance := actor.get_owner_gameplay_instance()
		if instance == null:
			return ActionResult.create_success_result([], { "removed": false, "reason": "instance_missing" })
		var removed := instance.remove_actor(owner_id)
		return ActionResult.create_success_result([], { "removed": removed })


static func create_config(duration_ms: float = DEFAULT_DURATION_MS) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("火焰地形寿命")
		.description("%.1f 秒后火焰地形自动消失" % (duration_ms / 1000.0))
		.ability_tags(["passive", "fire_tile", "lifetime"])
		.meta("duration_ms", duration_ms)
		.component_config(TimeDurationConfig.new(duration_ms))
		.component_config(
			NoInstanceConfig.builder()
			.on_remove_actions(_on_remove_actions())
			.build()
		)
		.build()
	)


static func _on_remove_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [_RemoveOwnerActorAction.new()]
	return arr
