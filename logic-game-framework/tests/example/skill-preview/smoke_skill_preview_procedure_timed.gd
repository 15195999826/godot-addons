## Smoke test: SkillPreviewProcedure 真实调度 (走 queue_preview + start_battle 路径)
##
## 目标: 验证 procedure 自己的 _fire_due_keyframes 在 t>0 keyframe 上的调度行为
## 与 HexBattleSkillScenarioHarness.run_with_actions helper 一致 —— 防止两者实现漂移。
##
## 配置: caster 在 (0,0) t=0   Strike → dummy
##       dummy  在 (1,0) t=500 Strike → caster
##
## 断言: timeline 里两条 damage 事件分别落在 frame >=1 和 >=6, 且 caster 那条 < dummy 那条。
##
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


const TIMEOUT_SEC := 30.0


var _world: SkillPreviewWorldGI
var _caster_id: String = ""
var _dummy_id: String = ""
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: SkillPreviewProcedure timed scheduling ===")

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
	dummy.attribute_set.set_max_hp_base(1000.0)
	dummy.attribute_set.set_hp_base(1000.0)
	_world.grid.place_occupant(HexCoord.new(1, 0), dummy)
	dummy.hex_position = HexCoord.new(1, 0)

	_caster_id = caster.get_id()
	_dummy_id = dummy.get_id()

	_world.queue_preview([
		{
			"actor_id": _caster_id,
			"passives": [] as Array[AbilityConfig],
			"track": [{
				"time_ms": 0,
				"ability_config": HexBattleStrike.ABILITY,
				"target_id": _dummy_id,
			}],
		},
		{
			"actor_id": _dummy_id,
			"passives": [] as Array[AbilityConfig],
			"track": [{
				"time_ms": 500,
				"ability_config": HexBattleStrike.ABILITY,
				"target_id": _caster_id,
			}],
		},
	], false)

	var participants: Array[Actor] = []
	for actor in _world.get_actors():
		participants.append(actor)
	_world.start_battle(participants)
	# BATTLE_TICKS_PER_WORLD_FRAME=INT_MAX 默认下一次 tick 跑完整场, 同步 emit battle_finished。
	_world.tick(100.0)


func _process(dt: float) -> void:
	if _finished:
		return
	_elapsed += dt
	if _elapsed > TIMEOUT_SEC:
		_fail("timeout %.1fs (battle_finished not emitted)" % _elapsed)


func _on_battle_finished(timeline: Dictionary) -> void:
	if _finished:
		return
	if timeline.is_empty():
		_fail("Empty timeline")
		return

	var caster_dmg_frame := -1
	var dummy_dmg_frame := -1
	for frame_data in timeline.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		var frame := int((frame_data as Dictionary).get("frame", 0))
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary) or str((ev as Dictionary).get("kind", "")) != "damage":
				continue
			var target := str((ev as Dictionary).get("target_actor_id", ""))
			if target == _dummy_id and caster_dmg_frame < 0:
				caster_dmg_frame = frame
			elif target == _caster_id and dummy_dmg_frame < 0:
				dummy_dmg_frame = frame

	if caster_dmg_frame < 0:
		_fail("No damage to dummy (caster t=0 Strike never landed)")
		return
	if dummy_dmg_frame < 0:
		_fail("No damage to caster (dummy t=500 Strike never landed)")
		return
	if caster_dmg_frame >= dummy_dmg_frame:
		_fail("Order wrong: caster=%d should be < dummy=%d" % [caster_dmg_frame, dummy_dmg_frame])
		return
	if dummy_dmg_frame - caster_dmg_frame < 4:
		_fail("Separation %d too small for 500ms delay (caster=%d dummy=%d)"
			% [dummy_dmg_frame - caster_dmg_frame, caster_dmg_frame, dummy_dmg_frame])
		return

	_pass("caster damage @ frame %d; dummy damage @ frame %d; separation = %d frames"
		% [caster_dmg_frame, dummy_dmg_frame, dummy_dmg_frame - caster_dmg_frame])


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
