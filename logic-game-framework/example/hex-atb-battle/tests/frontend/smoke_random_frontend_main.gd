## Smoke test: 随机技能 frontend demo 完整链路。
##
## 覆盖 demo_random_frontend.tscn: 固定 seed 随机组装 loadout, 跑完整 logic battle,
## 再用 BattleAnimator 播放到结束。它不替代 demo_frontend 基线, 只作为随机技能集成面。
extends Node


const MAIN_SCENE := "res://addons/logic-game-framework/example/hex-atb-battle/frontend/demo_random_frontend.tscn"
const TIMEOUT_SEC := 45.0
const PLAYBACK_SPEED := 200.0
const FIXED_SEED := 651143
const TEAM_SIZE := 3
const PASSIVES_PER_ACTOR := 1


var _main_scene: Node
var _world_view: FrontendWorldView
var _animator: FrontendBattleAnimator
var _mid_spawned_actor_ids: Array[String] = []
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	print("=== Smoke Test: Random Frontend Main Scene Flow ===")
	print("Scene: %s" % MAIN_SCENE)
	print("Seed: %d, Team Size: %d, Passives: %d" % [FIXED_SEED, TEAM_SIZE, PASSIVES_PER_ACTOR])
	print("")

	Log.set_level(Log.LogLevel.WARNING)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("Failed to load " + MAIN_SCENE)
		return
	_main_scene = packed.instantiate()
	if _main_scene == null:
		_fail("Failed to instantiate main scene")
		return
	add_child(_main_scene)

	await get_tree().process_frame

	if not _main_scene.has_method("set_random_config"):
		_fail("Random scene missing set_random_config")
		return
	_main_scene.call("set_random_config", FIXED_SEED, TEAM_SIZE, PASSIVES_PER_ACTOR)

	_world_view = _main_scene.get_node_or_null("WorldView") as FrontendWorldView
	if _world_view == null:
		_fail("WorldView node not found under Main")
		return
	_animator = _main_scene.get_node_or_null("BattleAnimator") as FrontendBattleAnimator
	if _animator == null:
		_fail("BattleAnimator node not found under Main")
		return

	print("Step 1: Triggering random battle...")
	_main_scene.call("_on_start_battle_button_pressed")

	var summary: Dictionary = _main_scene.call("get_random_battle_summary") as Dictionary
	if summary.is_empty():
		_fail("random battle summary is empty")
		return
	_assert_summary(summary)
	if _finished:
		return

	var replay: Dictionary = _main_scene.call("get_random_replay_data") as Dictionary
	_mid_spawned_actor_ids = _collect_mid_spawned_actor_ids(replay)
	if _mid_spawned_actor_ids.is_empty():
		_fail("fixed seed must produce mid-spawn actors for reset coverage")
		return
	if not _has_mid_spawned_actor_config(replay, "fire_tile"):
		_fail("fixed seed must spawn fire_tile for reset coverage")
		return
	if not _assert_mid_spawned_views_hidden("loaded frame 0"):
		return

	var total := _animator.get_total_frames()
	if total <= 0:
		_fail("Animator started but total_frames=%d (expected > 0)" % total)
		return
	var unit_count := _world_view.get_unit_view_count()
	if unit_count == 0:
		_fail("WorldView has no unit views after random battle start")
		return
	print("  + Random battle loaded: %d frames, %d unit views" % [total, unit_count])

	_animator.playback_ended.connect(_on_playback_ended, CONNECT_ONE_SHOT)
	_animator.set_speed(PLAYBACK_SPEED)
	_animator.play()
	print("Step 2: Playing at %.0fx ..." % PLAYBACK_SPEED)


func _process(delta: float) -> void:
	if _finished or _animator == null:
		return
	_elapsed += delta
	if _elapsed >= TIMEOUT_SEC:
		_fail("Playback did not end within %.0fs (current_frame=%d/%d)" % [
			TIMEOUT_SEC,
			_animator.get_current_frame(),
			_animator.get_total_frames(),
		])


func _assert_summary(summary: Dictionary) -> void:
	var result := str(summary.get("result", ""))
	if result == "timeout":
		_fail("random logic battle hit HexBattleProcedure.MAX_TICKS timeout")
		return
	if int(summary.get("seed", 0)) != FIXED_SEED:
		_fail("resolved seed mismatch: %s" % str(summary.get("seed", null)))
		return

	var actors: Array = summary.get("actors", []) as Array
	var expected_actor_count := TEAM_SIZE * 2
	if actors.size() != expected_actor_count:
		_fail("random summary actor count=%d, expected %d" % [actors.size(), expected_actor_count])
		return

	var active_skills := {}
	var granted_passive_count := 0
	for item_variant in actors:
		var item := item_variant as Dictionary
		var active_skill := str(item.get("active_skill", ""))
		if active_skill.is_empty():
			_fail("actor %s missing active_skill in summary" % str(item.get("actor_id", "")))
			return
		active_skills[active_skill] = true
		var passives: Array = item.get("passives", []) as Array
		granted_passive_count += passives.size()

	if active_skills.size() < 3:
		_fail("random loadout should include >=3 unique active skills, got %d" % active_skills.size())
		return
	if granted_passive_count < TEAM_SIZE:
		_fail("expected at least %d extra passive grants, got %d" % [TEAM_SIZE, granted_passive_count])
		return
	print("  + random result    = %s" % result)
	print("  + unique skills    = %d" % active_skills.size())
	print("  + passive grants   = %d" % granted_passive_count)


func _on_playback_ended() -> void:
	if _finished:
		return
	print("Step 3: playback_ended signal received, asserting invariants...")

	if not _animator.is_ended():
		_fail("playback_ended fired but animator.is_ended() is false")
		return

	var cur := _animator.get_current_frame()
	var tot := _animator.get_total_frames()
	if cur < tot:
		_fail("current_frame (%d) < total_frames (%d) at end" % [cur, tot])
		return

	var unit_count := _world_view.get_unit_view_count()
	if unit_count == 0:
		_fail("WorldView has no unit views after playback")
		return

	var snapshot := _animator.get_actors_snapshot()
	if snapshot.is_empty():
		_fail("animator.get_actors_snapshot() empty after playback")
		return
	for actor_id: String in snapshot.keys():
		var st: FrontendActorRenderState = snapshot[actor_id]
		if st.visual_hp < 0.0 or st.visual_hp > st.max_hp + 0.01:
			_fail("Actor %s hp out of range: %.2f / %.2f" % [actor_id, st.visual_hp, st.max_hp])
			return

	var final_state: Dictionary = _main_scene.call("get_final_state")
	var report := await HexBattleViewLogicReconciler.reconcile(
		final_state, _animator, _world_view, get_tree()
	)
	if report.skipped:
		print("  + reconciliation   = SKIPPED (%s)" % report.skip_reason)
	elif not report.passed:
		_fail("view-logic reconcile: %s" % report.to_human_string())
		return
	else:
		print("  + reconciliation   = PASS (%d actors, %d ms settle, drift %.4f)" % [
			report.actor_count, report.settle_time_ms, report.settle_max_drift,
		])

	var reset_ok := await _assert_reset_hides_mid_spawned_views()
	if not reset_ok:
		return

	_pass(tot, cur, unit_count, snapshot.size())


func _pass(total_frames: int, current_frame: int, unit_count: int, actor_count: int) -> void:
	_finished = true
	print("  + is_ended         = true")
	print("  + frame            = %d / %d" % [current_frame, total_frames])
	print("  + unit views       = %d" % unit_count)
	print("  + actor snapshots  = %d" % actor_count)
	print("SMOKE_TEST_RESULT: PASS - random frontend main scene flow ok")
	GameWorld.destroy()
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)


func _collect_mid_spawned_actor_ids(replay: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for frame_variant in replay.get("timeline", []) as Array:
		if not (frame_variant is Dictionary):
			continue
		var frame_data := frame_variant as Dictionary
		for event_variant in frame_data.get("events", []) as Array:
			if not (event_variant is Dictionary):
				continue
			var event := event_variant as Dictionary
			if str(event.get("kind", "")) != GameEvent.ACTOR_SPAWNED_EVENT:
				continue
			var actor_id := str(event.get("actorId", ""))
			if not actor_id.is_empty():
				result.append(actor_id)
	return result


func _has_mid_spawned_actor_config(replay: Dictionary, config_id: String) -> bool:
	for frame_variant in replay.get("timeline", []) as Array:
		if not (frame_variant is Dictionary):
			continue
		var frame_data := frame_variant as Dictionary
		for event_variant in frame_data.get("events", []) as Array:
			if not (event_variant is Dictionary):
				continue
			var event := event_variant as Dictionary
			if str(event.get("kind", "")) != GameEvent.ACTOR_SPAWNED_EVENT:
				continue
			var actor_data: Dictionary = event.get("actor", {}) as Dictionary
			if str(actor_data.get("configId", "")) == config_id:
				return true
	return false


func _assert_reset_hides_mid_spawned_views() -> bool:
	_animator.reset()
	await get_tree().process_frame
	if _animator.get_current_frame() != 0:
		_fail("reset did not return to frame 0")
		return false
	if not _assert_mid_spawned_views_hidden("after reset"):
		return false
	print("  + reset cleanup     = PASS (%d mid-spawn views hidden)" % _mid_spawned_actor_ids.size())
	return true


func _assert_mid_spawned_views_hidden(context: String) -> bool:
	for actor_id in _mid_spawned_actor_ids:
		var world_view_unit := _world_view.get_unit_view(actor_id)
		if world_view_unit != null and world_view_unit.visible:
			_fail("%s left mid-spawn WorldView unit visible: %s" % [context, actor_id])
			return false
		var replay_unit := _find_replay_unit_view(actor_id)
		if replay_unit != null and replay_unit.visible:
			_fail("%s left mid-spawn replay unit visible: %s" % [context, actor_id])
			return false
	return true


func _find_replay_unit_view(actor_id: String) -> FrontendUnitView:
	if _animator == null:
		return null
	var replay_root := _animator.get_node_or_null("ReplayUnitsRoot")
	if replay_root == null:
		return null
	for child in replay_root.get_children():
		var unit_view := child as FrontendUnitView
		if unit_view == null:
			continue
		if unit_view.get_actor_id() == actor_id or unit_view.name == actor_id:
			return unit_view
	return null
