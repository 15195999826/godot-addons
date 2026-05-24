## Phase C · Break 禁用 VitalitySurge → 期内不回血; GeneralPassive 仍 tick (intrinsic)
##
## V1 契约:
## - Break 不禁用 HexBattleGeneralPassive (intrinsic, 无 `passive` tag)
## - 但禁用 VitalitySurge (passive, 提供 hp_regen_per_sec)
## - 期内: attribute 归 0 → regen amount=0 → action early-exit → 无 RegenerationEvent
## - 期后: VitalitySurge re-enable → regen 恢复
##
## 时序 (Break 2000ms):
##   t=0     Break grant on caster, VitalitySurge disabled
##   t=0-2000  GeneralPassive timeline 每秒 tick, 但 attribute=0 → no RegenerationEvent
##   t=2000  Break expire, VitalitySurge 恢复
##   t=2000-4000  regen 正常每秒恢复 (期望至少 1-2 个 event)
class_name HpRegenBreakDisablesSourceScenario
extends SkillScenario


func get_name() -> String:
	return "HP Regen: Break disables VitalitySurge stat source; GeneralPassive intrinsic stays"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 50, "max_hp": 200, "atk": 0},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 5000, "atk": 0}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVitalitySurge.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [
		# enemy 给 caster 上 2s Break
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(2000.0),
			"target": "caster",
			"time_ms": 0,
		},
	]


func get_max_ticks() -> int:
	return 60  # ~6 秒, Break 2 秒 + 4 秒 regen 余量


func get_min_ticks() -> int:
	return 50  # 强制 5 秒, 让 Break 过期 (t=2000) + 之后 ≥1 regen tick


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Break expire frame
	var break_inst_id := ""
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != HexBattleBreakBuff.CONFIG_ID:
			continue
		break_inst_id = str(ability_data.get("id", ""))
		break
	ctx.assert_true(not break_inst_id.is_empty(), "BreakBuff granted on caster")

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

	# 所有 RegenerationEvent 必须发生在 break_remove_frame 之后
	var regen_events := ctx.events_of_kind("regeneration")
	for r in regen_events:
		var frame := int(r.get("replay_frame", -1))
		ctx.assert_true(frame > break_remove_frame,
			"regen frame %d must be AFTER break_remove_frame %d" % [frame, break_remove_frame])

	# 期后至少 1 个 regen tick (Break 期满后, regen 恢复)
	ctx.assert_true(regen_events.size() >= 1,
		"Expect >=1 RegenerationEvent after Break expires (got %d)" % regen_events.size())

	# GeneralPassive 仍 present (intrinsic, Break 不禁)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleGeneralPassive.CONFIG_ID,
		"HexBattleGeneralPassive remains on caster (Break does not disable intrinsic)"
	)
	# VitalitySurge 也 present (Break expire 后, 没被 revoke)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleVitalitySurge.CONFIG_ID,
		"VitalitySurge remains on caster after Break expires"
	)
