## Regeneration frontend smoke
##
## 验证 regeneration event 独立于 heal event, 但 frontend 仍按 actual_amount 更新 HP state。
## 事件经 VisualDirector.pump 走完整链路;账本只走 Director 的公开读法, 飘字经 Director 转发的 effect_spawned 观察。
extends Node


## 每趟 pump 推进的表演时间(毫秒)= 录像 tick_interval
const STEP_MS := 100.0


func _ready() -> void:
	print("=== Smoke: Regeneration Translator ===")
	Log.set_level(Log.LogLevel.WARNING)

	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	var snap := PlaybackData.WorldSnapshot.new()
	snap.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	snap.position_formats = {"Character": "hex"}
	record.world_snapshot = snap

	var actor_init := PlaybackData.ActorInitData.new()
	actor_init.id = "hero_1"
	actor_init.type = "Character"
	actor_init.display_name = "Hero"
	actor_init.team = 0
	actor_init.position = [0, 0, 0]
	actor_init.attributes = {"hp": 50.0, "max_hp": 100.0}
	snap.actors = [actor_init]

	var registry := FrontendDefaultRegistry.create()
	if not registry.has_translator_for("regeneration"):
		_fail("default registry missing regeneration translator")
		return

	var director := ReplayDirector.new(registry)
	add_child(director)
	var floating_texts: Array[String] = []
	director.effect_spawned.connect(func(kind: StringName, payload: VisualEffectPayload.Effect) -> void:
		if kind == VisualAction.KIND_FLOATING_TEXT:
			floating_texts.append((payload as VisualEffectPayload.FloatingText).text)
	)
	director.load_playback(record)

	_run_frame(director, [{
		"kind": "regeneration",
		"target_actor_id": "hero_1",
		"resource": "hp",
		"amount": 10.0,
		"actual_amount": 7.0,
		"source": "general_passive",
	}], "regen_7")

	var state := _get_state(director)
	if not is_equal_approx(state.target_hp, 57.0):
		_fail("target_hp after regen should be 57, got %.2f" % state.target_hp)
		return
	if floating_texts != ["+7"]:
		_fail("expected one +7 floating text, got %s" % str(floating_texts))
		return

	_run_frame(director, [{
		"kind": "regeneration",
		"target_actor_id": "hero_1",
		"resource": "hp",
		"amount": 10.0,
		"actual_amount": 0.0,
		"source": "general_passive",
	}], "regen_0")

	state = _get_state(director)
	if not is_equal_approx(state.target_hp, 57.0):
		_fail("zero actual regen should not change target_hp, got %.2f" % state.target_hp)
		return
	if floating_texts != ["+7"]:
		_fail("zero actual regen should not create floating text, got %s" % str(floating_texts))
		return

	print("SMOKE_TEST_RESULT: PASS - regeneration updates frontend HP state without heal event")
	get_tree().quit(0)


## 一趟 = 一个逻辑帧的事件 + STEP_MS 表演时间,与 ReplayDirector 帧时钟喂 pump 的口径相同
func _run_frame(director: VisualDirector, events: Array[Dictionary], tag: String) -> void:
	director.pump(STEP_MS, events)
	print("  [frame %s] pumped %d events" % [tag, events.size()])


func _get_state(director: VisualDirector) -> ActorVisualState:
	return director.get_actors_snapshot()["hero_1"] as ActorVisualState


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - " + reason)
	get_tree().quit(1)
