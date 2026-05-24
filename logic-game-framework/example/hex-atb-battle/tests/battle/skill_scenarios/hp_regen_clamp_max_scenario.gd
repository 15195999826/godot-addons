## Phase C · 满血/接近满血时 regen actual_amount clamp 到 max_hp
##
## V1 契约:
## - amount = per_sec * period_seconds (理论恢复)
## - actual_amount = min(hp + amount, max_hp) - hp (实际恢复, overheal 不补 shield)
## - 满血时 actual_amount = 0, 事件仍 push (consumer 自查)
##
## 设定 caster hp=98 max=100, regen 5/s:
##   tick 1: hp 98→100, amount=5, actual=2
##   tick 2: hp 100→100, amount=5, actual=0 (clamp 已达 max)
##   tick 3+: 同上 actual=0
class_name HpRegenClampMaxScenario
extends SkillScenario


func get_name() -> String:
	return "HP Regen: actual_amount clamp to max_hp on overheal"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 98, "max_hp": 100, "atk": 0},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVitalitySurge.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0}]


func get_max_ticks() -> int:
	return 40  # ~4 秒, 至少 3 tick


func get_min_ticks() -> int:
	return 35  # 强制 ~3.5 秒, 保证 ≥3 regen tick fire


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var regen_events := ctx.events_of_kind("regeneration")
	ctx.assert_true(regen_events.size() >= 2,
		"Expect >=2 RegenerationEvent (got %d)" % regen_events.size())
	if regen_events.size() < 1:
		return
	# tick 1 应当 actual_amount = 2 (98→100)
	var first := regen_events[0] as Dictionary
	ctx.assert_float_eq(first.get("amount", 0.0) as float, 5.0,
		"first regen amount = 5", 0.01)
	ctx.assert_float_eq(first.get("actual_amount", 0.0) as float, 2.0,
		"first regen actual_amount clamped to 2 (98+5 → 100)", 0.01)
	# tick 2+ 应当 actual_amount = 0 (已满)
	for i in range(1, regen_events.size()):
		var e := regen_events[i] as Dictionary
		ctx.assert_float_eq(e.get("amount", 0.0) as float, 5.0,
			"regen[%d] amount = 5" % i, 0.01)
		ctx.assert_float_eq(e.get("actual_amount", 0.0) as float, 0.0,
			"regen[%d] actual_amount = 0 (overheal clamped)" % i, 0.01)
	# 终态 hp = max
	var final_hp := ctx.actor_final_hp(ctx.caster_id)
	ctx.assert_float_eq(final_hp, 100.0, "caster hp capped at max_hp 100", 0.1)
