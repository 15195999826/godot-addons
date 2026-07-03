## Regeneration frontend smoke
##
## 验证 regeneration event 独立于 heal event, 但 frontend 仍按 actual_amount 更新 HP state。
extends Node


func _ready() -> void:
	print("=== Smoke: Regeneration Visualizer ===")
	Log.set_level(Log.LogLevel.WARNING)

	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	record.configs = {"positionFormats": {"Character": "hex"}}

	var actor_init := PlaybackData.ActorInitData.new()
	actor_init.id = "hero_1"
	actor_init.type = "Character"
	actor_init.display_name = "Hero"
	actor_init.team = 0
	actor_init.position = [0, 0, 0]
	actor_init.attributes = {"hp": 50.0, "maxHp": 100.0}
	record.initial_actors = [actor_init]

	var rw := FrontendRenderWorld.new()
	rw.initialize_from_replay(record)
	var registry := FrontendDefaultRegistry.create()
	if not registry.has_visualizer_for("regeneration"):
		_fail("default registry missing regeneration visualizer")
		return

	var scheduler := FrontendActionScheduler.new()
	var floating_texts: Array[String] = []
	rw.floating_text_created.connect(func(data: FrontendRenderData.FloatingText) -> void:
		floating_texts.append(data.text)
	)

	_run_frame(scheduler, registry, rw, [{
		"kind": "regeneration",
		"target_actor_id": "hero_1",
		"resource": "hp",
		"amount": 10.0,
		"actual_amount": 7.0,
		"source": "general_passive",
	}], "regen_7")

	var state := _get_state(rw)
	if not is_equal_approx(state.target_hp, 57.0):
		_fail("target_hp after regen should be 57, got %.2f" % state.target_hp)
		return
	if floating_texts != ["+7"]:
		_fail("expected one +7 floating text, got %s" % str(floating_texts))
		return

	_run_frame(scheduler, registry, rw, [{
		"kind": "regeneration",
		"target_actor_id": "hero_1",
		"resource": "hp",
		"amount": 10.0,
		"actual_amount": 0.0,
		"source": "general_passive",
	}], "regen_0")

	state = _get_state(rw)
	if not is_equal_approx(state.target_hp, 57.0):
		_fail("zero actual regen should not change target_hp, got %.2f" % state.target_hp)
		return
	if floating_texts != ["+7"]:
		_fail("zero actual regen should not create floating text, got %s" % str(floating_texts))
		return

	print("SMOKE_TEST_RESULT: PASS - regeneration updates frontend HP state without heal event")
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
		scheduler.enqueue(registry.translate(event, ctx))
	var result := scheduler.tick(100.0)
	rw.apply_actions(result.active_actions)
	rw.apply_actions(result.completed_this_tick)
	rw.flush_dirty_actors()
	print("  [frame %s] processed %d events" % [tag, events.size()])


func _get_state(rw: FrontendRenderWorld) -> FrontendActorRenderState:
	var snapshot := rw.get_actors_snapshot()
	return snapshot["hero_1"] as FrontendActorRenderState


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - " + reason)
	get_tree().quit(1)
