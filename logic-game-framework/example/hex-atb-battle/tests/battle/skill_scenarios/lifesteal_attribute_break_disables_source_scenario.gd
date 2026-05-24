## Phase B · Break 禁用 VampiricTraining (属性来源), GeneralPassive 仍在但 no-op
##
## V1 契约:
##   Break 不禁用 HexBattleGeneralPassive (`intrinsic` tag, 不带 `passive` tag).
##   但可以禁用提供属性的普通 passive (VampiricTraining 带 `passive` tag).
##   属性归零后, GeneralPassive 自然 no-op, 吸血停止.
##
## 时序:
##   t=0      enemy_0 cast Break caster → caster Break buff 2000ms, VampiricTraining disabled
##                                         → caster attack_lifesteal_pct → 0
##   t=600    caster Strike enemy_0 → AttackLandedEvent → GeneralPassive 读 pct=0 → 早退
##   t=3000   (Break 已 expire) caster Strike enemy_0 → AttackLandedEvent →
##                                         VampiricTraining 已 re-enable, pct=0.5 → heal
##
## 关键: 战斗结束 caster 应仍持有 HexBattleGeneralPassive (Break 不禁它).
class_name LifestealAttributeBreakDisablesSourceScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "AttackLifesteal: Break disables VampiricTraining (stat source), GeneralPassive stays"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 100, "max_hp": 500, "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 5000, "atk": 0}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVampiricTraining.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [
		# enemy 先给 caster 上 2s Break -> 期内 VampiricTraining disabled
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(2000.0),
			"target": "caster",
			"time_ms": 0,
		},
		# 期内 Strike: 不该 heal (VampiricTraining disabled → pct=0)
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 600,
		},
		# 期后 Strike: 应 heal (VampiricTraining 恢复)
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 3000,
		},
	]


func get_max_ticks() -> int:
	# t=3000 第二次 Strike + 500ms timeline + idle countdown 1000ms ≈ t=4500;
	# 80 ticks * 100ms = 8000ms 给未来 hp_regen periodic tick 增量留 timing buffer.
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Capture BreakBuff grant instance id, then find its ABILITY_REMOVED frame.
	var break_inst_id := ""
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != HexBattleBreakBuff.CONFIG_ID:
			continue
		break_inst_id = str(ability_data.get("id", ""))
		break
	ctx.assert_true(not break_inst_id.is_empty(), "BreakBuff was granted on caster")

	var break_remove_frame := -1
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		if str(e.get("abilityInstanceId", "")) != break_inst_id:
			continue
		break_remove_frame = int(e.get("replay_frame", -1))
		break
	ctx.assert_true(break_remove_frame > 0,
		"BreakBuff should expire (got frame %d)" % break_remove_frame)

	# Heal events on caster: 全部应 AT/AFTER break_remove_frame
	var heal_events: Array = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "heal":
			continue
		if str(e.get("target_actor_id", "")) != ctx.caster_id:
			continue
		heal_events.append(e)
	ctx.assert_true(heal_events.size() >= 1,
		"Expect 1+ heal events (the post-break Strike); got %d" % heal_events.size())
	for h in heal_events:
		var frame := int(h.get("replay_frame", -1))
		ctx.assert_true(frame > break_remove_frame,
			"Heal frame %d must be AFTER break_remove_frame %d (heals during break should not occur)" % [
				frame, break_remove_frame
			])

	# 关键契约: HexBattleGeneralPassive 仍在 caster 身上 (Break 不禁 intrinsic)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleGeneralPassive.CONFIG_ID,
		"HexBattleGeneralPassive remains on caster (Break does not disable intrinsic)"
	)
	# VampiricTraining 也应在 (Break expire 后, 没被 revoke 只是曾 disabled)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleVampiricTraining.CONFIG_ID,
		"VampiricTraining remains on caster after Break expires"
	)
