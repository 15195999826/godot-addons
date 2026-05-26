## Phase B2 · Break · Overlap (multi-source 引用计数)
##
## 多个 Break 重叠时, 每个 source 独立贡献 disabled_sources Set;
## 单一 Break 到期不能恢复 passive — 必须最后一个 Break 移除后 passive 才恢复。
##
## 时序 (Break A 短 1000ms + Break B 长 3000ms, 重叠区间 500~1300):
##   t=0     enemy_0 cast Break A caster (dur=1000ms) → HIT @ t=300 → BreakA grant
##                                                       caster Thorn disabled (sources={A})
##   t=500   enemy_1 cast Break B caster (dur=3000ms) → HIT @ t=800 → BreakB grant
##                                                       caster Thorn disabled (sources={A, B})
##   t=1300  Break A expire → BreakA remove → caster Thorn sources={B}, 仍 disabled
##   t=2000  enemy_0 cast Strike caster → caster 受 damage; Thorn 仍 disabled (B 在), 无反伤
##   t=3800  Break B expire → BreakB remove → caster Thorn sources={}, 恢复
##   t=4500  enemy_0 cast Strike caster → caster 受 damage; Thorn 恢复, 反伤 2 PURE
##
## 关键断言:
## - 2 个独立 BreakBuff 实例 (id 不同)
## - 短 Break 先 remove
## - 期间 (短 break 已到期 但 长 break 在) Strike 不触发反伤 (passive 仍 disabled)
## - 长 Break expire 后 Strike 触发反伤 (passive 恢复)
class_name BreakOverlapScenario
extends SkillScenario


func get_name() -> String:
	return "Break overlap (refcount: passive recovers only after LAST break removed)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 3000, "atk": 30},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 3000, "atk": 50},
			{"class": "WARRIOR", "pos": [0, 1], "hp": 3000, "atk": 50},
		],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleThorn.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [
		# Break A (短 1000ms) by enemy_0
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(1000.0),
			"target": "caster",
			"time_ms": 0,
		},
		# Break B (长 3000ms) by enemy_1
		{
			"caster": "enemy_1",
			"skill": HexBattleBreak.create_config(3000.0),
			"target": "caster",
			"time_ms": 500,
		},
		# t=2000 区间: A 已到期 (1300 < 2000), B 仍在 (800+3000=3800 > 2000)
		# enemy_0 Strike caster → 不该反伤 (B 仍 disable Thorn)
		{
			"caster": "enemy_0",
			"skill": HexBattleStrike.ABILITY,
			"target": "caster",
			"time_ms": 2000,
		},
		# t=4500 区间: B 已到期 (3800 < 4500), Thorn 恢复
		# enemy_0 Strike caster → 应反伤
		{
			"caster": "enemy_0",
			"skill": HexBattleStrike.ABILITY,
			"target": "caster",
			"time_ms": 4500,
		},
	]


func get_max_ticks() -> int:
	return 70


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. caster 上 2 个独立 BreakBuff grant
	var break_grants: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != HexBattleBreakBuff.CONFIG_ID:
			continue
		break_grants.append(e)
	ctx.assert_eq(break_grants.size(), 2,
		"Expect 2 independent BreakBuff grants on caster (got %d)" % break_grants.size())
	if break_grants.size() != 2:
		return

	# break_grants[0] = Break A (short), break_grants[1] = Break B (long)
	var inst_a := str((break_grants[0].get("ability", {}) as Dictionary).get("id", ""))
	var inst_b := str((break_grants[1].get("ability", {}) as Dictionary).get("id", ""))
	ctx.assert_true(inst_a != inst_b,
		"Break A id != Break B id (independent instances)")

	# 2. 2 个 remove (短先, 长后), 拿到 last_break_remove_frame (= 长 Break B remove)
	var break_removes: Array = []
	var remove_b_frame := -1  # 长 Break B remove frame
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var inst := str(e.get("abilityInstanceId", ""))
		if inst == inst_a or inst == inst_b:
			break_removes.append(e)
		if inst == inst_b:
			remove_b_frame = int(e.get("replay_frame", -1))
	ctx.assert_eq(break_removes.size(), 2,
		"Expect both Breaks to expire (got %d removes)" % break_removes.size())
	ctx.assert_true(remove_b_frame > 0,
		"Long Break B should expire (got frame %d)" % remove_b_frame)

	# 3. enemy_0 → caster 的 Strike 主伤害事件 = 2 (期内 + 期后)
	var all_strikes := ctx.filter_damage_events({
		"source_actor_id": ctx.enemy_id(0),
		"target_actor_id": ctx.caster_id,
		"is_reflected": false,
	})
	var main_strikes: Array = []
	for e in all_strikes:
		if (e.get("damage", 0.0) as float) > 30.0:
			main_strikes.append(e)
	ctx.assert_eq(main_strikes.size(), 2,
		"Expect 2 enemy_0 Strike main hits on caster got %d" % main_strikes.size())

	# 4. Thorn 反伤事件: 1 (期后 strike 主; 期内 strike 不反伤)
	#    关键 (multi-source refcount 契约): 每个 reflect frame 必须 > Break B remove frame,
	#    验证 短 Break A 到期不会过早恢复 Thorn (refcount = 1, B 仍在)。
	var reflects := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
		"is_reflected": true,
	})
	ctx.assert_eq(reflects.size(), 1,
		"Expect 1 Thorn reflect only after BOTH breaks removed; got %d" % reflects.size())
	for r in reflects:
		var frame := int(r.get("replay_frame", -1))
		ctx.assert_true(frame > remove_b_frame,
			"Thorn reflect must fire AFTER long Break B remove (refcount semantics): reflect frame %d > remove_b_frame %d" % [
				frame, remove_b_frame
			])

	# 5. 期末 caster 上无 BreakBuff
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleBreakBuff.CONFIG_ID,
		"All BreakBuffs revoked after duration"
	)
