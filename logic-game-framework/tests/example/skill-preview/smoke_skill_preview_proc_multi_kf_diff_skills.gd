## Smoke: SkillPreviewProcedure 多 keyframe 不同 skill (cooldown namespace 隔离)
##
## 配置: caster t=0 Strike + t=200 SwiftStrike + t=2000 Strike → dummy
##   Strike cooldown 2000ms, SwiftStrike cooldown 3000ms, 不同 config_id
##   cooldown tag = cooldown:<config_id>, namespace 互不影响
##   t=200 SwiftStrike 不会被 Strike 的 cooldown:skill_strike tag 拦
##   t=2000 Strike 刚好踩在 cooldown 到期边界, 应该合法
##
## 期望 caster 上 executionActivated = 3 (Strike x2 + SwiftStrike x1, 各一次 execution)。
##   不用 damage 计数: Strike on_critical 暴击会多 push 一条 damage, 数量随机不稳。
##   execution 数 = keyframe 数, 与暴击无关, 稳定可断言。
extends Node


const TIMEOUT_SEC := 30.0


var _world: SkillPreviewWorldGI
var _caster_id: String = ""
var _dummy_id: String = ""
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: skill_preview proc multi-keyframe diff skills ===")

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
	dummy.attribute_set.set_max_hp_base(9999.0)  # 5 发都打中, 不会死
	dummy.attribute_set.set_hp_base(9999.0)
	_world.grid.place_occupant(HexCoord.new(1, 0), dummy)
	dummy.hex_position = HexCoord.new(1, 0)

	_caster_id = caster.get_id()
	_dummy_id = dummy.get_id()

	_world.queue_preview([
		{
			"actor_id": _caster_id,
			"passives": [] as Array[AbilityConfig],
			"track": [
				{"time_ms": 0,    "ability_config": HexBattleStrike.ABILITY,      "target_id": _dummy_id},
				{"time_ms": 200,  "ability_config": HexBattleSwiftStrike.ABILITY, "target_id": _dummy_id},
				{"time_ms": 2000, "ability_config": HexBattleStrike.ABILITY,      "target_id": _dummy_id},
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

	var exec_count := 0
	var grant_configs: Dictionary = {}
	for frame_data in timeline.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary):
				continue
			var kind := str((ev as Dictionary).get("kind", ""))
			if kind == "executionActivated" and str((ev as Dictionary).get("actorId", "")) == _caster_id:
				exec_count += 1
			elif kind == "abilityGranted" and str((ev as Dictionary).get("actorId", "")) == _caster_id:
				var ability_dict: Dictionary = (ev as Dictionary).get("ability", {}) as Dictionary
				grant_configs[str(ability_dict.get("configId", ""))] = true

	if exec_count != 3:
		_fail("expected 3 executionActivated (Strike x2 + SwiftStrike x1), got %d" % exec_count)
		return
	# 期望 grant 两个 config: skill_strike (复用 1 instance, 但只 grant 一次) + skill_swift_strike
	if not grant_configs.has("skill_strike"):
		_fail("missing skill_strike grant: %s" % str(grant_configs.keys()))
		return
	if not grant_configs.has("skill_swift_strike"):
		_fail("missing skill_swift_strike grant: %s" % str(grant_configs.keys()))
		return

	_pass("exec=3; granted configs=%s" % str(grant_configs.keys()))


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
