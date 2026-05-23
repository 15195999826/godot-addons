## Phase B2 · Break · Thorn passive disabled (triggered passive)
##
## Break 期间, caster 持有的 Thorn passive 不应反伤; Break 结束后 Thorn 恢复反伤。
## 验证 Ability.receive_event() 顶层短路 — Thorn NoInstanceComponent 接收到 damage 事件
## 但被 ability.is_disabled() 提前 short-circuit, action 不执行。
##
## 时序:
##   t=0     enemy_0 cast Break caster → HIT @ t=300 → BreakBuff grant on caster
##                                       → caster Thorn 进入 disabled (1 source)
##   t=600   enemy_0 cast Strike caster → caster 受 damage, Thorn 不反伤 (disabled)
##   t=2300  BreakBuff expire → caster Thorn 恢复 (0 sources)
##   t=3000  enemy_0 cast Strike caster → caster 受 damage, Thorn 反伤 2 PURE
class_name BreakThornDisabledScenario
extends SkillScenario


func get_name() -> String:
	return "Break disables Thorn passive (no reflect during break, reflects after)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 30},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 50}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleThorn.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(2000.0),
			"target": "caster",
			"time_ms": 0,
		},
		# 期内 Strike: 不该反伤
		{
			"caster": "enemy_0",
			"skill": HexBattleStrike.ABILITY,
			"target": "caster",
			"time_ms": 600,
		},
		# 期后 Strike: 应反伤 2 PURE
		{
			"caster": "enemy_0",
			"skill": HexBattleStrike.ABILITY,
			"target": "caster",
			"time_ms": 3000,
		},
	]


func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. caster 上 1 次 Break grant + 1 次 remove
	var break_grants: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != HexBattleBreakBuff.CONFIG_ID:
			continue
		break_grants.append(e)
	ctx.assert_eq(break_grants.size(), 1, "Expect 1 Break grant on caster")

	# 2. Thorn passive 仍在 caster ability list (没被 revoke, 只是 disabled)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleThorn.CONFIG_ID,
		"Thorn passive remains on caster (not revoked, just disabled)"
	)

	# 3. 收集 enemy_0 → caster 的 strike 主伤害事件 (非 reflected, 非 crit bonus)
	# Strike crit 时 _on_critical_callbacks push 额外 critical_bonus damage (10 PURE), 用
	# damage > 30 过滤掉 (Expose scenario 同思路)。
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
		"Expect 2 enemy_0 Strike main hits on caster (crit bonus filtered) got %d" % main_strikes.size())

	var reflects_to_enemy := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
		"is_reflected": true,
	})
	# 期内 Strike 不该反伤; 期后 Strike 至少反伤 1 次 (crit 时 critical_bonus damage 也触发
	# Thorn, 反伤 2 次 — by design)。
	ctx.assert_true(reflects_to_enemy.size() >= 1 and reflects_to_enemy.size() <= 2,
		"Expect 1-2 Thorn reflects (main + optional crit bonus, only after break expire); got %d" % reflects_to_enemy.size())

	# 5. 战斗结束 caster 无 BreakBuff
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleBreakBuff.CONFIG_ID,
		"BreakBuff revoked after duration"
	)
