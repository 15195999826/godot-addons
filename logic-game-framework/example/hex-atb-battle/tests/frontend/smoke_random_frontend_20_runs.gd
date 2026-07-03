## Smoke test: demo_random_frontend 连续 20 轮随机战斗 + replay 语义分析。
##
## 这个测试不是只看 playback 是否结束。每轮还会读取 replay，检查硬不变量
## (damage / heal / shield / death / actor count) 和 active skill 执行后的可见证据。
extends Node


const MAIN_SCENE := "res://addons/logic-game-framework/example/hex-atb-battle/frontend/demo_random_frontend.tscn"
const TEAM_SIZE := 3
const PASSIVES_PER_ACTOR := 1
const PLAYBACK_SPEED := 400.0
const PLAYBACK_TIMEOUT_MS := 20000
const EFFECT_WINDOW_FRAMES := 60
const EPSILON := 0.05

const SEEDS := [
	424242,
	531001,
	541003,
	551009,
	561019,
	571031,
	581047,
	591061,
	601067,
	611083,
	621097,
	631109,
	641129,
	651143,
	661151,
	671159,
	681173,
	691181,
	701191,
	711199,
]

const DAMAGE_SKILLS := {
	"skill_strike": true,
	"skill_execute": true,
	"skill_crushing_blow": true,
	"skill_swift_strike": true,
	"skill_precise_shot": true,
	"skill_fireball": true,
	"skill_chain_lightning": true,
	"skill_wall_breaker": true,
	"skill_knockback_punch": true,
	"skill_lifesteal": true,
	"skill_piercing_line": true,
	"skill_grid_cone": true,
	"skill_angle_cone": true,
}

const BUFF_SKILLS := {
	"skill_poison": "buff_poison",
	"skill_ward": "buff_ward",
	"skill_physical_shield": "buff_physical_shield",
	"skill_magical_shield": "buff_magical_shield",
	"skill_surge": "buff_surge",
	"skill_expose": "buff_expose",
	"skill_stun": "buff_stun",
	"skill_silence": "buff_silence",
	"skill_break": "buff_break",
}

const EXPECTED_FAILURE_REASON_PARTS := [
	"cant_act",
	"cant_use_skill",
	"冷却",
	"cooldown",
]

const NEGATIVE_BUFFS := {
	"buff_poison": true,
	"buff_expose": true,
	"buff_stun": true,
	"buff_silence": true,
	"buff_break": true,
}


var _packed: PackedScene
var _rows: Array[Dictionary] = []
var _aggregate_event_counts: Dictionary = {}
var _aggregate_skill_counts: Dictionary = {}
var _aggregate_loaded_skill_counts: Dictionary = {}
var _aggregate_failure_reasons: Dictionary = {}
var _aggregate_warnings: Dictionary = {}
var _aggregate_late_effect_skips: Dictionary = {}
var _hard_failures: Array[String] = []


func _ready() -> void:
	print("=== Smoke Test: Random Frontend 20 Runs ===")
	print("Scene: %s" % MAIN_SCENE)
	print("Runs: %d, Team Size: %d, Passives: %d" % [SEEDS.size(), TEAM_SIZE, PASSIVES_PER_ACTOR])
	print("")

	Log.set_level(Log.LogLevel.WARNING)
	_packed = load(MAIN_SCENE)
	if _packed == null:
		_fail("Failed to load " + MAIN_SCENE)
		return

	for seed_value in SEEDS:
		var seed := int(seed_value)
		var row := await _run_one(seed)
		_rows.append(row)
		_print_run_row(row)
		if int(row.get("failures", 0)) > 0:
			_hard_failures.append("seed=%d failures=%s" % [seed, str(row.get("failure_details", []))])

	_print_aggregate()
	if not _hard_failures.is_empty():
		_fail("20-run random frontend found hard failures: %s" % str(_hard_failures))
		return

	print("SMOKE_TEST_RESULT: PASS - random frontend 20 runs completed")
	GameWorld.destroy()
	get_tree().quit(0)


func _run_one(seed: int) -> Dictionary:
	var report := _new_report(seed)
	var main_scene := _packed.instantiate()
	if main_scene == null:
		_report_failure(report, "Failed to instantiate main scene")
		return _report_to_row(report)

	add_child(main_scene)
	await get_tree().process_frame

	if not main_scene.has_method("set_random_config"):
		_report_failure(report, "Random scene missing set_random_config")
		await _cleanup_scene(main_scene)
		return _report_to_row(report)
	main_scene.call("set_random_config", seed, TEAM_SIZE, PASSIVES_PER_ACTOR)

	var world_view := main_scene.get_node_or_null("WorldView") as FrontendWorldView
	if world_view == null:
		_report_failure(report, "WorldView node not found")
		await _cleanup_scene(main_scene)
		return _report_to_row(report)
	var animator := main_scene.get_node_or_null("BattleAnimator") as FrontendBattleAnimator
	if animator == null:
		_report_failure(report, "BattleAnimator node not found")
		await _cleanup_scene(main_scene)
		return _report_to_row(report)

	main_scene.call("_on_start_battle_button_pressed")

	var summary: Dictionary = main_scene.call("get_random_battle_summary") as Dictionary
	var replay: Dictionary = main_scene.call("get_random_replay_data") as Dictionary
	_analyze_summary(summary, report)
	_analyze_replay(replay, report)
	report["frames"] = animator.get_total_frames()
	report["unit_views"] = world_view.get_unit_view_count()
	if animator.get_total_frames() <= 0:
		_report_failure(report, "Animator total_frames <= 0")
	if world_view.get_unit_view_count() == 0:
		_report_failure(report, "WorldView has no unit views")

	if report.get("failures", []).is_empty():
		await _play_and_assert(main_scene, world_view, animator, report)

	await _cleanup_scene(main_scene)
	return _report_to_row(report)


func _new_report(seed: int) -> Dictionary:
	return {
		"seed": seed,
		"result": "",
		"frames": 0,
		"initial_actors": 0,
		"unit_views": 0,
		"event_counts": {},
		"skill_counts": {},
		"loaded_skill_counts": {},
		"failure_reasons": {},
		"warnings": [],
		"late_effect_skips": {},
		"failures": [],
		"reconcile": "",
	}


func _analyze_summary(summary: Dictionary, report: Dictionary) -> void:
	if summary.is_empty():
		_report_failure(report, "random battle summary is empty")
		return

	var seed := int(report.get("seed", 0))
	if int(summary.get("seed", 0)) != seed:
		_report_failure(report, "resolved seed mismatch: %s" % str(summary.get("seed", null)))

	var result := str(summary.get("result", ""))
	report["result"] = result
	if result == "" or result == "timeout":
		_report_failure(report, "battle result is invalid: %s" % result)

	var actors: Array = summary.get("actors", []) as Array
	if actors.size() != TEAM_SIZE * 2:
		_report_failure(report, "loadout actor count=%d expected=%d" % [actors.size(), TEAM_SIZE * 2])

	for item_variant in actors:
		var item := item_variant as Dictionary
		var actor_name := str(item.get("actor_name", ""))
		if not actor_name.begins_with("左方 ") and not actor_name.begins_with("右方 "):
			_report_failure(report, "actor name is not neutral: %s" % actor_name)
		var skill_id := str(item.get("active_skill", ""))
		if skill_id.is_empty():
			_report_failure(report, "actor %s missing active_skill" % str(item.get("actor_id", "")))
			continue
		_increment(report["loaded_skill_counts"], skill_id)
		_increment(_aggregate_loaded_skill_counts, skill_id)


func _analyze_replay(replay: Dictionary, report: Dictionary) -> void:
	if replay.is_empty():
		_report_failure(report, "replay is empty")
		return

	var meta: Dictionary = replay.get("meta", {}) as Dictionary
	var result := str(meta.get("result", ""))
	if result == "" or result == "timeout":
		_report_failure(report, "replay result is invalid: %s" % result)
	if int(meta.get("totalFrames", 0)) <= 0:
		_report_failure(report, "replay totalFrames <= 0")

	var snapshot_dict: Dictionary = replay.get("world_snapshot", {}) as Dictionary
	var initial_actors: Array = snapshot_dict.get("actors", []) as Array
	report["initial_actors"] = initial_actors.size()
	if initial_actors.size() != TEAM_SIZE * 2:
		_report_failure(report, "world_snapshot.actors=%d expected=%d" % [initial_actors.size(), TEAM_SIZE * 2])
	_check_initial_actor_names(initial_actors, report)

	var events := _flatten_events(replay)
	if events.is_empty():
		_report_failure(report, "replay timeline has no events")
		return

	_count_events(events, report)
	_check_event_invariants(events, report)
	_check_skill_effects(events, report)


func _check_initial_actor_names(initial_actors: Array, report: Dictionary) -> void:
	for actor_variant in initial_actors:
		var actor := actor_variant as Dictionary
		var display_name := str(actor.get("displayName", ""))
		if not display_name.begins_with("左方 ") and not display_name.begins_with("右方 "):
			_report_failure(report, "initial actor displayName is not neutral: %s" % display_name)


func _flatten_events(replay: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var timeline: Array = replay.get("timeline", []) as Array
	for frame_variant in timeline:
		var frame_data := frame_variant as Dictionary
		var frame := int(frame_data.get("frame", 0))
		var events: Array = frame_data.get("events", []) as Array
		for event_variant in events:
			var event := event_variant as Dictionary
			var copy := event.duplicate(true)
			copy["_frame"] = frame
			result.append(copy)
	return result


func _count_events(events: Array[Dictionary], report: Dictionary) -> void:
	for event in events:
		var kind := _kind(event)
		_increment(report["event_counts"], kind)
		_increment(_aggregate_event_counts, kind)
		if kind == GameEvent.ABILITY_ACTIVATE_FAILED_EVENT:
			var reason := str(event.get("reason", ""))
			var key := "%s|%s" % [str(event.get("abilityConfigId", "")), reason]
			_increment(report["failure_reasons"], key)
			_increment(_aggregate_failure_reasons, key)


func _check_event_invariants(events: Array[Dictionary], report: Dictionary) -> void:
	var deaths := {}
	for event in events:
		match _kind(event):
			"damage":
				_check_damage_event(event, report)
			"heal":
				var heal_amount := float(event.get("heal_amount", -1.0))
				if heal_amount <= 0.0:
					_report_failure(report, "heal_amount must be > 0 at frame %d: %.2f" % [
						int(event.get("_frame", -1)), heal_amount
					])
			"regeneration":
				var amount := float(event.get("amount", -1.0))
				var actual := float(event.get("actual_amount", -1.0))
				if amount < -EPSILON or actual < -EPSILON or actual > amount + EPSILON:
					_report_failure(report, "invalid regeneration at frame %d: amount=%.2f actual=%.2f" % [
						int(event.get("_frame", -1)), amount, actual
					])
			"death":
				var actor_id := str(event.get("actor_id", ""))
				if deaths.has(actor_id):
					_report_failure(report, "duplicate death event for actor %s" % actor_id)
				deaths[actor_id] = true
			GameEvent.ABILITY_ACTIVATE_FAILED_EVENT:
				_check_activate_failed(event, report)


func _check_damage_event(event: Dictionary, report: Dictionary) -> void:
	var frame := int(event.get("_frame", -1))
	var damage := float(event.get("damage", -1.0))
	var actual := float(event.get("actual_life_damage", damage))
	var absorbed := float(event.get("shield_absorbed", 0.0))
	if damage < -EPSILON or actual < -EPSILON or absorbed < -EPSILON:
		_report_failure(report, "negative damage values at frame %d: damage=%.2f actual=%.2f absorbed=%.2f" % [
			frame, damage, actual, absorbed
		])
	if actual > damage + EPSILON or absorbed > damage + EPSILON:
		_report_failure(report, "damage parts exceed damage at frame %d: damage=%.2f actual=%.2f absorbed=%.2f" % [
			frame, damage, actual, absorbed
		])
	if absf((actual + absorbed) - damage) > EPSILON:
		_report_failure(report, "actual_life_damage + shield_absorbed != damage at frame %d: damage=%.2f actual=%.2f absorbed=%.2f" % [
			frame, damage, actual, absorbed
		])


func _check_activate_failed(event: Dictionary, report: Dictionary) -> void:
	var reason := str(event.get("reason", ""))
	if reason.is_empty():
		_report_failure(report, "abilityActivateFailed has empty reason at frame %d" % int(event.get("_frame", -1)))
		return
	for part in EXPECTED_FAILURE_REASON_PARTS:
		if reason.contains(str(part)):
			return
	_report_warning(report, "unexpected abilityActivateFailed reason: %s / %s" % [
		str(event.get("abilityConfigId", "")),
		reason,
	])


func _check_skill_effects(events: Array[Dictionary], report: Dictionary) -> void:
	var ability_config_by_instance := _build_ability_config_by_instance(events)
	var max_frame := _max_event_frame(events)
	for event in events:
		if _kind(event) != GameEvent.EXECUTION_ACTIVATED_EVENT:
			continue
		var skill_id := str(event.get("abilityConfigId", ""))
		if not skill_id.begins_with("skill_"):
			continue
		var source_id := str(event.get("actorId", ""))
		var frame := int(event.get("_frame", 0))
		_increment(report["skill_counts"], skill_id)
		_increment(_aggregate_skill_counts, skill_id)

		var window := _events_between(events, frame, frame + EFFECT_WINDOW_FRAMES)
		if DAMAGE_SKILLS.has(skill_id):
			if not _has_damage_from(window, source_id):
				_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d produced no source damage in %d frames" % [
					skill_id, frame, EFFECT_WINDOW_FRAMES
				])
		elif BUFF_SKILLS.has(skill_id):
			var buff_id := str(BUFF_SKILLS[skill_id])
			if not _has_ability_granted(window, buff_id):
				_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d did not grant %s in %d frames" % [
					skill_id, frame, buff_id, EFFECT_WINDOW_FRAMES
				])
		else:
			match skill_id:
				"skill_holy_heal":
					if not _has_heal_from(window, source_id):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d produced no heal" % [skill_id, frame])
				"skill_summon_totem":
					if not _has_spawned_actor_kind(window, "Totem"):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d spawned no Totem" % [skill_id, frame])
				"skill_spawn_fire_tile":
					if not _has_spawned_actor_kind(window, "fire_tile"):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d spawned no fire_tile" % [skill_id, frame])
				"skill_swap":
					if not _has_swap_displacement(window, source_id):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d produced no paired swap displacement" % [skill_id, frame])
				"skill_cleanse":
					if not _has_negative_buff_removed(window, ability_config_by_instance):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d removed no known negative buff" % [skill_id, frame])
				"skill_stance":
					if not _has_stance_tag_change(window, source_id):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d produced no stance tag change" % [skill_id, frame])
				"skill_shadow_step":
					if not _has_damage_from(window, source_id) and not _has_displacement_kind(window, source_id, "teleport"):
						_report_missing_effect(report, skill_id, frame, max_frame, "%s execution at frame %d neither damaged nor teleported" % [skill_id, frame])
				_:
					_report_warning(report, "unmapped skill execution: %s at frame %d" % [skill_id, frame])


func _max_event_frame(events: Array[Dictionary]) -> int:
	var max_frame := 0
	for event in events:
		max_frame = maxi(max_frame, int(event.get("_frame", 0)))
	return max_frame


func _report_missing_effect(
	report: Dictionary,
	skill_id: String,
	frame: int,
	max_frame: int,
	message: String,
) -> void:
	if frame + EFFECT_WINDOW_FRAMES > max_frame:
		_increment(report["late_effect_skips"], skill_id)
		_increment(_aggregate_late_effect_skips, skill_id)
		return
	_report_warning(report, message)


func _build_ability_config_by_instance(events: Array[Dictionary]) -> Dictionary:
	var result := {}
	for event in events:
		if _kind(event) != GameEvent.ABILITY_GRANTED_EVENT:
			continue
		var ability: Dictionary = event.get("ability", {}) as Dictionary
		var instance_id := str(ability.get("instanceId", ability.get("id", "")))
		if instance_id.is_empty():
			continue
		result[instance_id] = str(ability.get("configId", ""))
	return result


func _events_between(events: Array[Dictionary], min_frame: int, max_frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		var frame := int(event.get("_frame", 0))
		if frame >= min_frame and frame <= max_frame:
			result.append(event)
	return result


func _has_damage_from(events: Array[Dictionary], source_id: String) -> bool:
	for event in events:
		if _kind(event) == "damage" and str(event.get("source_actor_id", "")) == source_id:
			if float(event.get("damage", 0.0)) > EPSILON:
				return true
	return false


func _has_heal_from(events: Array[Dictionary], source_id: String) -> bool:
	for event in events:
		if _kind(event) == "heal" and str(event.get("source_actor_id", "")) == source_id:
			if float(event.get("heal_amount", 0.0)) > EPSILON:
				return true
	return false


func _has_ability_granted(events: Array[Dictionary], config_id: String) -> bool:
	for event in events:
		if _kind(event) != GameEvent.ABILITY_GRANTED_EVENT:
			continue
		var ability: Dictionary = event.get("ability", {}) as Dictionary
		if str(ability.get("configId", "")) == config_id:
			return true
	return false


func _has_spawned_actor_kind(events: Array[Dictionary], expected_kind: String) -> bool:
	for event in events:
		if _kind(event) != GameEvent.ACTOR_SPAWNED_EVENT:
			continue
		var actor: Dictionary = event.get("actor", {}) as Dictionary
		if str(actor.get("configId", "")) == expected_kind:
			return true
		if str(actor.get("displayName", "")) == expected_kind:
			return true
	return false


func _has_swap_displacement(events: Array[Dictionary], source_id: String) -> bool:
	var swap_counts := {}
	for event in events:
		if _kind(event) != "actor_displaced":
			continue
		if str(event.get("source_actor_id", "")) != source_id:
			continue
		if str(event.get("displacement_kind", "")) != "swap":
			continue
		var swap_id := str(event.get("swap_id", ""))
		_increment(swap_counts, swap_id)
	for swap_id in swap_counts.keys():
		if int(swap_counts[swap_id]) >= 2:
			return true
	return false


func _has_negative_buff_removed(events: Array[Dictionary], ability_config_by_instance: Dictionary) -> bool:
	for event in events:
		if _kind(event) != GameEvent.ABILITY_REMOVED_EVENT:
			continue
		var ability_id := str(event.get("abilityInstanceId", ""))
		var config_id := str(ability_config_by_instance.get(ability_id, ""))
		if NEGATIVE_BUFFS.has(config_id):
			return true
	return false


func _has_stance_tag_change(events: Array[Dictionary], source_id: String) -> bool:
	for event in events:
		if _kind(event) != GameEvent.TAG_CHANGED_EVENT:
			continue
		if str(event.get("actorId", "")) != source_id:
			continue
		if str(event.get("tag", "")).begins_with("stance:skill_stance:"):
			return true
	return false


func _has_displacement_kind(events: Array[Dictionary], source_id: String, kind: String) -> bool:
	for event in events:
		if _kind(event) == "actor_displaced" \
				and str(event.get("source_actor_id", "")) == source_id \
				and str(event.get("displacement_kind", "")) == kind:
			return true
	return false


func _play_and_assert(
	main_scene: Node,
	world_view: FrontendWorldView,
	animator: FrontendBattleAnimator,
	report: Dictionary,
) -> void:
	var main_reconcile_callback := Callable(main_scene, "_on_playback_ended")
	if animator.playback_ended.is_connected(main_reconcile_callback):
		animator.playback_ended.disconnect(main_reconcile_callback)

	animator.set_speed(PLAYBACK_SPEED)
	animator.play()
	var started_at := Time.get_ticks_msec()
	while not animator.is_ended() and Time.get_ticks_msec() - started_at < PLAYBACK_TIMEOUT_MS:
		await get_tree().process_frame

	if not animator.is_ended():
		_report_failure(report, "playback timeout current_frame=%d/%d" % [
			animator.get_current_frame(),
			animator.get_total_frames(),
		])
		return

	var current_frame := animator.get_current_frame()
	var total_frames := animator.get_total_frames()
	if current_frame < total_frames:
		_report_failure(report, "current_frame (%d) < total_frames (%d)" % [current_frame, total_frames])

	if world_view.get_unit_view_count() == 0:
		_report_failure(report, "WorldView has no unit views after playback")

	var snapshot := animator.get_actors_snapshot()
	if snapshot.is_empty():
		_report_failure(report, "animator.get_actors_snapshot() empty after playback")
	for actor_id: String in snapshot.keys():
		var st: FrontendActorRenderState = snapshot[actor_id]
		if st.visual_hp < -EPSILON or st.visual_hp > st.max_hp + EPSILON:
			_report_failure(report, "Actor %s hp out of range: %.2f / %.2f" % [
				actor_id, st.visual_hp, st.max_hp
			])

	var final_state: Dictionary = main_scene.call("get_final_state") as Dictionary
	var reconcile_report := await HexBattleViewLogicReconciler.reconcile(
		final_state,
		animator,
		world_view,
		get_tree()
	)
	if reconcile_report.skipped:
		report["reconcile"] = "SKIPPED:%s" % reconcile_report.skip_reason
	elif not reconcile_report.passed:
		_report_failure(report, "view-logic reconcile: %s" % reconcile_report.to_human_string())
	else:
		report["reconcile"] = "PASS:%d" % reconcile_report.actor_count


func _cleanup_scene(main_scene: Node) -> void:
	if main_scene != null:
		remove_child(main_scene)
		main_scene.queue_free()
	GameWorld.destroy()
	await get_tree().process_frame


func _report_to_row(report: Dictionary) -> Dictionary:
	return {
		"seed": int(report.get("seed", 0)),
		"result": str(report.get("result", "")),
		"frames": int(report.get("frames", 0)),
		"initial_actors": int(report.get("initial_actors", 0)),
		"unit_views": int(report.get("unit_views", 0)),
		"executed_skills": (report.get("skill_counts", {}) as Dictionary).size(),
		"warnings": (report.get("warnings", []) as Array).size(),
		"late_effect_skips": _sum_counts(report.get("late_effect_skips", {}) as Dictionary),
		"failures": (report.get("failures", []) as Array).size(),
		"failure_details": (report.get("failures", []) as Array).duplicate(),
		"warning_details": (report.get("warnings", []) as Array).duplicate(),
		"reconcile": str(report.get("reconcile", "")),
	}


func _print_run_row(row: Dictionary) -> void:
	print("RANDOM_RUN_RESULT seed=%d result=%s frames=%d actors=%d unitViews=%d skillKinds=%d warnings=%d lateSkips=%d failures=%d reconcile=%s" % [
		int(row.get("seed", 0)),
		str(row.get("result", "")),
		int(row.get("frames", 0)),
		int(row.get("initial_actors", 0)),
		int(row.get("unit_views", 0)),
		int(row.get("executed_skills", 0)),
		int(row.get("warnings", 0)),
		int(row.get("late_effect_skips", 0)),
		int(row.get("failures", 0)),
		str(row.get("reconcile", "")),
	])
	var warnings: Array = row.get("warning_details", []) as Array
	for warning_variant in warnings:
		var warning := str(warning_variant)
		_increment(_aggregate_warnings, warning)
		print("  WARN %s" % warning)
	var failures: Array = row.get("failure_details", []) as Array
	for failure_variant in failures:
		print("  FAIL %s" % str(failure_variant))


func _print_aggregate() -> void:
	print("")
	print("=== Random 20-run Aggregate ===")
	print("Loaded primary skills: %s" % _format_counts(_aggregate_loaded_skill_counts))
	print("Executed active skills: %s" % _format_counts(_aggregate_skill_counts))
	print("Event counts: %s" % _format_counts(_aggregate_event_counts))
	if _aggregate_failure_reasons.is_empty():
		print("Activation failures: none")
	else:
		print("Activation failures: %s" % _format_counts(_aggregate_failure_reasons))
	if _aggregate_warnings.is_empty():
		print("Semantic warnings: none")
	else:
		print("Semantic warnings: %s" % _format_counts(_aggregate_warnings))
	if _aggregate_late_effect_skips.is_empty():
		print("Late effect skips: none")
	else:
		print("Late effect skips: %s" % _format_counts(_aggregate_late_effect_skips))


func _format_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "{}"
	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%d" % [str(key), int(counts[key])])
	return "{%s}" % ", ".join(parts)


func _sum_counts(counts: Dictionary) -> int:
	var total := 0
	for key in counts.keys():
		total += int(counts[key])
	return total


func _report_warning(report: Dictionary, message: String) -> void:
	var warnings: Array = report.get("warnings", []) as Array
	warnings.append(message)


func _report_failure(report: Dictionary, message: String) -> void:
	var failures: Array = report.get("failures", []) as Array
	failures.append(message)


func _increment(counts: Dictionary, key: String, amount: int = 1) -> void:
	counts[key] = int(counts.get(key, 0)) + amount


func _kind(event: Dictionary) -> String:
	return str(event.get("kind", ""))


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
