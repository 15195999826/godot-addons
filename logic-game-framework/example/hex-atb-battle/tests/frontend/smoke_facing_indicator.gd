## Phase F · Facing 前端回归 smoke
##
## 验证三条契约:
##   1. Replay 初始化时 RenderWorld 从 actor_init.attributes 读 facing_direction (snapshot 链路)
##   2. actor_facing_changed event 翻译为 ApplyFacingStateAction → RenderWorld 更新 facing
##   3. EnvironmentActor 的 FacingIndicatorView 在 set_environment_style 后隐藏
##
## 不验证视觉旋转角度 (单元 smoke 无相机 / 无渲染断言); 用 FrontendActorRenderState.facing_direction
## 数值确认 frontend state 同步, UnitView 用 visible 标志确认 env actor 不显示.
extends Node


func _ready() -> void:
	print("=== Smoke: Facing Indicator (init + event + env-hidden) ===")
	Log.set_level(Log.LogLevel.WARNING)

	# ===== Step 1: Replay init reads facing_direction from attributes =====
	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	record.configs = {"positionFormats": {"Character": "hex"}}

	var hero_a := PlaybackData.ActorInitData.new()
	hero_a.id = "hero_a"
	hero_a.type = "Character"
	hero_a.team = 0
	hero_a.position = [0, 0, 0]
	# A 队默认朝东 (DIR_EAST = 0)
	hero_a.attributes = {"hp": 100.0, "maxHp": 100.0, "facing_direction": HexFacing.DIR_EAST}

	var hero_b := PlaybackData.ActorInitData.new()
	hero_b.id = "hero_b"
	hero_b.type = "Character"
	hero_b.team = 1
	hero_b.position = [1, 0, 0]
	# B 队默认朝西 (DIR_WEST = 3)
	hero_b.attributes = {"hp": 100.0, "maxHp": 100.0, "facing_direction": HexFacing.DIR_WEST}

	# Environment actor 不带 facing_direction 字段, RenderWorld 读到默认 0
	var wall := PlaybackData.ActorInitData.new()
	wall.id = "wall_1"
	wall.type = "Environment"
	wall.team = -1
	wall.position = [2, 0, 0]
	wall.attributes = {"hp": 100.0, "maxHp": 100.0}

	record.initial_actors = [hero_a, hero_b, wall]

	var rw := FrontendRenderWorld.new()
	rw.initialize_from_replay(record)

	var snapshot: Dictionary = rw.get_actors_snapshot()
	var state_a: FrontendActorRenderState = snapshot["hero_a"]
	var state_b: FrontendActorRenderState = snapshot["hero_b"]
	var state_wall: FrontendActorRenderState = snapshot["wall_1"]

	if state_a.facing_direction != HexFacing.DIR_EAST:
		_fail("init hero_a.facing_direction = %d (expected DIR_EAST=%d)" % [state_a.facing_direction, HexFacing.DIR_EAST])
		return
	if state_b.facing_direction != HexFacing.DIR_WEST:
		_fail("init hero_b.facing_direction = %d (expected DIR_WEST=%d)" % [state_b.facing_direction, HexFacing.DIR_WEST])
		return
	# Wall 默认 0 (DIR_EAST), 但 UnitView 自查 type 跳过显示, 不靠这里值. 仅断言不抛错.
	if state_wall.facing_direction != 0:
		_fail("init wall.facing_direction = %d (expected 0 default)" % state_wall.facing_direction)
		return
	print("  Step1 PASS: replay init seeded facing from attributes (A=%d B=%d wall=%d)" % [
		state_a.facing_direction, state_b.facing_direction, state_wall.facing_direction
	])

	# ===== Step 2: actor_facing_changed event updates state =====
	var scheduler := FrontendActionScheduler.new()
	var registry := FrontendDefaultRegistry.create()

	var facing_event: Dictionary = {
		"kind": "actor_facing_changed",
		"actor_id": "hero_a",
		"old_direction": HexFacing.DIR_EAST,
		"new_direction": HexFacing.DIR_NORTHEAST,
		"reason": "active_use",
	}
	_run_frame(scheduler, registry, rw, [facing_event], "facing_change")

	snapshot = rw.get_actors_snapshot()
	state_a = snapshot["hero_a"]
	if state_a.facing_direction != HexFacing.DIR_NORTHEAST:
		_fail("after event, hero_a.facing = %d (expected DIR_NORTHEAST=%d)" % [state_a.facing_direction, HexFacing.DIR_NORTHEAST])
		return
	print("  Step2 PASS: actor_facing_changed event → FrontendActorRenderState.facing_direction updated")

	# B 队 actor 未收到事件 → 不变
	state_b = snapshot["hero_b"]
	if state_b.facing_direction != HexFacing.DIR_WEST:
		_fail("hero_b should be unchanged (DIR_WEST=%d), got %d" % [HexFacing.DIR_WEST, state_b.facing_direction])
		return
	print("  Step3 PASS: unrelated actor's facing untouched by event")

	# ===== Step 3: FrontendUnitView indicator visibility (Character vs Environment) =====
	var char_view := FrontendUnitView.new()
	add_child(char_view)
	await get_tree().process_frame  # let _ready fire to instantiate sub-views

	state_a.type = "Character"
	char_view.update_state(state_a)
	if not char_view.get_facing_indicator_view().visible:
		_fail("Character UnitView's facing indicator should be visible")
		return
	print("  Step4 PASS: CharacterActor UnitView shows facing indicator")

	# Env actor: set_environment_style 应隐藏 indicator
	var env_view := FrontendUnitView.new()
	add_child(env_view)
	await get_tree().process_frame
	env_view.set_environment_style("stone_wall")
	# 同时 update_state 给一个 Environment 类型的 state: indicator 自身也会因 type != "Character" 隐藏
	state_wall.type = "Environment"
	env_view.update_state(state_wall)
	if env_view.get_facing_indicator_view().visible:
		_fail("Environment UnitView's facing indicator should be hidden")
		return
	print("  Step5 PASS: EnvironmentActor UnitView hides facing indicator (per spec)")

	print("SMOKE_TEST_RESULT: PASS - facing replay init + event update + env-hidden all OK")
	get_tree().quit(0)


func _run_frame(
	scheduler: FrontendActionScheduler,
	registry: FrontendVisualizerRegistry,
	rw: FrontendRenderWorld,
	events: Array[Dictionary],
	tag: String,
) -> void:
	var ctx := rw.as_context()
	for event in events:
		var actions := registry.translate(event, ctx)
		scheduler.enqueue(actions)
	var result := scheduler.tick(100.0)
	rw.apply_actions(result.active_actions)
	rw.apply_actions(result.completed_this_tick)
	rw.cleanup(rw.get_world_time())
	rw.flush_dirty_actors()
	print("  [frame %s] processed %d events" % [tag, events.size()])


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - " + reason)
	get_tree().quit(1)
