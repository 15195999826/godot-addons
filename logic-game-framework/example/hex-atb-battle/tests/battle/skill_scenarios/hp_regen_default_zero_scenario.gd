## Phase C · 默认 hp_regen_per_sec = 0 时, periodic timeline 不产生 RegenerationEvent
##
## V1 契约:
## - 默认 hp_regen_per_sec = 0
## - HexBattleGeneralPassive 周期 timeline 仍正常 tick, RegenerateAction 进入但读 pct=0 → early return
## - replay 中没有 RegenerationEvent
## - caster HP 不变 (起步=最大)
class_name HpRegenDefaultZeroScenario
extends SkillScenario


func get_name() -> String:
	return "HP Regen: default per_sec=0 → no RegenerationEvent"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 80, "max_hp": 100},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0}],
	}


# 不施放任何技能, 单纯让 GeneralPassive periodic timeline tick.
func get_actions() -> Array[Dictionary]:
	return [{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0}]


func get_max_ticks() -> int:
	return 60  # ~6 秒 模拟时间


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var regen_events := ctx.events_of_kind("regeneration")
	ctx.assert_eq(regen_events.size(), 0,
		"Expect 0 RegenerationEvent when hp_regen_per_sec=0 (got %d)" % regen_events.size())
	# caster HP 不应受 regen 影响 (Strike 自伤无, enemy.atk=0 也无反弹)
	var final_hp := ctx.actor_final_hp(ctx.caster_id)
	ctx.assert_float_eq(final_hp, 80.0,
		"caster HP unchanged at 80 (no regen, no damage taken)", 0.1)
