## Smoke: SkillPreviewProcedure 不继续 tick 已死亡 actor 身上的 ability
##
## 配置: caster t=0 Poison -> dummy, t=1000 Execute -> dummy。
## dummy 初始 15/100 HP, Execute 命中后死亡；PoisonBuff 的首轮 DOT 原本应在
## 2300ms 左右 tick。正式 HexBattleProcedure 只 tick alive characters, 因此
## dummy 死亡后 buff timeline 应冻结, 不再产生 poison damage / stacks changed。
extends Node


const TIMEOUT_SEC := 30.0


var _world: SkillPreviewWorldGI
var _caster_id: String = ""
var _dummy_id: String = ""
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: skill_preview proc dead actor ability does not tick ===")

	GameWorld.init()
	_world = SkillPreviewWorldGI.new()
	GameWorld.create_instance(func() -> GameplayInstance: return _world)
	_world.start()
	_world.battle_finished.connect(_on_battle_finished)

	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = 3
	cfg.orientation = GridMapConfig.Orientation.FLAT
	cfg.size = 1.0
	_world.configure_grid(cfg)

	var collision_detector := MobaCollisionDetector.new()
	_world.add_system(ProjectileSystem.new(collision_detector, GameWorld.event_collector, false))
	HexBattleAllSkills.register_all_timelines()

	var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	caster._display_name = "caster"
	_world.add_actor(caster)
	caster.set_team_id(0)
	caster.attribute_set.set_max_hp_base(1000.0)
	caster.attribute_set.set_hp_base(1000.0)
	_world.grid.place_occupant(HexCoord.new(0, 0), caster)
	caster.hex_position = HexCoord.new(0, 0)

	var dummy := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	dummy._display_name = "dummy"
	_world.add_actor(dummy)
	dummy.set_team_id(1)
	dummy.attribute_set.set_max_hp_base(100.0)
	dummy.attribute_set.set_hp_base(15.0)
	_world.grid.place_occupant(HexCoord.new(1, 0), dummy)
	dummy.hex_position = HexCoord.new(1, 0)

	_caster_id = caster.get_id()
	_dummy_id = dummy.get_id()

	_world.queue_preview([
		{
			"actor_id": _caster_id,
			"passives": [] as Array[AbilityConfig],
			"track": [
				{"time_ms": 0, "ability_config": HexBattlePoison.ABILITY, "target_id": _dummy_id},
				{"time_ms": 1000, "ability_config": HexBattleExecute.ABILITY, "target_id": _dummy_id},
			],
		},
		{
			"actor_id": _dummy_id,
			"passives": [] as Array[AbilityConfig],
			"track": [] as Array[Dictionary],
		},
	], false)

	var participants: Array[Actor] = []
	for actor in _world.get_actors():
		participants.append(actor)
	_world.start_battle(participants)
	_world.tick(100.0)


func _process(dt: float) -> void:
	if _finished:
		return
	_elapsed += dt
	if _elapsed > TIMEOUT_SEC:
		_fail("timeout")


func _on_battle_finished(timeline: Dictionary) -> void:
	if _finished:
		return
	if timeline.is_empty():
		_fail("Empty timeline")
		return

	var death_seen := false
	var poison_granted := false
	var post_death_damage_count := 0
	var post_death_stack_count := 0
	for frame_data in timeline.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary):
				continue
			var event_dict := ev as Dictionary
			var kind := str(event_dict.get("kind", ""))
			if kind == GameEvent.ABILITY_GRANTED_EVENT and str(event_dict.get("actorId", "")) == _dummy_id:
				var ability_dict: Dictionary = event_dict.get("ability", {}) as Dictionary
				if str(ability_dict.get("configId", "")) == HexBattlePoisonBuff.CONFIG_ID:
					poison_granted = true
			elif kind == "death" and str(event_dict.get("actor_id", "")) == _dummy_id:
				death_seen = true
			elif death_seen and kind == "damage" and str(event_dict.get("target_actor_id", "")) == _dummy_id:
				post_death_damage_count += 1
			elif death_seen and kind == GameEvent.ABILITY_STACKS_CHANGED_EVENT and str(event_dict.get("actorId", "")) == _dummy_id:
				if str(event_dict.get("abilityConfigId", "")) == HexBattlePoisonBuff.CONFIG_ID:
					post_death_stack_count += 1

	if not poison_granted:
		_fail("expected PoisonBuff grant before dummy death")
		return
	if not death_seen:
		_fail("expected dummy death event")
		return
	if post_death_damage_count != 0:
		_fail("dead dummy received %d post-death damage events" % post_death_damage_count)
		return
	if post_death_stack_count != 0:
		_fail("dead dummy produced %d post-death poison stack events" % post_death_stack_count)
		return

	_pass("poison buff granted, dummy died, no post-death buff tick events")


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
