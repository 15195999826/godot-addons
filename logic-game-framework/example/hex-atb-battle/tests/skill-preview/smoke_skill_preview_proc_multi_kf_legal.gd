## Smoke: SkillPreviewProcedure 单 actor 多 keyframe (timeline 合法 / cooldown 拦截)
##
## 配置: caster t=0 / t=500 / t=1000 三发 Strike → dummy
##   Strike timeline = 500ms (UI occupy 边界), cooldown = 2000ms
##   间隔 500ms 满足 timeline 边界 (UI 接受) — 但 cooldown=2000ms > 500ms,
##   后两发会在 ActiveUseComponent 被 CooldownCondition reject。
##
## 这是关注点分离后的核心回归: UI 只防 timeline 重叠, "能否释放"由 LGF 在
## fire 时检查并 push AbilityActivateFailed 事件供前端 console 渲染。
##
## 期望:
##   1. 1 条 executionActivated (第一发) + 2 条 abilityActivateFailed (后两发)
##   2. abilityActivateFailed.reason 含 "冷却" (来自 CooldownCondition.get_fail_reason)
##   3. abilityActivateFailed.failedComponentType == "condition"
##   4. caster 上只 grant 一个 Strike Ability (procedure 去重)
extends Node


const TIMEOUT_SEC := 30.0


var _world: SkillPreviewWorldGI
var _caster_id: String = ""
var _dummy_id: String = ""
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: skill_preview proc multi-keyframe legal (timeline ok, cooldown rejects) ===")

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
			"track": [
				{"time_ms": 0,    "ability_config": HexBattleStrike.ABILITY, "target_id": _dummy_id},
				{"time_ms": 500,  "ability_config": HexBattleStrike.ABILITY, "target_id": _dummy_id},
				{"time_ms": 1000, "ability_config": HexBattleStrike.ABILITY, "target_id": _dummy_id},
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

	var grant_count := 0
	var exec_count := 0
	var failed_events: Array[Dictionary] = []
	for frame_data in timeline.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary):
				continue
			var kind := str((ev as Dictionary).get("kind", ""))
			if kind == "abilityGranted" and str((ev as Dictionary).get("actorId", "")) == _caster_id:
				grant_count += 1
			elif kind == "executionActivated" and str((ev as Dictionary).get("actorId", "")) == _caster_id:
				exec_count += 1
			elif kind == "abilityActivateFailed" and str((ev as Dictionary).get("sourceId", "")) == _caster_id:
				failed_events.append(ev as Dictionary)

	if exec_count != 1:
		_fail("expected 1 executionActivated (only first fire passes cooldown), got %d" % exec_count)
		return
	if failed_events.size() != 2:
		_fail("expected 2 abilityActivateFailed events (后两发被 cooldown 拦), got %d" % failed_events.size())
		return
	if grant_count != 1:
		_fail("expected exactly 1 abilityGranted (instance reuse), got %d" % grant_count)
		return
	# 验证 reason 含"冷却" / failedComponentType=="condition"
	for fev in failed_events:
		var reason := str(fev.get("reason", ""))
		var ft := str(fev.get("failedComponentType", ""))
		if not ("冷却" in reason):
			_fail("expected reason to contain '冷却', got: %s" % reason)
			return
		if ft != "condition":
			_fail("expected failedComponentType=condition, got: %s" % ft)
			return

	_pass("exec=1 + 2 cooldown failures (reason='%s'); grant=1 (reused)" %
			str(failed_events[0].get("reason", "")))


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
