## Smoke test: HexBattleSkillScenarioHarness.run_with_actions 时间轴调度
##
## 目标: 验证 actions 的 time_ms 字段确实推迟施法 ——
##   caster t=0   Strike  → enemy_0 (基线: 立即开打, 第一帧 ~3 帧后命中)
##   enemy_0 t=500 Strike → caster (延迟 500ms 才施法, 命中至少要再隔 4 帧)
##
## 断言:
##   1. 两条 damage 事件都存在
##   2. caster 那条 frame < enemy_0 那条 (顺序对)
##   3. 两条 frame 至少差 4 (≈ 400ms+, 证明 500ms 调度真起作用了)
##
## 不覆盖: 具体伤害数值 (那是 strike 本身的契约, 由 fireball_scenario 等覆盖)
##
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: SkillPreview timeline scheduling ===")

	var scene_config := {
		"map": {"radius": 4, "orientation": "flat", "size": 1.0},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000.0},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000.0}],
	}

	var actions: Array[Dictionary] = [
		{"caster": "caster",  "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0},
		{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster",  "time_ms": 500},
	]

	var result := HexBattleSkillScenarioHarness.run_with_actions(scene_config, actions, 100)

	if not result.get("success", false):
		_fail("run_with_actions failed: errors=%s" % str(result.get("errors", [])))
		return

	var caster_id: String = str(result.get("caster_id", ""))
	var enemy_ids: Array = result.get("enemy_ids", [])
	if caster_id == "" or enemy_ids.is_empty():
		_fail("Missing caster/enemy ids in result: %s" % str(result))
		return
	var enemy_id: String = str(enemy_ids[0])

	var replay: Dictionary = result.get("replay", {}) as Dictionary
	if replay.is_empty():
		_fail("Empty replay")
		return

	var caster_dmg_frame := -1
	var enemy_dmg_frame := -1
	for frame_data in replay.get("timeline", []) as Array:
		if not (frame_data is Dictionary):
			continue
		var frame := int((frame_data as Dictionary).get("frame", 0))
		for ev in (frame_data as Dictionary).get("events", []) as Array:
			if not (ev is Dictionary):
				continue
			if str((ev as Dictionary).get("kind", "")) != "damage":
				continue
			var target := str((ev as Dictionary).get("target_actor_id", ""))
			if target == enemy_id and caster_dmg_frame < 0:
				caster_dmg_frame = frame
			elif target == caster_id and enemy_dmg_frame < 0:
				enemy_dmg_frame = frame

	if caster_dmg_frame < 0:
		_fail("No damage event to enemy_0 (caster t=0 Strike never landed)")
		return
	if enemy_dmg_frame < 0:
		_fail("No damage event to caster (enemy_0 t=500 Strike never landed)")
		return

	if caster_dmg_frame >= enemy_dmg_frame:
		_fail("Order wrong: caster damage frame=%d should be < enemy damage frame=%d"
			% [caster_dmg_frame, enemy_dmg_frame])
		return

	var separation := enemy_dmg_frame - caster_dmg_frame
	if separation < 4:
		_fail("Separation %d frames too small — 500ms delay should yield >=4 frame gap (caster=%d enemy=%d)"
			% [separation, caster_dmg_frame, enemy_dmg_frame])
		return

	_pass("caster damage @ frame %d; enemy damage @ frame %d; separation = %d frames"
		% [caster_dmg_frame, enemy_dmg_frame, separation])


func _pass(reason: String) -> void:
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
