## SpawnFireTileAction - spawn 一个火焰地形 EnvironmentActor (overlay, 不占 grid.occupant)
##
## V1 用例: Phase C SpawnFireTile 主动技能在 timeline HIT 调用本 action。
##
## 与 SpawnActorAction 差别:
## - 不调 grid.place_occupant (overlay 语义, 不与 character occupant 打架)
## - spawn EnvironmentActor (不是 CharacterActor)
## - 自动 grant FireTilePulse + FireTileLifetime passives
##
## spawn 位置: target_selector 选出的第一个 target actor 的 hex_position;
## 若无 target 或 target 无 hex_position → spawn 失败 (success no-op).
class_name HexBattleSpawnFireTileAction
extends Action.PrimitiveAction


var _pulse_interval_ms: float
var _pulse_damage: float
var _lifetime_ms: float


func _init(
	target_selector: TargetSelector,
	pulse_interval_ms: float = HexBattleFireTilePulse.DEFAULT_PULSE_INTERVAL_MS,
	pulse_damage: float = HexBattleFireTilePulse.DEFAULT_PULSE_DAMAGE,
	lifetime_ms: float = HexBattleFireTileLifetime.DEFAULT_DURATION_MS,
) -> void:
	super._init(target_selector)
	type = "spawn_fire_tile"
	_pulse_interval_ms = pulse_interval_ms
	_pulse_damage = pulse_damage
	_lifetime_ms = lifetime_ms


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	if battle == null:
		return ActionResult.create_success_result([], { "spawn_failed": "no_game_state" })
	var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	if targets.is_empty():
		return ActionResult.create_success_result([], { "spawn_failed": "no_target" })

	var target_actor := battle.get_actor(targets[0]) as HexBattleActor
	if target_actor == null:
		return ActionResult.create_success_result([], { "spawn_failed": "target_missing" })
	var spawn_coord: HexCoord = target_actor.hex_position
	if spawn_coord == null:
		return ActionResult.create_success_result([], { "spawn_failed": "no_target_position" })

	# Spawn fire tile (EnvironmentActor) — 不 place_occupant, overlay 语义
	var tile := HexBattleFireTile.create()
	tile.hex_position = spawn_coord.duplicate()
	battle.add_actor(
		tile,
		func(added: Actor) -> void:
			_initialize_fire_tile(added, battle, caster_id),
	)

	return ActionResult.create_success_result([], {
		"fire_tile_actor_id": tile.get_id(),
		"fire_tile_coord": [spawn_coord.q, spawn_coord.r],
	})


func _initialize_fire_tile(
	added: Actor,
	battle: HexWorldGameplayInstance,
	caster_id: String,
) -> void:
	var tile := added as EnvironmentActor
	if tile == null:
		return
	# Grant passives (PulseAction periodic + Lifetime auto-remove)
	# Note: HexBattleFireTilePulse.ABILITY 默认 1s interval / 20 damage; 自定义 interval/damage
	# 留给后续 (当前 V1 用默认值, 与 SpawnFireTileAction 的 _pulse_interval_ms 等参数解耦)。
	var pulse_ab := Ability.new(HexBattleFireTilePulse.ABILITY, tile.get_id(), caster_id)
	tile.ability_set.grant_ability(pulse_ab, battle)
	var lifetime_ab := Ability.new(
		HexBattleFireTileLifetime.create_config(_lifetime_ms),
		tile.get_id(),
		caster_id,
	)
	tile.ability_set.grant_ability(lifetime_ab, battle)
