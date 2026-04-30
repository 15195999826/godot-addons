## Smoke: SkillPreviewProcedure target 中途死亡时仍能 graceful 完成
##
## 配置: caster (atk=50) t=0/2100/4200 三发 Strike → dummy (hp=60)
##   第一发 50 dmg → hp=10
##   第二发 50 dmg → hp 归零, dummy 死
##   第三发 fire 时 target 已死, procedure 必须不崩, battle_finished 正常 emit
##
## 断言:
##   1. battle_finished emit 且 timeline 非空
##   2. 至少有 1 条 damage 事件 (放宽: Strike on_critical 暴击 + 50 base + 10 crit
##      可能让第一发就 60 = overkill 直接致死, 第二发命中 dead actor 行为由 LGF 决定;
##      关注点是 procedure 不崩, damage 多少由下层契约管)
##   3. 至少有 1 条 death 事件
##   4. caster 三次 keyframe 都 fire 到 (3 个 executionActivated, 不会因为
##      target 死亡而 silently 跳过整个 keyframe)
##
## 不断言: 暴击数量 / 第三发是否打到死者 —— 那是 LGF action 层 (DamageAction
## 对死者的语义) 的责任, 不在本测试覆盖。
extends Node


const TIMEOUT_SEC := 30.0


var _world: SkillPreviewWorldGI
var _caster_id: String = ""
var _dummy_id: String = ""
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: skill_preview proc target dies mid timeline ===")

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
	caster.attribute_set.set_atk_base(50.0)  # 控制伤害可预期
	_world.grid.place_occupant(HexCoord.new(0, 0), caster)
	caster.hex_position = HexCoord.new(0, 0)

	var dummy := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	dummy._display_name = "dummy"
	_world.add_actor(dummy)
	dummy.set_team_id(1)
	dummy.attribute_set.set_max_hp_base(60.0)
	dummy.attribute_set.set_hp_base(60.0)
	_world.grid.place_occupant(HexCoord.new(1, 0), dummy)
	dummy.hex_position = HexCoord.new(1, 0)

	_caster_id = caster.get_id()
	_dummy_id = dummy.get_id()

	_world.queue_preview([
		{
			"actor_id": _caster_id,
			"passives": [] as Array[AbilityConfig],
			"track": [
				{"time_ms": 0,    "ability_config": HexBattleStrike.ABILITY, "target_id": _dummy_id},
				{"time_ms": 2100, "ability_config": HexBattleStrike.ABILITY, "target_id": _dummy_id},
				{"time_ms": 4200, "ability_config": HexBattleStrike.ABILITY, "target_id": _dummy_id},
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
		_fail("Empty timeline (procedure crashed before producing any frame?)")
		return

	var dmg_count := 0
	var death_count := 0
	var exec_count := 0
	for frame_data in timeline.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary):
				continue
			var kind := str((ev as Dictionary).get("kind", ""))
			if kind == "damage" and str((ev as Dictionary).get("target_actor_id", "")) == _dummy_id:
				dmg_count += 1
			elif kind == "death":
				death_count += 1
			elif kind == "executionActivated" and str((ev as Dictionary).get("actorId", "")) == _caster_id:
				exec_count += 1

	if dmg_count < 1:
		_fail("expected at least 1 damage, got %d" % dmg_count)
		return
	if death_count < 1:
		_fail("expected dummy death event, got %d death events" % death_count)
		return
	if exec_count != 3:
		_fail("expected 3 executionActivated (procedure must fire all keyframes regardless of target state), got %d" % exec_count)
		return

	_pass("dmg=%d death=%d exec=%d (procedure didn't crash on dead target)" %
			[dmg_count, death_count, exec_count])


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
