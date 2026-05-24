## Phase C · VitalitySurge → 周期 RegenerationEvent + HP 上升 + 不产 HealEvent
##
## V1 契约:
## - VitalitySurge 提供 +5 hp/s
## - periodic timeline 每 1s tick 一次, 每次 RegenerationEvent amount=5, actual_amount=5 (未到 max)
## - caster HP 起 50, max 200 → 6 秒后 ≈ 80
## - 不产生 HealEvent (kind="regeneration" ≠ "heal")
## - 不通过 HexBattleHealAction (没有 on_heal/post_heal 钩子触发)
class_name HpRegenBasicScenario
extends SkillScenario


const CASTER_START_HP := 50.0
const CASTER_MAX_HP := 200.0


func get_name() -> String:
	return "HP Regen: VitalitySurge 5 hp/s → periodic RegenerationEvent, no HealEvent"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": CASTER_START_HP, "max_hp": CASTER_MAX_HP, "atk": 0},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVitalitySurge.ABILITY]


# 单 Strike 让 harness 跑战斗循环; max_ticks 大到能跑出 ≥3 个 regen tick.
func get_actions() -> Array[Dictionary]:
	return [{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0}]


func get_max_ticks() -> int:
	return 60  # ~6 秒, 应有 5-6 个 regen tick (5+5+5+5+5=25 hp 恢复)


func get_min_ticks() -> int:
	return 50  # 强制 5 秒, 至少 3-5 个 regen tick


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. 至少 3 条 RegenerationEvent (period=1s, max_ticks 6 秒)
	var regen_events := ctx.events_of_kind("regeneration")
	ctx.assert_true(regen_events.size() >= 3,
		"Expect >=3 RegenerationEvent (got %d)" % regen_events.size())

	# 2. 每条 RegenerationEvent 的字段合规
	for e in regen_events:
		ctx.assert_eq(e.get("target_actor_id", ""), ctx.caster_id,
			"regen target = caster")
		ctx.assert_eq(e.get("resource", ""), "hp", "regen resource = hp")
		ctx.assert_float_eq(e.get("amount", 0.0) as float, HexBattleVitalitySurge.HP_PER_SEC,
			"regen amount = per_sec * 1.0 = %.1f" % HexBattleVitalitySurge.HP_PER_SEC, 0.01)
		ctx.assert_eq(e.get("source", ""), "general_passive",
			"regen source = general_passive (HexBattleGeneralPassive)")

	# 3. 不产生 HealEvent
	var heal_events := ctx.events_of_kind("heal")
	ctx.assert_eq(heal_events.size(), 0,
		"HP regen must NOT produce any HealEvent (got %d)" % heal_events.size())

	# 4. caster HP 上升
	var final_hp := ctx.actor_final_hp(ctx.caster_id)
	ctx.assert_true(final_hp > CASTER_START_HP,
		"caster HP rose from %.1f to %.1f via regen" % [CASTER_START_HP, final_hp])
