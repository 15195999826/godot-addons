## Smoke: production HexBattleProcedure records mid-spawn actor lifecycle.
##
## Covers Summon Totem + Fire Tile through production procedure recorder/tick path,
## not SkillPreviewProcedure or scenario harness.
extends Node


const TICK_INTERVAL := 100.0


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: Production mid-spawn replay lifecycle ===")

	if not _phase_summon_totem():
		return
	if not _phase_fire_tile():
		return

	print("SMOKE_TEST_RESULT: PASS - production mid-spawn replay lifecycle covered")
	get_tree().quit(0)


func _phase_summon_totem() -> bool:
	var replay := _run_production_skill(
		HexBattleSummonTotem.create_config(4200.0),
		"",
		60,
	)
	var spawned := _find_spawned_actor_by_config(replay, "Totem")
	if spawned.is_empty():
		return _fail("SummonTotem: missing actorSpawned for Totem")
	var totem_id := str(spawned.get("actorId", ""))
	var actor_data: Dictionary = spawned.get("actor", {}) as Dictionary
	if int(actor_data.get("team", -1)) != 0:
		return _fail("SummonTotem: spawned Totem team snapshot expected 0")
	if _actor_data_position_is(actor_data, 0.0, 0.0):
		return _fail("SummonTotem: spawned Totem position snapshot stayed at default origin")
	if not _actor_data_has_ability(actor_data, HexBattleTotemAttack.CONFIG_ID):
		return _fail("SummonTotem: actorSpawned snapshot missing TotemAttack")
	if not _actor_data_has_ability(actor_data, HexBattleTotemLifetime.CONFIG_ID):
		return _fail("SummonTotem: actorSpawned snapshot missing TotemLifetime")
	if not _has_ability_granted(replay, totem_id, HexBattleTotemAttack.CONFIG_ID):
		return _fail("SummonTotem: missing synthesized TotemAttack abilityGranted")
	if not _has_execution_activated(replay, totem_id, HexBattleTotemAttack.CONFIG_ID):
		return _fail("SummonTotem: missing TotemAttack executionActivated")
	if not _has_stage_cue(replay, totem_id, HexBattleTotemAttack.STAGE_CUE_ID):
		return _fail("SummonTotem: missing TotemAttack stageCue for attack VFX")
	if not _has_actor_destroyed(replay, totem_id):
		return _fail("SummonTotem: missing actorDestroyed after TotemLifetime")
	print("  [PASS] SummonTotem production replay")
	return true


func _phase_fire_tile() -> bool:
	var replay := _run_production_skill(
		HexBattleSpawnFireTile.create_config(1800.0),
		"enemy",
		45,
	)
	var spawned := _find_spawned_actor_by_config(replay, HexBattleFireTile.KIND)
	if spawned.is_empty():
		return _fail("FireTile: missing actorSpawned for fire_tile")
	var fire_tile_id := str(spawned.get("actorId", ""))
	var actor_data: Dictionary = spawned.get("actor", {}) as Dictionary
	if not _actor_data_position_is(actor_data, 2.0, 0.0):
		return _fail("FireTile: actorSpawned position snapshot expected target coord [2,0]")
	if not _actor_data_has_ability(actor_data, HexBattleFireTilePulse.CONFIG_ID):
		return _fail("FireTile: actorSpawned snapshot missing FireTilePulse")
	if not _actor_data_has_ability(actor_data, HexBattleFireTileLifetime.CONFIG_ID):
		return _fail("FireTile: actorSpawned snapshot missing FireTileLifetime")
	if not _has_ability_granted(replay, fire_tile_id, HexBattleFireTilePulse.CONFIG_ID):
		return _fail("FireTile: missing synthesized FireTilePulse abilityGranted")
	if not _has_execution_activated(replay, fire_tile_id, HexBattleFireTilePulse.CONFIG_ID):
		return _fail("FireTile: missing FireTilePulse executionActivated")
	if not _has_actor_destroyed(replay, fire_tile_id):
		return _fail("FireTile: missing actorDestroyed after FireTileLifetime")
	if not _has_damage_from(replay, fire_tile_id):
		return _fail("FireTile: missing pulse damage from spawned fire tile")
	print("  [PASS] FireTile production replay")
	return true


func _run_production_skill(skill_config: AbilityConfig, target_mode: String, tick_count: int) -> Dictionary:
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()

	var world := GameWorld.create_instance(func() -> GameplayInstance:
		var inst := HexWorldGameplayInstance.new()
		var grid_cfg := GridMapConfig.new()
		grid_cfg.grid_type = GridMapConfig.GridType.HEX
		grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
		grid_cfg.radius = 3
		inst.configure_grid(grid_cfg)
		return inst
	) as HexWorldGameplayInstance
	world.start()

	var caster := _add_character(world, HexBattleClassConfig.CharacterClass.WARRIOR, 0, HexCoord.new(0, 0), 2000.0, 50.0)
	var enemy := _add_character(world, HexBattleClassConfig.CharacterClass.WARRIOR, 1, HexCoord.new(2, 0), 2000.0, 10.0)

	var proc := HexBattleProcedure.new(world, [caster], [enemy], {
		"logging": false,
		"recording": true,
		"file_log": false,
	})
	proc.start()

	var ability := Ability.new(skill_config, caster.get_id())
	caster.ability_set.grant_ability(ability, world)
	var activate_event := {
		"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
		"abilityInstanceId": ability.id,
		"sourceId": caster.get_id(),
		"logicTime": 0.0,
	}
	if target_mode == "enemy":
		activate_event["target_actor_id"] = enemy.get_id()
	caster.ability_set.receive_event(activate_event, world)

	for _i in range(tick_count):
		proc.tick_once()

	var replay := proc.finish("mid_spawn_smoke")
	GameWorld.destroy()
	return replay


func _add_character(
	world: HexWorldGameplayInstance,
	char_class: HexBattleClassConfig.CharacterClass,
	team_id: int,
	coord: HexCoord,
	hp: float,
	atk: float,
) -> CharacterActor:
	var actor := CharacterActor.new(char_class)
	actor.set_team_id(team_id)
	actor.hex_position = coord.duplicate()
	actor.attribute_set.set_max_hp_base(hp)
	actor.attribute_set.set_hp_base(hp)
	actor.attribute_set.set_atk_base(atk)
	actor.attribute_set.set_speed_base(0.0)
	world.add_actor(
		actor,
		func(added: Actor) -> void:
			world.grid.place_occupant(coord, added as CharacterActor),
	)
	return actor


func _flatten_events(replay: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for frame in replay.get("timeline", []) as Array:
		if not (frame is Dictionary):
			continue
		for event in (frame as Dictionary).get("events", []) as Array:
			if event is Dictionary:
				result.append(event as Dictionary)
	return result


func _find_spawned_actor_by_config(replay: Dictionary, config_id: String) -> Dictionary:
	for event in _flatten_events(replay):
		if str(event.get("kind", "")) != GameEvent.ACTOR_SPAWNED_EVENT:
			continue
		var actor_data: Dictionary = event.get("actor", {}) as Dictionary
		if str(actor_data.get("configId", "")) == config_id:
			return event
	return {}


func _actor_data_has_ability(actor_data: Dictionary, config_id: String) -> bool:
	for ability in actor_data.get("abilities", []) as Array:
		if ability is Dictionary and str((ability as Dictionary).get("config_id", "")) == config_id:
			return true
	return false


func _actor_data_position_is(actor_data: Dictionary, q: float, r: float) -> bool:
	var position: Array = actor_data.get("position", []) as Array
	if position.size() < 2:
		return false
	return absf(float(position[0]) - q) < 0.01 and absf(float(position[1]) - r) < 0.01


func _has_ability_granted(replay: Dictionary, actor_id: String, config_id: String) -> bool:
	for event in _flatten_events(replay):
		if str(event.get("kind", "")) != GameEvent.ABILITY_GRANTED_EVENT:
			continue
		if str(event.get("actorId", "")) != actor_id:
			continue
		var ability_data: Dictionary = event.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) == config_id:
			return true
	return false


func _has_execution_activated(replay: Dictionary, actor_id: String, config_id: String) -> bool:
	for event in _flatten_events(replay):
		if str(event.get("kind", "")) != GameEvent.EXECUTION_ACTIVATED_EVENT:
			continue
		if str(event.get("actorId", "")) != actor_id:
			continue
		if str(event.get("abilityConfigId", "")) == config_id:
			return true
	return false


func _has_stage_cue(replay: Dictionary, actor_id: String, cue_id: String) -> bool:
	for event_dict in _flatten_events(replay):
		if str(event_dict.get("kind", "")) != GameEvent.STAGE_CUE_EVENT:
			continue
		if str(event_dict.get("sourceActorId", "")) == actor_id and str(event_dict.get("cueId", "")) == cue_id:
			return true
	return false


func _has_actor_destroyed(replay: Dictionary, actor_id: String) -> bool:
	for event in _flatten_events(replay):
		if str(event.get("kind", "")) == GameEvent.ACTOR_DESTROYED_EVENT \
				and str(event.get("actorId", "")) == actor_id:
			return true
	return false


func _has_damage_from(replay: Dictionary, source_id: String) -> bool:
	for event in _flatten_events(replay):
		if str(event.get("kind", "")) == "damage" \
				and str(event.get("source_actor_id", "")) == source_id:
			return true
	return false


func _fail(msg: String) -> bool:
	print("  [FAIL] %s" % msg)
	print("SMOKE_TEST_RESULT: FAIL - %s" % msg)
	get_tree().quit(1)
	return false
