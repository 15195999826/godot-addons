## TotemLifetime - 图腾 actor-level TimeDuration 控制 + 自动 remove
##
## V1 用例: Phase C0 Summon Totem 召唤后图腾的 lifetime ability。
## TimeDurationConfig 到期 → ability.expire → NoInstanceConfig.on_remove → _RemoveOwnerActor
## 调 battle.remove_actor(owner.id), 同时清 grid。
##
## 与 spike 设计一致 (smoke_summon_spike.gd Phase 4b), 抽出 SkillLocalAction 私有内嵌。
class_name HexBattleTotemLifetime


const CONFIG_ID := "passive_totem_lifetime"
const DEFAULT_DURATION_MS := 15000.0


class _RemoveOwnerActorAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleTotemLifetime.CONFIG_ID)
		type = "totem_lifetime_remove_owner"

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
		.display_name("图腾寿命")
		.description("%.1f 秒后图腾自动消失" % (duration_ms / 1000.0))
		.ability_tags(["passive", "totem", "lifetime"])
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
