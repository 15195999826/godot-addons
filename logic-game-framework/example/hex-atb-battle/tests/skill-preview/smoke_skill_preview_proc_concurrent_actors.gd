## Smoke: SkillPreviewProcedure 多 actor 同时刻 deterministic 顺序
##
## 配置: 3 个 caster 同 t=0 各 cast 一发 Strike → 各自 dummy
##   按 setup 数组顺序 [c1, c2, c3] queue_preview, procedure 内部排序应该按
##   (time_ms asc, actor_order asc) —— 同 time 同 t=0 时, actor_order 决定顺序。
##
## 期望: frame 1 (start() drain t<=0 keyframe + 第一次 record_current_frame_events) 里
##   abilityGranted / executionActivated 事件按 c1, c2, c3 顺序出现。
extends Node


const TIMEOUT_SEC := 30.0


var _world: SkillPreviewWorldGI
var _caster_ids: Array[String] = []
var _dummy_ids: Array[String] = []
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: skill_preview proc concurrent actors deterministic ===")

	GameWorld.init()
	_world = SkillPreviewWorldGI.new()
	GameWorld.create_instance(func() -> GameplayInstance: return _world)
	_world.start()
	_world.battle_finished.connect(_on_battle_finished)

	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = 4
	cfg.orientation = GridMapConfig.Orientation.FLAT
	cfg.size = 1.0
	_world.configure_grid(cfg)

	var collision_detector := MobaCollisionDetector.new()
	_world.add_system(ProjectileSystem.new(collision_detector, GameWorld.event_collector, false))
	HexBattleAllSkills.register_all_timelines()

	# 3 个 caster (q=0/0/0, r=-2/0/2), 3 个 dummy (q=1, 同 r) 各自的相邻格
	var caster_positions := [HexCoord.new(0, -2), HexCoord.new(0, 0), HexCoord.new(0, 2)]
	var dummy_positions := [HexCoord.new(1, -2), HexCoord.new(1, 0), HexCoord.new(1, 2)]
	for i in 3:
		var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
		caster._display_name = "caster_%d" % i
		_world.add_actor(caster)
		caster.set_team_id(0)
		caster.attribute_set.set_max_hp_base(1000.0)
		caster.attribute_set.set_hp_base(1000.0)
		_world.grid.place_occupant(caster_positions[i], caster)
		caster.hex_position = caster_positions[i]
		_caster_ids.append(caster.get_id())

		var dummy := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
		dummy._display_name = "dummy_%d" % i
		_world.add_actor(dummy)
		dummy.set_team_id(1)
		dummy.attribute_set.set_max_hp_base(1000.0)
		dummy.attribute_set.set_hp_base(1000.0)
		_world.grid.place_occupant(dummy_positions[i], dummy)
		dummy.hex_position = dummy_positions[i]
		_dummy_ids.append(dummy.get_id())

	var setups: Array[Dictionary] = []
	for i in 3:
		setups.append({
			"actor_id": _caster_ids[i],
			"passives": [] as Array[AbilityConfig],
			"track": [{
				"time_ms": 0,
				"ability_config": HexBattleStrike.ABILITY,
				"target_id": _dummy_ids[i],
			}],
		})
	_world.queue_preview(setups, false)

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

	# 收集 executionActivated 的 actor 顺序
	var exec_actor_order: Array[String] = []
	for frame_data in timeline.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary):
				continue
			if str((ev as Dictionary).get("kind", "")) != "executionActivated":
				continue
			var actor_id := str((ev as Dictionary).get("actorId", ""))
			if actor_id in _caster_ids:
				exec_actor_order.append(actor_id)

	if exec_actor_order.size() != 3:
		_fail("expected 3 executionActivated events, got %d (%s)" %
				[exec_actor_order.size(), str(exec_actor_order)])
		return

	for i in 3:
		if exec_actor_order[i] != _caster_ids[i]:
			_fail("order mismatch at idx %d: expected %s, got %s (full=%s)" %
					[i, _caster_ids[i], exec_actor_order[i], str(exec_actor_order)])
			return

	_pass("3 casters fired in setup order: %s" % str(exec_actor_order))


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
